//  NppPaths.h
//  Centralised resolver for the NP++ user-data directory.
//
//  NP++ keeps user configuration, plugins, backups, session state and the
//  like under a single base directory. Historically that was the hidden
//  ~/.nextpad++ folder (a straight port of %APPDATA%\NP++ on Windows).
//  macOS applications are expected to store this kind of data under
//  ~/Library/Application Support/<AppName> instead (see GitHub issue #67), so
//  that is the base directory used now. NppConfigDir() migrates an existing
//  ~/.nextpad++ folder to the new location once, on first use.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Base user-data directory: the selected -settingsDir, otherwise
/// ~/Library/Application Support/NP++.
/// The directory is created if it does not exist. The first call after upgrading
/// from a build that used ~/.nextpad++ migrates that legacy folder into the
/// default profile only.
FOUNDATION_EXPORT NSString *NppConfigDir(void);

/// Select an independent configuration directory before any app settings are used.
/// Relative paths are resolved against the launch working directory. Custom
/// profiles never migrate the default profile's legacy files.
FOUNDATION_EXPORT BOOL NppConfigureSettingsDirectory(NSString *path, NSError * _Nullable * _Nullable error);

/// The current profile's preferences; the default profile uses standard defaults.
FOUNDATION_EXPORT NSUserDefaults *NppUserDefaults(void);

/// Persist custom-profile preferences to preferences.plist in its settings directory.
FOUNDATION_EXPORT BOOL NppSaveProfilePreferences(NSError * _Nullable * _Nullable error);

/// Convenience: NppConfigDir() joined with a relative subpath, e.g.
/// NppConfigSubpath(@"plugins") or NppConfigSubpath(@"shortcuts.xml").
FOUNDATION_EXPORT NSString *NppConfigSubpath(NSString *relativePath);

/// The legacy ~/.nextpad++ directory. Exposed for migration/diagnostics only;
/// normal code should use NppConfigDir()/NppConfigSubpath().
FOUNDATION_EXPORT NSString *NppLegacyConfigDir(void);

NS_ASSUME_NONNULL_END
