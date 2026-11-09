// Separate processes exercise startup selection, persistence and isolation without
// launching the GUI or reusing the test runner's cached defaults/path singletons.
#import <Foundation/Foundation.h>
#import "NppPaths.h"
#import "NppCommandLineParams.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NppCommandLineParams *cli = [[NppCommandLineParams alloc] initWithArgc:argc argv:argv];
        NSError *error = nil;
        if (cli.settingsDir != nil && !NppConfigureSettingsDirectory(cli.settingsDir, &error)) {
            fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return 2;
        }
        if (argc < 3) return 2;
        NSString *action = [NSString stringWithUTF8String:argv[1]];
        NSString *key = [NSString stringWithUTF8String:argv[2]];
        NSUserDefaults *defaults = NppUserDefaults();
        if ([action isEqualToString:@"--write"]) {
            if (argc < 4) return 2;
            NSData *json = [[NSString stringWithUTF8String:argv[3]] dataUsingEncoding:NSUTF8StringEncoding];
            id value = [NSJSONSerialization JSONObjectWithData:json options:NSJSONReadingFragmentsAllowed error:&error];
            if (!value || value == [NSNull null]) return 2;
            [defaults setObject:value forKey:key];
        } else if ([action isEqualToString:@"--remove"]) {
            [defaults removeObjectForKey:key];
        } else if (![action isEqualToString:@"--read"]) {
            return 2;
        }
        if (!NppSaveProfilePreferences(&error)) {
            fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return 2;
        }
        [defaults synchronize];
        NSDictionary *output = @{@"directory": NppConfigDir(), @"value": [defaults objectForKey:key] ?: [NSNull null]};
        NSData *json = [NSJSONSerialization dataWithJSONObject:output options:0 error:&error];
        if (!json) return 2;
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}
