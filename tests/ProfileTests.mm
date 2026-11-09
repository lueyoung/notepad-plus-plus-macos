#import <XCTest/XCTest.h>

@interface ProfileTests : XCTestCase
@property(nonatomic, copy) NSString *tempDir;
@end

@implementation ProfileTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"npp-profile-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.tempDir stringByAppendingPathComponent:@"home"]
                             withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (NSDictionary *)probe:(NSArray<NSString *> *)arguments status:(int)status {
    NSString *build = [NSBundle bundleForClass:self.class].bundlePath.stringByDeletingLastPathComponent;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[build stringByAppendingPathComponent:@"NppConfigProbe"]];
    task.arguments = arguments;
    task.currentDirectoryURL = [NSURL fileURLWithPath:self.tempDir];
    NSMutableDictionary *environment = NSProcessInfo.processInfo.environment.mutableCopy;
    environment[@"CFFIXED_USER_HOME"] = [self.tempDir stringByAppendingPathComponent:@"home"];
    task.environment = environment;
    NSPipe *output = [NSPipe pipe];
    NSPipe *errors = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = errors;
    NSError *error = nil;
    BOOL launched = [task launchAndReturnError:&error];
    XCTAssertTrue(launched, @"Could not launch config probe: %@", error);
    if (!launched) return @{};
    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    NSData *errorData = [errors.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    XCTAssertEqual(task.terminationStatus, status, @"%@", [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding]);
    if (status != 0) return @{};
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNotNil(result, @"Probe output: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    return result ?: @{};
}

- (void)testProfilesPersistAndDoNotSharePreferences {
    NSString *alpha = @"-settingsDir=profiles/中文 alpha";
    NSString *beta = @"-settingsDir=profiles/beta";
    [self probe:@[@"--write", @"wordWrap", @"true", alpha] status:0];
    XCTAssertEqualObjects(([self probe:@[@"--read", @"wordWrap", alpha] status:0][@"value"]), @YES);
    XCTAssertEqualObjects(([self probe:@[@"--read", @"wordWrap", beta] status:0][@"value"]), NSNull.null);
    XCTAssertEqualObjects(([self probe:@[@"--read", @"wordWrap"] status:0][@"value"]), NSNull.null);
    [self probe:@[@"--write", @"wordWrap", @"false"] status:0];
    XCTAssertEqualObjects(([self probe:@[@"--read", @"wordWrap", alpha] status:0][@"value"]), @YES);
    NSString *preferences = [self.tempDir stringByAppendingPathComponent:@"profiles/中文 alpha/preferences.plist"];
    XCTAssertEqualObjects([NSDictionary dictionaryWithContentsOfFile:preferences][@"wordWrap"], @YES);
}

- (void)testApplicationHelpDoesNotInitializeProfiles {
    NSString *home = [self.tempDir stringByAppendingPathComponent:@"home"];
    NSString *legacy = [home stringByAppendingPathComponent:@".npp"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:legacy withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *sentinel = [legacy stringByAppendingPathComponent:@"toolbarLayout.xml"];
    [@"legacy" writeToFile:sentinel atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *build = [NSBundle bundleForClass:self.class].bundlePath.stringByDeletingLastPathComponent;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[build stringByAppendingPathComponent:@"NP++.app/Contents/MacOS/NP++"]];
    NSString *custom = [self.tempDir stringByAppendingPathComponent:@"custom"];
    task.arguments = @[@"--help", [@"-settingsDir=" stringByAppendingString:custom]];
    NSMutableDictionary *environment = NSProcessInfo.processInfo.environment.mutableCopy;
    environment[@"CFFIXED_USER_HOME"] = home;
    task.environment = environment;
    task.standardOutput = NSPipe.pipe;
    NSError *error = nil;
    BOOL launched = [task launchAndReturnError:&error];
    XCTAssertTrue(launched, @"Could not launch the actual app: %@", error);
    if (!launched) return;
    [task waitUntilExit];
    XCTAssertEqual(task.terminationStatus, 0);
    XCTAssertTrue([fm fileExistsAtPath:sentinel], @"--help must not migrate a legacy profile before main()");
    XCTAssertFalse([fm fileExistsAtPath:[home stringByAppendingPathComponent:@"Library/Application Support/NP++"]]);
    XCTAssertFalse([fm fileExistsAtPath:custom]);
}

- (void)testCustomDirectoryDoesNotMigrateDefaultProfile {
    NSString *legacy = [self.tempDir stringByAppendingPathComponent:@"home/.npp"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:legacy withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *sentinel = [legacy stringByAppendingPathComponent:@"config.xml"];
    [@"legacy" writeToFile:sentinel atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSDictionary *result = [self probe:@[@"--read", @"wordWrap", @"-settingsDir=profiles/custom"] status:0];
    NSString *resolved = [[self.tempDir stringByAppendingPathComponent:@"profiles/custom"] stringByResolvingSymlinksInPath];
    XCTAssertEqualObjects(result[@"directory"], resolved);
    XCTAssertTrue([fm fileExistsAtPath:sentinel]);
    XCTAssertFalse([fm fileExistsAtPath:[resolved stringByAppendingPathComponent:@"config.xml"]]);

    result = [self probe:@[@"--read", @"wordWrap"] status:0];
    XCTAssertEqualObjects([NSString stringWithContentsOfFile:[result[@"directory"] stringByAppendingPathComponent:@"config.xml"]
                                                  encoding:NSUTF8StringEncoding error:nil], @"legacy");
    XCTAssertFalse([fm fileExistsAtPath:sentinel]);
}

- (void)testMovedProfileLoadsItsOwnPreferencesFile {
    [self probe:@[@"--write", @"tabWidth", @"8", @"-settingsDir=first"] status:0];
    NSFileManager *fm = NSFileManager.defaultManager;
    XCTAssertTrue([fm copyItemAtPath:[self.tempDir stringByAppendingPathComponent:@"first"]
                             toPath:[self.tempDir stringByAppendingPathComponent:@"second"] error:nil]);
    XCTAssertEqualObjects(([self probe:@[@"--read", @"tabWidth", @"-settingsDir=second"] status:0][@"value"]), @8);
    [self probe:@[@"--remove", @"tabWidth", @"-settingsDir=second"] status:0];
    XCTAssertEqualObjects(([self probe:@[@"--read", @"tabWidth", @"-settingsDir=second"] status:0][@"value"]), NSNull.null);
    XCTAssertEqualObjects(([self probe:@[@"--read", @"tabWidth", @"-settingsDir=first"] status:0][@"value"]), @8);
}

- (void)testEquivalentPathsSelectTheSameProfile {
    [self probe:@[@"--write", @"marker", @"\"saved\"", @"-settingsDir=profiles/a"] status:0];
    NSDictionary *result = [self probe:@[@"--read", @"marker", @"-settingsDir=./profiles/../profiles/a"] status:0];
    XCTAssertEqualObjects(result[@"value"], @"saved");
}

- (void)testInvalidDirectoryFailsWithoutFallingBack {
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"file"];
    [@"file" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self probe:@[@"--read", @"marker", @"-settingsDir=file"] status:2];
    [self probe:@[@"--read", @"marker", @"-settingsDir="] status:2];
    NSString *standard = [self.tempDir stringByAppendingPathComponent:@"home/Library/Application Support/NP++"];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:standard]);
}

- (void)testMalformedPreferencesAreNotOverwritten {
    NSString *profile = [self.tempDir stringByAppendingPathComponent:@"broken"];
    [NSFileManager.defaultManager createDirectoryAtPath:profile withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [profile stringByAppendingPathComponent:@"preferences.plist"];
    NSData *input = [@"not a plist" dataUsingEncoding:NSUTF8StringEncoding];
    [input writeToFile:path atomically:YES];
    [self probe:@[@"--read", @"marker", @"-settingsDir=broken"] status:2];
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:path], input);
}

@end
