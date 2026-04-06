#import "PythonBridge.h"

static NSError *PythonBridgeLastError = nil;

@interface PythonBridge ()

@property(nonatomic, strong) NSString *scriptPath;
@property(nonatomic, strong) NSString *pythonExecutable;
@property(nonatomic, strong, nullable) NSString *pythonHome;

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
        _pythonHome = [self pythonHomeForExecutable:_pythonExecutable];

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
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (envOverride.length > 0) {
        [candidates addObject:envOverride];
    }

    NSString *bundledExecutable = [self bundledPythonExecutable];
    if (bundledExecutable.length > 0) {
        [candidates addObject:bundledExecutable];
    }

    // Prefer system/CLT Python because it is the most likely to have compatible PyObjC.
    [candidates addObject:@"/usr/bin/python3"];
    [candidates addObject:@"/Library/Developer/CommandLineTools/usr/bin/python3"];

    NSPipe *outputPipe = [NSPipe pipe];
    NSTask *whichTask = [[NSTask alloc] init];
    whichTask.launchPath = @"/usr/bin/env";
    whichTask.arguments = @[@"which", @"python3"];
    whichTask.standardOutput = outputPipe;
    whichTask.standardError = outputPipe;

    @try {
        [whichTask launch];
        [whichTask waitUntilExit];
    } @catch (NSException *exception) {
        [self recordErrorWithCode:101 description:exception.reason ?: @"Failed to locate python3 interpreter."];
        return nil;
    }

    NSData *data = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSString *resolvedFromPath = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (whichTask.terminationStatus == 0 && resolvedFromPath.length > 0) {
        [candidates addObject:resolvedFromPath];
    }

    NSMutableOrderedSet<NSString *> *uniqueCandidates = [NSMutableOrderedSet orderedSet];
    for (NSString *candidate in candidates) {
        if (candidate.length > 0) {
            [uniqueCandidates addObject:candidate];
        }
    }

    NSString *lastError = @"";
    for (NSString *candidate in uniqueCandidates) {
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
            continue;
        }

        NSPipe *stderrPipe = [NSPipe pipe];
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/env";
        task.arguments = @[candidate, @"-c", @"import objc"];
        task.standardError = stderrPipe;
        task.environment = [self pythonEnvironmentForExecutable:candidate];

        @try {
            [task launch];
            [task waitUntilExit];
        } @catch (NSException *exception) {
            lastError = exception.reason ?: @"Failed to launch candidate python interpreter.";
            continue;
        }

        if (task.terminationStatus == 0) {
            return candidate;
        }

        NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        NSString *stderrString = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
        if (stderrString.length > 0) {
            lastError = stderrString;
        }
    }

    NSString *message = @"python3 interpreter not found with PyObjC support.";
    if (lastError.length > 0) {
        message = [NSString stringWithFormat:@"%@ %@", message, lastError];
    }
    [self recordErrorWithCode:102 description:message];
    return nil;
}

- (nullable NSString *)bundledPythonExecutable {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *frameworksPath = bundle.privateFrameworksPath;
    if (frameworksPath.length == 0) {
        return nil;
    }

    NSString *candidate = [frameworksPath stringByAppendingPathComponent:@"Python3.framework/Versions/Current/bin/python3"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
        return candidate;
    }

    candidate = [frameworksPath stringByAppendingPathComponent:@"Python3.framework/Versions/3.9/bin/python3"];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
        return candidate;
    }

    return nil;
}

- (nullable NSString *)bundledResourcesBinDirectory {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *resourcePath = bundle.resourcePath;
    if (resourcePath.length == 0) {
        return nil;
    }

    NSString *candidate = [resourcePath stringByAppendingPathComponent:@"bin"];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory) {
        return candidate;
    }

    return nil;
}

- (nullable NSString *)bundledToolExecutableNamed:(NSString *)name {
    NSString *binDirectory = [self bundledResourcesBinDirectory];
    if (binDirectory.length == 0 || name.length == 0) {
        return nil;
    }

    NSString *candidate = [binDirectory stringByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
        return candidate;
    }

    return nil;
}

- (nullable NSString *)pythonHomeForExecutable:(NSString *)executable {
    if (executable.length == 0) {
        return nil;
    }

    NSURL *executableURL = [NSURL fileURLWithPath:executable];
    NSURL *resolvedURL = [executableURL URLByResolvingSymlinksInPath];
    NSString *resolvedPath = resolvedURL.path;
    if (resolvedPath.length == 0) {
        resolvedPath = executable;
    }

    NSArray<NSString *> *parts = [resolvedPath pathComponents];
    NSUInteger versionsIndex = [parts indexOfObject:@"Versions"];
    if (versionsIndex == NSNotFound || versionsIndex + 1 >= parts.count) {
        return nil;
    }

    NSArray<NSString *> *homeParts = [parts subarrayWithRange:NSMakeRange(0, versionsIndex + 2)];
    return [NSString pathWithComponents:homeParts];
}

- (NSDictionary<NSString *, NSString *> *)pythonEnvironmentForExecutable:(NSString *)executable {
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

    NSString *pythonHome = [self pythonHomeForExecutable:executable];
    if (pythonHome.length > 0) {
        env[@"PYTHONHOME"] = pythonHome;
    } else {
        [env removeObjectForKey:@"PYTHONHOME"];
    }

    if (executable.length > 0) {
        env[@"PYTHON_EXECUTABLE"] = executable;
    }
    NSString *bundledFFmpeg = [self bundledToolExecutableNamed:@"ffmpeg"];
    if (bundledFFmpeg.length > 0) {
        env[@"AURAFLOW_FFMPEG_PATH"] = bundledFFmpeg;
    }
    NSString *bundledFFprobe = [self bundledToolExecutableNamed:@"ffprobe"];
    if (bundledFFprobe.length > 0) {
        env[@"AURAFLOW_FFPROBE_PATH"] = bundledFFprobe;
    }
    NSString *bundledBinDirectory = [self bundledResourcesBinDirectory];
    if (bundledBinDirectory.length > 0) {
        NSString *existingPath = env[@"PATH"] ?: @"";
        if (existingPath.length > 0) {
            env[@"PATH"] = [NSString stringWithFormat:@"%@:%@", bundledBinDirectory, existingPath];
        } else {
            env[@"PATH"] = bundledBinDirectory;
        }
    }
    env[@"PYTHONPATH"] = [pythonPaths componentsJoinedByString:@":"];
    env[@"PYTHONUNBUFFERED"] = @"1";
    env[@"PYTHONNOUSERSITE"] = @"1";
    env[@"PYTHONDONTWRITEBYTECODE"] = @"1";
    return env;
}

- (NSDictionary<NSString *, NSString *> *)pythonEnvironment {
    return [self pythonEnvironmentForExecutable:self.pythonExecutable];
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
