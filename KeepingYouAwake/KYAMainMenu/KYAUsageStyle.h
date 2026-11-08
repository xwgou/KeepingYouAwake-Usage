#import <Cocoa/Cocoa.h>

// Percentages describe remaining quota, including both threshold endpoints.
static inline NSColor *KYAUsageColor(double remaining)
{
    if(remaining == 0) return NSColor.systemRedColor;
    return NSColor.labelColor;
}

// Static menu views retain their colors during asynchronous updates and AppKit
// validation. They remain informational rather than appearing as clickable actions.
static inline NSMenuItem *KYAUsageInformation(NSString *text, NSColor *color)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:text action:nil keyEquivalent:@""];
    item.enabled = NO;
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont menuFontOfSize:0];
    label.textColor = color;
    [label sizeToFit];
    NSSize size = label.frame.size;
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width + 32, MAX(24, size.height + 8))];
    label.frame = NSMakeRect(16, (view.frame.size.height - size.height) / 2, size.width, size.height);
    [view addSubview:label];
    item.view = view;
    return item;
}
