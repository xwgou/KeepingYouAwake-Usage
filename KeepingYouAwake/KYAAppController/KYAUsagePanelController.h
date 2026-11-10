#import <Cocoa/Cocoa.h>

extern NSNotificationName const KYAUsagePanelRequestedNotification;

@interface KYAUsagePanelController : NSObject
- (instancetype)initWithTarget:(id)target menu:(NSMenu *)menu;
- (void)showPanel;
- (void)updateWithAwake:(BOOL)awake refreshing:(BOOL)refreshing;
- (void)applyDockPreference;
@end
