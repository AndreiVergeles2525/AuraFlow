#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PythonBridge : NSObject

@property(class, readonly, nullable) NSError *lastError;

- (nullable instancetype)initWithBundleResource:(NSString *)resourceName;
- (nullable NSString *)runCommand:(NSString *)command
                        arguments:(NSArray<NSString *> *)arguments
                            error:(NSError * _Nullable * _Nullable)error;
- (void)runCommand:(NSString *)command
         arguments:(NSArray<NSString *> *)arguments
         completion:(void (^)(NSString *_Nullable output, NSString *_Nullable errorOutput, NSInteger status))completion;

@end

NS_ASSUME_NONNULL_END
