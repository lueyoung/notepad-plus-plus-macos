//  NppPaths.mm
//  See NppPaths.h.

#import "NppPaths.h"
#import <CommonCrypto/CommonDigest.h>
#include <atomic>

static NSString *sSettingsDirectory;
static NSString *sPreferencesSuite;
static NSUserDefaults *sProfileDefaults;
static id sPreferencesObserver;
static std::atomic_bool sConfigurationUsed{false};

BOOL NppSaveProfilePreferences(NSError **error) {
    if (!sProfileDefaults) return YES;
    @synchronized (sProfileDefaults) {
        NSDictionary *values = [sProfileDefaults persistentDomainForName:sPreferencesSuite] ?: @{};
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:values
                             format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
        return data && [data writeToFile:[sSettingsDirectory stringByAppendingPathComponent:@"preferences.plist"]
                                options:NSDataWritingAtomic error:error];
    }
}

BOOL NppConfigureSettingsDirectory(NSString *path, NSError **error) {
    if (path.length == 0) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError
            userInfo:@{NSLocalizedDescriptionKey: @"Set a non-empty -settingsDir=path."}];
        return NO;
    }
    if (sConfigurationUsed.load(std::memory_order_relaxed) || sSettingsDirectory) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
            userInfo:@{NSLocalizedDescriptionKey: @"Select the settings directory before initializing app preferences."}];
        return NO;
    }
    NSString *resolved = path.stringByExpandingTildeInPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!resolved.isAbsolutePath)
        resolved = [fm.currentDirectoryPath stringByAppendingPathComponent:resolved];
    resolved = resolved.stringByStandardizingPath;
    if (![fm createDirectoryAtPath:resolved withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    resolved = resolved.stringByResolvingSymlinksInPath;
    if (![fm isWritableFileAtPath:resolved]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError
            userInfo:@{NSLocalizedDescriptionKey: @"The settings directory is not writable."}];
        return NO;
    }

    NSString *preferencesPath = [resolved stringByAppendingPathComponent:@"preferences.plist"];
    NSDictionary *stored = @{};
    if ([fm fileExistsAtPath:preferencesPath]) {
        NSData *data = [NSData dataWithContentsOfFile:preferencesPath options:0 error:error];
        if (!data) return NO;
        id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                             format:nil error:error];
        if (![plist isKindOfClass:[NSDictionary class]]) {
            if (error && !*error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                userInfo:@{NSLocalizedDescriptionKey: @"The profile's preferences.plist must contain a dictionary."}];
            return NO;
        }
        stored = plist;
    }

    // A suite isolates all app-owned defaults, including preferences not in config.xml.
    // The plist is authoritative so moving or recreating a profile cannot resurrect
    // stale preferences from the system's defaults cache.
    NSData *pathData = [resolved dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(pathData.bytes, (CC_LONG)pathData.length, digest);
    NSMutableString *suite = [NSMutableString stringWithString:@"org.npp.mac.profile."];
    for (NSUInteger i = 0; i < sizeof(digest); ++i) [suite appendFormat:@"%02x", digest[i]];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    if (!defaults) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
            userInfo:@{NSLocalizedDescriptionKey: @"Could not initialize the profile's preferences."}];
        return NO;
    }
    [defaults setPersistentDomain:stored forName:suite];
    sSettingsDirectory = resolved;
    sPreferencesSuite = suite;
    sProfileDefaults = defaults;
    sPreferencesObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSUserDefaultsDidChangeNotification object:defaults queue:nil
        usingBlock:^(NSNotification *notification) {
            NSError *saveError = nil;
            if (!NppSaveProfilePreferences(&saveError))
                NSLog(@"[Config] Could not save profile preferences: %@", saveError);
        }];
    return YES;
}

NSUserDefaults *NppUserDefaults(void) {
    sConfigurationUsed.store(true, std::memory_order_relaxed);
    return sProfileDefaults ?: [NSUserDefaults standardUserDefaults];
}

NSString *NppLegacyConfigDir(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".npp"];
}

