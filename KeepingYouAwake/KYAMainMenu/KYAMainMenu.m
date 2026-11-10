//
//  KYAMainMenu.m
//  KeepingYouAwake
//
//  Created by Marcel Dierkes on 12.02.22.
//  Copyright © 2022 Marcel Dierkes. All rights reserved.
//

#import "KYAMainMenu.h"
#import "KYAUsageStyle.h"
#import <KYACommon/KYACommon.h>
#import "KYALocalizedStrings.h"
#import "KYAAppDelegate.h"
#import "KYAAppController.h"

NSMenu *KYACreateMainMenuWithActivationDurationsSubMenu(NSMenu *activationDurationsSubMenu)
{
    NSCParameterAssert(activationDurationsSubMenu);
    
    Auto mainMenu = [[NSMenu alloc] initWithTitle:@""];
    
    Auto title = [[NSMenuItem alloc] initWithTitle:@"KeepingYouAwake-Usage" action:nil keyEquivalent:@""];
    [mainMenu addItem:title];
    [mainMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Show Usage Panel…" action:@selector(showUsagePanel:) keyEquivalent:@""]];
    [mainMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Keep Awake" action:@selector(toggleKeepAwake:) keyEquivalent:@""]];

    Auto activateForDuration = [[NSMenuItem alloc] initWithTitle:KYA_L10N_ACTIVATE_FOR_DURATION
                                                          action:nil
                                                   keyEquivalent:@""];
    if(@available(macOS 26.0, *))
    {
        activateForDuration.image = [NSImage imageWithSystemSymbolName:@"timer" accessibilityDescription:nil];
    }
    activateForDuration.submenu = activationDurationsSubMenu;
    [mainMenu addItem:activateForDuration];
    
    [mainMenu addItem:NSMenuItem.separatorItem];
    
    NSInteger providerTag = 810;
    for(NSString *provider in @[@"Codex", @"Kimi Code"])
    {
        Auto heading = [[NSMenuItem alloc] initWithTitle:[provider stringByAppendingString:@" — Not connected"] action:nil keyEquivalent:@""];
        heading.tag = providerTag++;
        heading.submenu = [[NSMenu alloc] initWithTitle:provider];
        [heading.submenu addItem:KYAUsageInformation(@"Connect your installed CLI to see usage", NSColor.labelColor)];
        [mainMenu addItem:heading];
    }
    [mainMenu addItem:NSMenuItem.separatorItem];
    [mainMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Connect Codex…" action:@selector(toggleCodexConnection:) keyEquivalent:@""]];
    [mainMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Refresh Usage" action:@selector(reloadUsageSnapshot:) keyEquivalent:@"r"]];
    [mainMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Connect Kimi Code…" action:@selector(toggleKimiConnection:) keyEquivalent:@""]];
    [mainMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Legacy Click Behavior" action:@selector(toggleLegacyClickBehavior:) keyEquivalent:@""]];
    [mainMenu addItem:NSMenuItem.separatorItem];

    Auto settings = [[NSMenuItem alloc] initWithTitle:KYA_L10N_SETTINGS_ELLIPSIS
                                               action:@selector(showSettingsWindow:)
                                        keyEquivalent:@","];
    if(@available(macOS 26.0, *))
    {
        settings.image = [NSImage imageWithSystemSymbolName:@"gear" accessibilityDescription:nil];
    }
    [mainMenu addItem:settings];
    
    [mainMenu addItem:NSMenuItem.separatorItem];
    
    Auto quit = [[NSMenuItem alloc] initWithTitle:KYA_L10N_QUIT
                                           action:@selector(terminate:)
                                    keyEquivalent:@"q"];
    [mainMenu addItem:quit];
    
    return mainMenu;
}
