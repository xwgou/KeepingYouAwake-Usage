//
//  KYAAppController.m
//  KeepingYouAwake
//
//  Created by Marcel Dierkes on 17.10.14.
//  Copyright (c) 2014 Marcel Dierkes. All rights reserved.
//

#import "KYAAppController.h"
#import <math.h>
#import "../../Helpers/UsageService/Protocol.h"
#import <KYACommon/KYACommon.h>
#import "KYALocalizedStrings.h"
#import "KYAMainMenu.h"
#import "../KYAMainMenu/KYAUsageStyle.h"
#import "KYABatteryCapacityThreshold.h"
#import "KYAActivationDurationsMenuController.h"
#import "KYAActivationUserNotification.h"

// Deprecated!
#define KYA_MINUTES(m) (m * 60.0f)
#define KYA_HOURS(h) (h * 3600.0f)

@interface KYAAppController () <NSMenuDelegate, KYAStatusItemControllerDataSource, KYAStatusItemControllerDelegate, KYAActivationDurationsMenuControllerDelegate, KYASleepWakeTimerDelegate>
@property (nonatomic, readwrite) KYASleepWakeTimer *sleepWakeTimer;
@property (nonatomic, readwrite) KYAStatusItemController *statusItemController;
@property (nonatomic) KYAActivationDurationsMenuController *menuController;

@property (nonatomic) NSTimeInterval workspaceScheduledTimeInterval;

// Battery Status
@property (nonatomic, direct, getter=isBatteryOverrideEnabled) BOOL batteryOverrideEnabled;

// Menu
@property (nonatomic) NSMenu *menu;
@property (nonatomic) NSUInteger usageGeneration;
@property (nonatomic) BOOL usageReadInProgress;
@property (nonatomic) NSXPCConnection *usageConnection;
@property (nonatomic) NSTimer *usageTimer;
@property (nonatomic) NSDate *lastUsageRefresh;
@end

@implementation KYAAppController

#pragma mark - Life Cycle

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        [self configureStatusItemController];
        [self configureSleepWakeTimer];
        [self configureEventHandler];
        [self configureUserNotificationCenter];
        [self configureMainMenu];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"usageFolderBookmark"];
        __weak typeof(self) weakSelf = self;
        self.usageTimer = [NSTimer scheduledTimerWithTimeInterval:300 repeats:YES block:^(NSTimer *timer) {
            [weakSelf reloadUsageSnapshot:nil];
        }];
        [self reloadUsageSnapshot:nil];

        Auto center = NSNotificationCenter.defaultCenter;
        [center addObserver:self
                   selector:@selector(applicationWillFinishLaunching:)
                       name:NSApplicationWillFinishLaunchingNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(applicationDidChangeScreenParameters:)
                       name:NSApplicationDidChangeScreenParametersNotification
                     object:nil];
        [center addObserver:self
                   selector:@selector(batteryCapacityThresholdDidChange:)
                       name:kKYABatteryCapacityThresholdDidChangeNotification
                     object:nil];
        
        [self registerForWorkspaceSessionNotifications];
    }
    return self;
}

- (void)dealloc
{
    [self.usageTimer invalidate];
    [self.usageConnection invalidate];
    Auto center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self name:NSApplicationDidFinishLaunchingNotification object:nil];
    [center removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [center removeObserver:self name:kKYABatteryCapacityThresholdDidChangeNotification object:nil];
    
    [self unregisterFromWorkspaceSessionNotifications];
}

#pragma mark - Main Menu

- (void)configureMainMenu
{
    Auto menuController = [KYAActivationDurationsMenuController new];
    menuController.delegate = self;
    self.menuController = menuController;
    
    self.menu = KYACreateMainMenuWithActivationDurationsSubMenu(menuController.menu);
    self.menu.delegate = self;
    for(NSMenuItem *item in self.menu.itemArray)
    {
        if(item.action == @selector(toggleKeepAwake:) || item.action == @selector(toggleLegacyClickBehavior:) || item.action == @selector(toggleCodexConnection:) || item.action == @selector(reloadUsageSnapshot:) || item.action == @selector(toggleKimiConnection:))
        {
            item.target = self;
        }
    }
}

