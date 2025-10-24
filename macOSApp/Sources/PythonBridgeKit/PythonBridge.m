#import "PythonBridge.h"

static NSError *PythonBridgeLastError = nil;

@interface PythonBridge ()

@property(nonatomic, strong) NSString *scriptPath;
@property(nonatomic, strong) NSString *pythonExecutable;

@end

@implementation PythonBridge

+ (NSError *)lastError {
    return PythonBridgeLastError;
}

- (instancetype)initWithBundleResource:(NSString *)resourceName {
    self = [super init];
    if (self) {
        PythonBridgeLastError = nil;
        _scriptPath = [self findScriptPath:resourceName];
        if (!_scriptPath) {
            [self recordErrorWithCode:100 description:@"Python control script not found in bundle."];
            return nil;
        }

        _pythonExecutable = [self resolvePythonExecutable];
        if (!_pythonExecutable) {
            return nil;
        }

        if (![self validatePythonEnvironment]) {
            return nil;
        }
    }
    return self;
}

- (NSString *)findScriptPath:(NSString *)resourceName {
    NSBundle *bundle = [NSBundle mainBundle];

    NSString *envOverride = [[[NSProcessInfo processInfo] environment] objectForKey:@"PYTHON_CONTROL_PATH"];
    if (envOverride.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:envOverride]) {
        return envOverride;
    }

    NSURL *resourceURL = [bundle URLForResource:resourceName withExtension:@"py" subdirectory:@"Python"];
    if (resourceURL) {
        return resourceURL.path;
    }

    NSURL *currentURL = bundle.bundleURL;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSInteger depth = 0; depth < 8 && currentURL != nil; depth++) {
        NSURL *candidateURL = [currentURL URLByAppendingPathComponent:@"python/control.py"];
        if ([fileManager fileExistsAtPath:candidateURL.path]) {
            return candidateURL.path;
        }
        currentURL = [currentURL URLByDeletingLastPathComponent];
    }

    return nil;
}

- (void)recordErrorWithCode:(NSInteger)code description:(NSString *)description {
    PythonBridgeLastError = [NSError errorWithDomain:@"PythonBridgeError"
                                                code:code
                                            userInfo:@{NSLocalizedDescriptionKey : description}];
}

- (NSString *)resolvePythonExecutable {
    NSString *envOverride = [[[NSProcessInfo processInfo] environment] objectForKey:@"PYTHON_EXECUTABLE"];
    if (envOverride.length > 0 && [[NSFileManager defaultManager] isExecutableFileAtPath:envOverride]) {
        return envOverride;
    }

    NSPipe *outputPipe = [NSPipe pipe];
    NSTask *whichTask = [[NSTask alloc] init];
    whichTask.launchPath = @"/usr/bin/env";
    whichTask.arguments = @[@"which", @"python3"];
    whichTask.standardOutput = outputPipe;
    whichTask.standardError = outputPipe;

    @try {
        [whichTask launch];
    } @catch (NSException *exception) {
        [self recordErrorWithCode:101 description:exception.reason ?: @"Failed to locate python3 interpreter."];
        return nil;
    }

    [whichTask waitUntilExit];
    NSData *data = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSString *path = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (whichTask.terminationStatus != 0 || path.length == 0) {
        [self recordErrorWithCode:102 description:@"python3 interpreter not found. Install Python 3 with PyObjC."];
        return nil;
    }

    return path;
}

- (NSDictionary<NSString *, NSString *> *)pythonEnvironment {
    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    NSString *scriptDir = [self.scriptPath stringByDeletingLastPathComponent];
    NSString *sitePackages = [scriptDir stringByAppendingPathComponent:@"site-packages"];

    NSMutableArray<NSString *> *pythonPaths = [NSMutableArray array];
    if (scriptDir.length > 0) {
        [pythonPaths addObject:scriptDir];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:sitePackages]) {
        [pythonPaths addObject:sitePackages];
    }

    NSString *existing = env[@"PYTHONPATH"];
    if (existing.length > 0) {
        [pythonPaths addObject:existing];
    }

    env[@"PYTHONPATH"] = [pythonPaths componentsJoinedByString:@":"];
    env[@"PYTHONUNBUFFERED"] = @"1";
    return env;
}

- (BOOL)validatePythonEnvironment {
    NSPipe *stderrPipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.arguments = @[self.pythonExecutable, @"-c", @"import objc"];
    task.standardError = stderrPipe;
    task.environment = [self pythonEnvironment];

    @try {
        [task launch];
    } @catch (NSException *exception) {
        [self recordErrorWithCode:103 description:exception.reason ?: @"Unable to launch python interpreter."];
        return NO;
    }

    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        NSString *stderrString = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *message = [NSString stringWithFormat:@"Python environment error: %@", stderrString];
        [self recordErrorWithCode:104 description:message];
        return NO;
    }

    return YES;
}

- (NSArray<NSString *> *)fullCommandFor:(NSString *)command arguments:(NSArray<NSString *> *)arguments {
    NSMutableArray<NSString *> *cmd = [NSMutableArray arrayWithObjects:self.pythonExecutable, self.scriptPath, command, nil];
    [cmd addObjectsFromArray:arguments];
    return [cmd copy];
}

- (NSString *)runCommand:(NSString *)command
              arguments:(NSArray<NSString *> *)arguments
                  error:(NSError **)error {
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.arguments = [self fullCommandFor:command arguments:arguments];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;
    task.environment = [self pythonEnvironment];

    @try {
        [task launch];
    } @catch (NSException *exception) {
        [self recordErrorWithCode:105 description:exception.reason ?: @"Failed to launch python process."];
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridgeError"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: @"Failed to launch python process."}];
        }
        return nil;
    }

    [task waitUntilExit];

    NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
    NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];

    if (task.terminationStatus != 0) {
        NSString *stderrString = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
        [self recordErrorWithCode:task.terminationStatus description:stderrString.length ? stderrString : @"Python process exited with error."];
        if (error) {
            *error = [NSError errorWithDomain:@"PythonBridgeError"
                                         code:task.terminationStatus
                                     userInfo:@{NSLocalizedDescriptionKey : stderrString}];
        }
        return nil;
    }

    return [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
}

- (void)runCommand:(NSString *)command
         arguments:(NSArray<NSString *> *)arguments
         completion:(void (^)(NSString *_Nullable output, NSString *_Nullable errorOutput, NSInteger status))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSPipe *stdoutPipe = [NSPipe pipe];
        NSPipe *stderrPipe = [NSPipe pipe];

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/env";
        task.arguments = [self fullCommandFor:command arguments:arguments];
        task.standardOutput = stdoutPipe;
        task.standardError = stderrPipe;
        task.environment = [self pythonEnvironment];

        @try {
            [task launch];
        } @catch (NSException *exception) {
            [self recordErrorWithCode:105 description:exception.reason ?: @"Failed to launch python process."];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, exception.reason ?: @"Launch failed", -1);
            });
            return;
        }

        [task waitUntilExit];

        NSString *output = [[NSString alloc] initWithData:[[stdoutPipe fileHandleForReading] readDataToEndOfFile]
                                                 encoding:NSUTF8StringEncoding];
        NSString *errorOutput = [[NSString alloc] initWithData:[[stderrPipe fileHandleForReading] readDataToEndOfFile]
                                                     encoding:NSUTF8StringEncoding];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.terminationStatus != 0) {
                [self recordErrorWithCode:task.terminationStatus description:errorOutput ?: @"Python process exited with error."];
            }
            completion(output, errorOutput, task.terminationStatus);
        });
    });
}

@end
