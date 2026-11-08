#import <Foundation/Foundation.h>

#import "Protocol.h"

@interface UsageService : NSObject <KYAUsageServiceProtocol, NSXPCListenerDelegate>
@end
@implementation UsageService
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection
{
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(KYAUsageServiceProtocol)];
    connection.exportedObject = self;
    [connection resume];
    return YES;
}
- (void)fetchCodex:(BOOL)codex kimi:(BOOL)kimi reply:(void (^)(NSData *))reply
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
        NSString *script = [NSBundle.mainBundle pathForResource:@"usage_bridge" ofType:@"py"];
        NSMutableArray *arguments = [NSMutableArray arrayWithObjects:script, @"--stdout", nil];
        if(!codex) [arguments addObject:@"--no-codex"];
        if(kimi) [arguments addObject:@"--auto-kimi"];
        task.arguments = arguments;
        NSPipe *pipe = NSPipe.pipe;
        task.standardOutput = pipe;
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        if(![task launchAndReturnError:nil]) { reply(nil); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            if(task.running) [task terminate];
        });
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        [task waitUntilExit];
        reply(task.terminationStatus == 0 && data.length <= 1048576 ? data : nil);
    });
}
@end

int main(void)
{
    @autoreleasepool {
        UsageService *service = [UsageService new];
        NSXPCListener *listener = NSXPCListener.serviceListener;
        listener.delegate = service;
        [listener resume];
    }
    return 0;
}