#pragma mark - Usage Snapshots

- (void)menuWillOpen:(NSMenu *)menu
{
    if(self.lastUsageRefresh == nil || self.lastUsageRefresh.timeIntervalSinceNow < -60)
        [self reloadUsageSnapshot:nil];
}

- (IBAction)toggleCodexConnection:(id)sender
{
    [self toggleUsageProvider:@"usageCodexConnected"];
}

- (IBAction)toggleKimiConnection:(id)sender
{
    [self toggleUsageProvider:@"usageKimiConnected"];
}

- (void)toggleUsageProvider:(NSString *)key
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    BOOL connected = [defaults boolForKey:key];
    if(!connected)
    {
        Auto alert = [NSAlert new];
        alert.messageText = [key isEqual:@"usageCodexConnected"] ? @"Connect Codex" : @"Connect Kimi Code";
        alert.informativeText = @"Read usage from your installed, signed-in CLI? The bundled helper refreshes quota automatically. If needed, sign in using the official CLI first.";
        [alert addButtonWithTitle:@"Connect"];
        [alert addButtonWithTitle:@"Cancel"];
        if([alert runModal] != NSAlertFirstButtonReturn) return;
    }
    [defaults setBool:!connected forKey:key];
    self.usageGeneration++;
    [self.usageConnection invalidate];
    self.usageConnection = nil;
    self.usageReadInProgress = NO;
    [self displayUsageProviders:nil];
    [self reloadUsageSnapshot:nil];
}

- (IBAction)reloadUsageSnapshot:(id)sender
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    BOOL codex = [defaults boolForKey:@"usageCodexConnected"];
    BOOL kimi = [defaults boolForKey:@"usageKimiConnected"];
    if(self.usageReadInProgress || (!codex && !kimi)) return;
    self.usageReadInProgress = YES;
    NSUInteger generation = ++self.usageGeneration;
    Auto connection = [[NSXPCConnection alloc] initWithServiceName:@"com.xwgou.KeepingYouAwake-Usage.UsageService"];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(KYAUsageServiceProtocol)];
    self.usageConnection = connection;
    [connection resume];
    __weak typeof(self) weakSelf = self;
    void (^finish)(NSData *) = ^(NSData *data) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Auto strongSelf = weakSelf;
            if(strongSelf == nil || generation != strongSelf.usageGeneration || !strongSelf.usageReadInProgress) return;
            strongSelf.usageReadInProgress = NO;
            strongSelf.lastUsageRefresh = NSDate.date;
            id document = data.length > 0 && data.length <= 1048576 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray *providers = nil;
            if([document isKindOfClass:NSDictionary.class] && [document[@"schemaVersion"] isEqual:@1] && [document[@"providers"] isKindOfClass:NSArray.class])
                providers = document[@"providers"];
            if(providers == nil)
                providers = @[@{@"provider": @"Codex", @"state": codex ? @"unavailable" : @"notConnected"}, @{@"provider": @"Kimi Code", @"state": kimi ? @"unavailable" : @"notConnected"}];
            [strongSelf displayUsageProviders:providers];
            [strongSelf.usageConnection invalidate];
            strongSelf.usageConnection = nil;
        });
    };
    id<KYAUsageServiceProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) { finish(nil); }];
    [proxy fetchCodex:codex kimi:kimi reply:finish];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ finish(nil); });
}

