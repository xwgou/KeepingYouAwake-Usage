#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "../../KeepingYouAwake/KYAAppController/KYAUsagePanelController.h"
@interface KYAUsagePanelController (Testing)
- (void)createPanel;
- (BOOL)registerKey:(UInt32)key modifiers:(UInt32)modifiers enabled:(BOOL)enabled;
@end
int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"usageShortcutEnabled": @NO,
            @"usageCodexConnected": @YES, @"usageKimiConnected": @NO} forName:NSArgumentDomain];
        NSMenu *menu = [NSMenu new];
        for(NSInteger tag = 810; tag <= 811; tag++) {
            NSMenuItem *provider = [[NSMenuItem alloc] initWithTitle:tag == 810 ? @"Codex" : @"Kimi Code" action:nil keyEquivalent:@""];
            provider.tag = tag;
            provider.submenu = [NSMenu new];
            NSMenuItem *row = [[NSMenuItem alloc] initWithTitle:tag == 810 ? @"Session: 0% remaining" : @"Weekly: 80% remaining" action:nil keyEquivalent:@""];
            row.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
            NSTextField *label = [NSTextField labelWithString:row.title];
            label.textColor = tag == 810 ? NSColor.systemRedColor : NSColor.labelColor;
            [row.view addSubview:label];
            [provider.submenu addItem:row];
            [menu addItem:provider];
        }
        KYAUsagePanelController *controller = [[KYAUsagePanelController alloc] initWithTarget:nil menu:menu];
        [controller createPanel];
        [controller updateWithAwake:YES refreshing:YES];
        NSCAssert([[controller valueForKey:@"awakeButton"] state] == NSControlStateValueOn, @"awake state follows model");
        NSCAssert(![[controller valueForKey:@"refreshButton"] isEnabled], @"refresh cannot overlap");
        NSCAssert([[[controller valueForKey:@"codexButton"] title] isEqual:@"Disconnect Codex"], @"connected provider action");
        NSTextView *text = [controller valueForKey:@"usageText"];
        NSRange red = [text.string rangeOfString:@"Session: 0%"];
        NSRange normal = [text.string rangeOfString:@"Weekly: 80%"];
        NSCAssert(red.location != NSNotFound && normal.location != NSNotFound, @"both providers shared");
        NSCAssert([[text.textStorage attribute:NSForegroundColorAttributeName atIndex:red.location effectiveRange:NULL] isEqual:NSColor.systemRedColor], @"exhausted quota stays red");
        NSCAssert([[text.textStorage attribute:NSForegroundColorAttributeName atIndex:normal.location effectiveRange:NULL] isEqual:NSColor.labelColor], @"positive quota stays normal");
        [controller updateWithAwake:NO refreshing:NO];
        NSCAssert([[controller valueForKey:@"awakeButton"] state] == NSControlStateValueOff, @"deactivation synchronizes");
        NSCAssert([[controller valueForKey:@"refreshButton"] isEnabled], @"refresh restored");
        NSCAssert(![controller registerKey:kVK_ANSI_U modifiers:optionKey enabled:YES], @"reject unmodified typing shortcut");
        NSCAssert(![controller registerKey:999 modifiers:cmdKey enabled:YES], @"reject unknown key");
        NSCAssert([controller registerKey:kVK_ANSI_U modifiers:cmdKey enabled:NO], @"disable shortcut");
        puts("Usage panel checks passed (11 assertions).");
    }
}
