//
//  KYAAppDelegate.m
//  KeepingYouAwake
//
//  Created by Marcel Dierkes on 17.10.14.
//  Copyright (c) 2014 Marcel Dierkes. All rights reserved.
//

#import "KYAAppDelegate.h"
#import "KYAUsagePanelController.h"
#import <Carbon/Carbon.h>
#import <KYACommon/KYACommon.h>
#import "KYAAppUpdater.h"
#import "KYASettingsWindow.h"
#import "KYAUpdateSettingsViewController.h"

@interface KYAAppDelegate ()
@property (weak, nonatomic, nullable) KYASettingsWindow *settingsWindow;
@end

@implementation KYAAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
#if KYA_APP_UPDATER_ENABLED
    [KYAAppUpdater defaultAppUpdater];
#endif
    
    if(@available(macOS 13.0, *))
    {
        [NSApplication.sharedApplication kya_migrateLaunchAtLoginToAppServiceIfNeeded];
    }
    NSAppleEventDescriptor *event = NSAppleEventManager.sharedAppleEventManager.currentAppleEvent;
    BOOL loginLaunch = [event paramDescriptorForKeyword:keyAELaunchedAsLogInItem] != nil
        || [[event paramDescriptorForKeyword:keyAEPropData] descriptorForKeyword:keyAELaunchedAsLogInItem] != nil;
    if(!loginLaunch && [notification.userInfo[NSApplicationLaunchIsDefaultLaunchKey] boolValue])
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:KYAUsagePanelRequestedNotification object:nil];
        });

}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows
{
    [NSNotificationCenter.defaultCenter postNotificationName:KYAUsagePanelRequestedNotification object:nil];
    return NO;
}

#pragma mark - Settings Window

- (void)showSettingsWindow:(id)sender
{
    if(@available(macOS 14.0, *))
    {
        [NSApplication.sharedApplication activate];
    }
    else
    {
        [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    }
    
    AutoVar settingsWindow = self.settingsWindow;
    if(settingsWindow == nil)
    {
        NSArray<NSTabViewItem *> *additionalTabViewItems;
#if KYA_APP_UPDATER_ENABLED
        additionalTabViewItems = @[KYAUpdateSettingsViewController.preferredTabViewItem];
#endif
        settingsWindow = [[KYASettingsWindow alloc] initWithAdditionalTabViewItems:additionalTabViewItems];
        self.settingsWindow = settingsWindow;
    }
    [settingsWindow makeKeyAndOrderFront:sender];
}

@end