- (void)displayUsageProviders:(NSArray *)providers
{
    NSArray *names = @[@"Codex", @"Kimi Code"];
    Auto formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    for(NSUInteger index = 0; index < names.count; index++)
    {
        NSString *name = names[index];
        NSDictionary *provider = nil;
        for(id candidate in providers)
        {
            if([candidate isKindOfClass:NSDictionary.class] && [candidate[@"provider"] isEqual:name])
            {
                provider = candidate;
                break;
            }
        }
        NSString *status = @"Not connected";
        Auto item = [self.menu itemWithTag:810 + (NSInteger)index];
        Auto submenu = item.submenu;
        [submenu removeAllItems];
        id fetched = provider[@"fetchedAt"];
        NSDate *date = [fetched isKindOfClass:NSString.class] ? [formatter dateFromString:fetched] : nil;
        BOOL fresh = [provider[@"state"] isEqual:@"fresh"] && date != nil;
        if(provider != nil) status = @"Unavailable";
        if([provider[@"state"] isEqual:@"notConnected"]) status = @"Not connected";
        if(fresh) status = (date.timeIntervalSinceNow < -360 || date.timeIntervalSinceNow > 60) ? @"Stale" : @"Connected";
        if(fresh && [provider[@"windows"] isKindOfClass:NSArray.class])
        {
            for(id window in provider[@"windows"])
            {
                if(![window isKindOfClass:NSDictionary.class]) continue;
                id remaining = window[@"remainingPercent"];
                id label = window[@"label"];
                if(![remaining isKindOfClass:NSNumber.class] || ![label isKindOfClass:NSString.class]) continue;
                double value = [remaining doubleValue];
                if(CFGetTypeID((__bridge CFTypeRef)remaining) == CFBooleanGetTypeID() || !isfinite(value) || value < 0 || value > 100) continue;
                Auto text = [NSString stringWithFormat:@"%@: %g%% remaining%@", label, value, value == 0 ? @" — Limit reached" : @""];
                [submenu addItem:KYAUsageInformation(text, KYAUsageColor(value))];
                id reset = window[@"resetsAt"];
                if([reset isKindOfClass:NSString.class])
                {
                    NSDate *resetDate = [formatter dateFromString:reset];
                    if(resetDate == nil)
                    {
                        Auto plain = [NSISO8601DateFormatter new];
                        resetDate = [plain dateFromString:reset];
                    }
                    if(resetDate)
                    {
                        Auto resetText = [@"Resets " stringByAppendingString:[NSDateFormatter localizedStringFromDate:resetDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
                        [submenu addItem:KYAUsageInformation(resetText, NSColor.labelColor)];
                    }
                }
            }
        }
        if(submenu.numberOfItems == 0)
            [submenu addItem:KYAUsageInformation(@"No verified quota available", NSColor.labelColor)];
        if(date)
        {
            Auto updated = [@"Updated " stringByAppendingString:[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
            [submenu addItem:KYAUsageInformation(updated, NSColor.labelColor)];
        }
        item.title = [NSString stringWithFormat:@"%@ — %@", name, status];
    }
}

- (IBAction)toggleKeepAwake:(id)sender
{
    [self statusItemControllerShouldPerformPrimaryAction:self.statusItemController];
}

- (IBAction)toggleLegacyClickBehavior:(id)sender
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:![defaults boolForKey:@"usageLegacyClickBehavior"] forKey:@"usageLegacyClickBehavior"];
    self.statusItemController.appearance = self.sleepWakeTimer.isScheduled ? KYAStatusItemAppearanceActive : KYAStatusItemAppearanceInactive;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if(item.action == @selector(toggleKeepAwake:))
    {
        item.state = self.sleepWakeTimer.isScheduled ? NSControlStateValueOn : NSControlStateValueOff;
    }
    else if(item.action == @selector(toggleLegacyClickBehavior:))
    {
        item.state = [NSUserDefaults.standardUserDefaults boolForKey:@"usageLegacyClickBehavior"] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if(item.action == @selector(toggleCodexConnection:))
        item.title = [NSUserDefaults.standardUserDefaults boolForKey:@"usageCodexConnected"] ? @"Disconnect Codex" : @"Connect Codex…";
    if(item.action == @selector(toggleKimiConnection:))
        item.title = [NSUserDefaults.standardUserDefaults boolForKey:@"usageKimiConnected"] ? @"Disconnect Kimi Code" : @"Connect Kimi Code…";
    return YES;
}

#pragma mark - Status Item Controller

- (void)configureStatusItemController
{
    Auto statusItemController = [KYAStatusItemController new];
    statusItemController.dataSource = self;
    statusItemController.delegate = self;
    self.statusItemController = statusItemController;
}

#pragma mark - Sleep Wake Timer

- (void)configureSleepWakeTimer
{
    Auto sleepWakeTimer = [KYASleepWakeTimer new];
    sleepWakeTimer.delegate = self;
    self.sleepWakeTimer = sleepWakeTimer;
    
    // Activate on launch if needed
    if([NSUserDefaults.standardUserDefaults kya_isActivatedOnLaunch])
    {
        [self activateTimer];
    }
}

- (void)activateTimer
{
    [self activateTimerWithTimeInterval:self.defaultTimeInterval];
}

- (void)activateTimerWithTimeInterval:(NSTimeInterval)timeInterval
{
    // Do not allow negative time intervals
    if(timeInterval < 0)
    {
        return;
    }

    Auto defaults = NSUserDefaults.standardUserDefaults;
    
    Auto timerCompletion = ^(BOOL cancelled) {
        // Post deactivation notification
        Auto notification = [[KYAActivationUserNotification alloc] initWithFireDate:nil activating:NO];
        [KYAUserNotificationCenter.sharedCenter postNotification:notification];

        // Quit on timer expiration
        if(cancelled == NO && [defaults kya_isQuitOnTimerExpirationEnabled])
        {
            [NSApplication.sharedApplication terminate:nil];
        }
    };
    [self.sleepWakeTimer scheduleWithTimeInterval:timeInterval completion:timerCompletion];

    // Post activation notification
    Auto fireDate = self.sleepWakeTimer.fireDate;
    Auto notification = [[KYAActivationUserNotification alloc] initWithFireDate:fireDate activating:YES];
    [KYAUserNotificationCenter.sharedCenter postNotification:notification];
}

- (void)terminateTimer
{
    [self disableBatteryOverride];

    if([self.sleepWakeTimer isScheduled])
    {
        [self.sleepWakeTimer invalidate];
    }
}

#pragma mark - Default Time Interval

- (NSTimeInterval)defaultTimeInterval
{
    return NSUserDefaults.standardUserDefaults.kya_defaultTimeInterval;
}

#pragma mark - Activate on Launch

- (IBAction)toggleActivateOnLaunch:(id)sender
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    defaults.kya_activateOnLaunch = ![defaults kya_isActivatedOnLaunch];
    [defaults synchronize];
}

#pragma mark - User Notification Center

- (void)configureUserNotificationCenter
{
    Auto center = KYAUserNotificationCenter.sharedCenter;
    [center requestAuthorizationIfUndetermined];
    [center clearAllDeliveredNotifications];
}

#pragma mark - Device Power Monitoring

- (void)checkAndEnableBatteryOverride
{
    Auto batteryMonitor = KYADevice.currentDevice.batteryMonitor;
    CGFloat currentCapacity = batteryMonitor.currentCapacity;
    CGFloat threshold = NSUserDefaults.standardUserDefaults.kya_batteryCapacityThreshold;

    self.batteryOverrideEnabled = (currentCapacity <= threshold);
}

- (void)disableBatteryOverride
{
    self.batteryOverrideEnabled = NO;
}

- (void)deviceParameterDidChange:(NSNotification *)notification
{
    NSParameterAssert(notification);
    
    Auto device = (KYADevice *)notification.object;
    Auto defaults = NSUserDefaults.standardUserDefaults;
    
    Auto userInfo = notification.userInfo;
    Auto deviceParameter = (KYADeviceParameter)userInfo[KYADeviceParameterKey];
    if([deviceParameter isEqualToString:KYADeviceParameterBattery])
    {
        if([defaults kya_isBatteryCapacityThresholdEnabled] == NO) { return; }
        
        CGFloat threshold = defaults.kya_batteryCapacityThreshold;
        Auto capacity = device.batteryMonitor.currentCapacity;
        if([self.sleepWakeTimer isScheduled] && (capacity <= threshold) && ![self isBatteryOverrideEnabled])
        {
            [self terminateTimer];
        }
    }
    else if([deviceParameter isEqualToString:KYADeviceParameterLowPowerMode])
    {
        if([defaults kya_isLowPowerModeMonitoringEnabled] == NO) { return; }
        
        if([device.lowPowerModeMonitor isLowPowerModeEnabled] && [self.sleepWakeTimer isScheduled])
        {
            [self terminateTimer];
        }
    }
}

- (void)enableDevicePowerMonitoring
{
    Auto device = KYADevice.currentDevice;
    Auto center = NSNotificationCenter.defaultCenter;
    Auto defaults = NSUserDefaults.standardUserDefaults;
    
    // Check battery overrides and register for capacity changes.
    [self checkAndEnableBatteryOverride];
    
    [center addObserver:self
               selector:@selector(deviceParameterDidChange:)
                   name:KYADeviceParameterDidChangeNotification
                 object:device];
    
    if([defaults kya_isBatteryCapacityThresholdEnabled])
    {
        device.batteryMonitoringEnabled = YES;
    }
    if([defaults kya_isLowPowerModeMonitoringEnabled])
    {
        device.lowPowerModeMonitoringEnabled = YES;
    }
}

- (void)disableDevicePowerMonitoring
{
    Auto device = KYADevice.currentDevice;
    Auto center = NSNotificationCenter.defaultCenter;
    
    [center removeObserver:self
                      name:KYADeviceParameterDidChangeNotification
                    object:device];
    
    device.batteryMonitoringEnabled = NO;
    device.lowPowerModeMonitoringEnabled = NO;
}

#pragma mark - Battery Capacity Threshold Changes

- (void)batteryCapacityThresholdDidChange:(NSNotification *)notification
{
    if([self.sleepWakeTimer isScheduled])
    {
        [self terminateTimer];
    }
}

#pragma mark - Workspace Session Handling

- (void)registerForWorkspaceSessionNotifications
{
    Auto workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserver:self
                        selector:@selector(workspaceSessionDidBecomeActive:)
                            name:NSWorkspaceSessionDidBecomeActiveNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(workspaceSessionDidResignActive:)
                            name:NSWorkspaceSessionDidResignActiveNotification
                          object:nil];
}

- (void)unregisterFromWorkspaceSessionNotifications
{
    Auto workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter removeObserver:self
                               name:NSWorkspaceSessionDidBecomeActiveNotification
                             object:nil];
    [workspaceCenter removeObserver:self
                               name:NSWorkspaceSessionDidResignActiveNotification
                             object:nil];
}

- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    if([defaults kya_isDeactivateOnUserSwitchEnabled] && self.workspaceScheduledTimeInterval >= 0)
    {
        [self activateTimerWithTimeInterval:self.workspaceScheduledTimeInterval];
        self.workspaceScheduledTimeInterval = -1;
    }
}

- (void)workspaceSessionDidResignActive:(NSNotification *)notification
{
    Auto defaults = NSUserDefaults.standardUserDefaults;
    if([defaults kya_isDeactivateOnUserSwitchEnabled] && [self.sleepWakeTimer isScheduled])
    {
        self.workspaceScheduledTimeInterval = self.sleepWakeTimer.scheduledTimeInterval;
        [self terminateTimer];
    }
}

#pragma mark - Event Handling

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    [KYAEventHandler.defaultHandler registerAsDefaultEventHandler];
}

- (void)configureEventHandler
{
    Auto eventHandler = KYAEventHandler.defaultHandler;
    
    AutoWeak weakSelf = self;
    [eventHandler registerActionNamed:@"activate" block:^(KYAEvent *event) {
        [weakSelf handleActivateActionForEvent:event];
    }];
    
    [eventHandler registerActionNamed:@"deactivate" block:^(KYAEvent *event) {
        Auto strongSelf = weakSelf;
        [strongSelf terminateTimer];
        strongSelf.statusItemController.appearance = KYAStatusItemAppearanceInactive;
    }];
    
    [eventHandler registerActionNamed:@"toggle" block:^(KYAEvent *event) {
        Auto strongSelf = weakSelf;
        [strongSelf statusItemControllerShouldPerformPrimaryAction:strongSelf.statusItemController];
    }];
}

