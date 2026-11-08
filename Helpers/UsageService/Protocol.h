#import <Foundation/Foundation.h>
@protocol KYAUsageServiceProtocol
- (void)fetchCodex:(BOOL)codex kimi:(BOOL)kimi reply:(void (^)(NSData *))reply;
@end
