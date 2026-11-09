//
//  KYAStatusItemController.m
//  KYAStatusItemUI
//
//  Created by Marcel Dierkes on 10.09.17.
//  Copyright © 2017 Marcel Dierkes. All rights reserved.
//

#import <KYAStatusItemUI/KYAStatusItemController.h>
#import <KYACommon/KYACommon.h>
#import <KYAStatusItemUI/KYAStatusItemImageProvider.h>
#import "KYAStatusItemUILocalizedStrings.h"

@interface KYAStatusItemController ()
@property (nonatomic, readwrite) NSStatusItem *systemStatusItem;
@end

@implementation KYAStatusItemController

- (instancetype)init
{
    self = [super init];
    if(self)
    {
        [self configureStatusItem];
    }
    return self;
}

#pragma mark - Configuration

- (void)configureStatusItem
{
    Auto statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusItem.highlightMode = ![NSUserDefaults standardUserDefaults].kya_menuBarIconHighlightDisabled;
    if([statusItem respondsToSelector:@selector(behavior)])
    {
        statusItem.behavior = NSStatusItemBehaviorTerminationOnRemoval;
    }
    if([statusItem respondsToSelector:@selector(isVisible)])
    {
        statusItem.visible = YES;
    }
    
    Auto button = statusItem.button;
    
    [button sendActionOn:NSEventMaskLeftMouseUp|NSEventMaskRightMouseUp];
    button.target = self;
    button.action = @selector(toggleStatus:);
    
    // AppKit chooses the contrasting menu-bar color, including full-screen Spaces.
    button.contentTintColor = nil;
    
    self.systemStatusItem = statusItem;
    self.appearance = KYAStatusItemAppearanceInactive;
}

- (void)toggleStatus:(id)sender
{
    Auto delegate = self.delegate;
    Auto event = NSApplication.sharedApplication.currentEvent;
    
    if(![NSUserDefaults.standardUserDefaults boolForKey:@"usageLegacyClickBehavior"]
       || (event.modifierFlags & NSEventModifierFlagControl)   // ctrl click
       || (event.modifierFlags & NSEventModifierFlagOption) // alt click
       || (event.type == NSEventTypeRightMouseUp))          // right click
    {
        [self showMenuFromDataSource];
        return;
    }
    
    if([delegate respondsToSelector:@selector(statusItemControllerShouldPerformPrimaryAction:)])
    {
        [delegate statusItemControllerShouldPerformPrimaryAction:self];
    }
}

#pragma mark - Appearance

- (KYAStatusItemAppearance)appearance
{
    Auto menubarIcon = KYAStatusItemImageProvider.currentProvider;
    return self.systemStatusItem.button.image == menubarIcon.activeIconImage;
}

- (void)setAppearance:(KYAStatusItemAppearance)appearance
{
    [self willChangeValueForKey:@"appearance"];
    
    Auto button = self.systemStatusItem.button;
    Auto imageProvider = KYAStatusItemImageProvider.currentProvider;
    
    if(appearance == KYAStatusItemAppearanceActive)
    {
        button.image = imageProvider.activeIconImage;
        button.toolTip = [NSUserDefaults.standardUserDefaults boolForKey:@"usageLegacyClickBehavior"] ? KYA_L10N_CLICK_TO_ALLOW_SLEEP : @"KeepingYouAwake-Usage — Awake; click to open menu";
    }
    else
    {
        button.image = imageProvider.inactiveIconImage;
        button.toolTip = [NSUserDefaults.standardUserDefaults boolForKey:@"usageLegacyClickBehavior"] ? KYA_L10N_CLICK_TO_PREVENT_SLEEP : @"KeepingYouAwake-Usage — Sleep allowed; click to open menu";
    }
    
    [self didChangeValueForKey:@"appearance"];
}

#pragma mark - Menu

- (void)showMenuFromDataSource
{
    Auto dataSource = self.dataSource;
    if([dataSource respondsToSelector:@selector(menuForStatusItemController:)])
    {
        Auto menu = [dataSource menuForStatusItemController:self];
        if(menu != nil)
        {
            [self.systemStatusItem popUpStatusItemMenu:menu];
        }
    }
}

@end
