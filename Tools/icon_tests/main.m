#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if(argc != 2) { fprintf(stderr, "Usage: icon-tests /path/to/app\n"); return 2; }
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSImage *active = [bundle imageForResource:@"ActiveIcon"];
        NSImage *inactive = [bundle imageForResource:@"InactiveIcon"];
        NSCAssert(active != nil && inactive != nil, @"Both status icons must be bundled");
        NSCAssert(active.isTemplate, @"Active asset must use adaptive template rendering");
        NSCAssert(inactive.isTemplate, @"Inactive asset must use adaptive template rendering");
        NSCAssert(![active.TIFFRepresentation isEqual:inactive.TIFFRepresentation], @"Active/inactive shapes must remain distinct");
        puts("Both compiled icons are distinct adaptive templates.");
    }
    return 0;
}