- (void)handleActivateActionForEvent:(KYAEvent *)event
{
    Auto parameters = event.arguments;
    NSString *seconds = parameters[@"seconds"];
    NSString *minutes = parameters[@"minutes"];
    NSString *hours = parameters[@"hours"];

    [self terminateTimer];
    
    Auto statusItemController = self.statusItemController;

    // Activate indefinitely if there are no parameters
    if(parameters == nil || parameters.count == 0)
    {
        [self activateTimer];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else if(seconds != nil)
    {
        [self activateTimerWithTimeInterval:(NSTimeInterval)ceil(seconds.doubleValue)];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else if(minutes != nil)
    {
        [self activateTimerWithTimeInterval:(NSTimeInterval)KYA_MINUTES(ceil(minutes.doubleValue))];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else if(hours != nil)
    {
        [self activateTimerWithTimeInterval:(NSTimeInterval)KYA_HOURS(ceil(hours.doubleValue))];
        statusItemController.appearance = KYAStatusItemAppearanceActive;
    }
    else
    {
        statusItemController.appearance = KYAStatusItemAppearanceInactive;
    }
}

#pragma mark - Internal / External Screen Parameter Changes

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
    if([NSUserDefaults.standardUserDefaults kya_isActivateOnExternalDisplayConnectedEnabled] == NO)
    {
        return;
    }
    
    NSUInteger numberOfExternalScreens = KYADisplayParametersGetNumberOfExternalDisplays();
    Auto sleepWakeTimer = self.sleepWakeTimer;
    
    if(numberOfExternalScreens == 0)
    {
        // Only the main screen is connected, deactivate!
        if([sleepWakeTimer isScheduled])
        {
            [self terminateTimer];
        }
    }
    else
    {
        // The main screen and at least one external screen, activate!
        if([sleepWakeTimer isScheduled] == NO)
        {
            [self activateTimer];
        }
    }
}

#pragma mark - KYAStatusItemControllerDataSource

- (NSMenu *)menuForStatusItemController:(KYAStatusItemController *)controller
{
    return self.menu;
}

#pragma mark - KYAStatusItemControllerDelegate

- (void)statusItemControllerShouldPerformPrimaryAction:(KYAStatusItemController *)controller
{
    if([self.sleepWakeTimer isScheduled])
    {
        [self terminateTimer];
    }
    else
    {
        [self activateTimer];
    }
}

#pragma mark - KYAActivationDurationsMenuControllerDelegate

- (KYAActivationDuration *)currentActivationDuration
{
    Auto sleepWakeTimer = self.sleepWakeTimer;
    if(![sleepWakeTimer isScheduled])
    {
        return nil;
    }

    NSTimeInterval seconds = sleepWakeTimer.scheduledTimeInterval;
    return [[KYAActivationDuration alloc] initWithSeconds:seconds];
}

- (void)activationDurationsMenuController:(KYAActivationDurationsMenuController *)controller didSelectActivationDuration:(KYAActivationDuration *)activationDuration
{
    [self terminateTimer];

    AutoWeak weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimeInterval seconds = activationDuration.seconds;
        [weakSelf activateTimerWithTimeInterval:seconds];
    });
}

- (NSDate *)fireDateForMenuController:(KYAActivationDurationsMenuController *)controller
{
    return self.sleepWakeTimer.fireDate;
}

#pragma mark - KYASleepWakeTimerDelegate

- (void)sleepWakeTimer:(KYASleepWakeTimer *)sleepWakeTimer willActivateWithTimeInterval:(NSTimeInterval)timeInterval
{
    // Update the status item
    self.statusItemController.appearance = KYAStatusItemAppearanceActive;
    
    [self enableDevicePowerMonitoring];
}

- (void)sleepWakeTimerDidDeactivate:(KYASleepWakeTimer *)sleepWakeTimer
{
    // Update the status item
    self.statusItemController.appearance = KYAStatusItemAppearanceInactive;
    
    [self disableDevicePowerMonitoring];
}

@end