static NSString *NppComputeConfigDir(void) {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    if (appSupport.length == 0) {
        // Should not happen on macOS, but keep a sane fallback.
        appSupport = [NSHomeDirectory()
            stringByAppendingPathComponent:@"Library/Application Support"];
    }
    return [appSupport stringByAppendingPathComponent:@"NP++"];
}

// Recursively move everything under `src` into `dst`, NEVER overwriting an
// existing destination. Returns YES iff `src` ends up fully drained (so the
// caller may remove it).
//   - No collision: a plain move (atomic same-volume rename) handles a file or a
//     whole subtree at once; falls back to copy+delete across volumes.
//   - Both sides are directories: merge child-by-child with the same rule.
//   - File-vs-existing collision: the destination (newer) copy wins and the
//     legacy item is left in place — nothing is lost.
static BOOL NppMergeMove(NSFileManager *fm, NSString *src, NSString *dst) {
    BOOL srcIsDir = NO;
    if (![fm fileExistsAtPath:src isDirectory:&srcIsDir]) return YES;  // vanished

    if (![fm fileExistsAtPath:dst]) {
        NSError *moveErr = nil;
        if ([fm moveItemAtPath:src toPath:dst error:&moveErr]) return YES;
        NSError *copyErr = nil;
        if ([fm copyItemAtPath:src toPath:dst error:&copyErr]) {
            [fm removeItemAtPath:src error:NULL];
            return YES;
        }
        NSLog(@"[Config] Failed to migrate %@ (move: %@; copy: %@)", src, moveErr, copyErr);
        return NO;
    }

    BOOL dstIsDir = NO;
    [fm fileExistsAtPath:dst isDirectory:&dstIsDir];
    if (!srcIsDir || !dstIsDir) {
        NSLog(@"[Config] Keeping %@; legacy copy left at %@", dst, src);
        return NO;
    }

    BOOL drained = YES;
    for (NSString *name in [fm contentsOfDirectoryAtPath:src error:NULL]) {
        if (!NppMergeMove(fm, [src stringByAppendingPathComponent:name],
                              [dst stringByAppendingPathComponent:name]))
            drained = NO;
    }
    if (drained) [fm removeItemAtPath:src error:NULL];
    return drained;
}

// One-time migration of a legacy ~/.nextpad++ tree into the new base dir.
//
// The new base dir may ALREADY EXIST on a first upgrade — e.g. NppLocalizer
// eagerly creates ~/Library/Application Support/NP++/localization. So
// "new dir exists" is NOT a valid "already migrated" sentinel; treating it as
// one would strand the user's real config/session/plugins in ~/.nextpad++.
// Instead we recursively merge the legacy tree into the new one, never
// clobbering anything already present, and remove the legacy dir only once it
// is fully drained (so a partial failure leaves un-migrated items in place).
static void NppMigrateLegacyIfNeeded(NSString *newDir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *legacy = NppLegacyConfigDir();

    BOOL legacyIsDir = NO;
    BOOL hasLegacy = [fm fileExistsAtPath:legacy isDirectory:&legacyIsDir] && legacyIsDir;
    if (!hasLegacy) return;                    // nothing to migrate (fresh install)

    [fm createDirectoryAtPath:newDir withIntermediateDirectories:YES
                   attributes:nil error:NULL];

    if (NppMergeMove(fm, legacy, newDir))
        NSLog(@"[Config] Migrated legacy %@ into %@", legacy, newDir);
    else
        NSLog(@"[Config] Partially migrated %@ into %@ (some items kept in place)",
              legacy, newDir);
}

NSString *NppConfigDir(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sConfigurationUsed.store(true, std::memory_order_relaxed);
        dir = sSettingsDirectory ?: NppComputeConfigDir();
        if (!sSettingsDirectory) NppMigrateLegacyIfNeeded(dir);
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    });
    return dir;
}

NSString *NppConfigSubpath(NSString *relativePath) {
    return [NppConfigDir() stringByAppendingPathComponent:relativePath];
}
