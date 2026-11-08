#import <Cocoa/Cocoa.h>
#import "../../KeepingYouAwake/KYAMainMenu/KYAUsageStyle.h"
int main(void)
{
    @autoreleasepool {
        NSCAssert([KYAUsageColor(0) isEqual:NSColor.systemRedColor], @"zero is exhausted");
        NSCAssert([KYAUsageColor(.01) isEqual:NSColor.labelColor], @"positive low quota is normal text");
        NSCAssert([KYAUsageColor(24.99) isEqual:NSColor.labelColor], @"below 25 is normal text");
        NSCAssert([KYAUsageColor(25) isEqual:NSColor.labelColor], @"25 is normal text");
        NSCAssert([KYAUsageColor(75) isEqual:NSColor.labelColor], @"75 is normal text");
        NSCAssert([KYAUsageColor(75.01) isEqual:NSColor.labelColor], @"above 75 is normal text");
        NSCAssert([KYAUsageColor(100) isEqual:NSColor.labelColor], @"full quota is normal text");
        puts("Quota color boundary checks passed.");
    }
}
