#import "KYAUsagePanelController.h"
#import "KYAAppController.h"
#import "KYAAppDelegate.h"
#import <Carbon/Carbon.h>

NSNotificationName const KYAUsagePanelRequestedNotification = @"KYAUsagePanelRequested";

@interface KYAUsagePanel : NSPanel
@end
@implementation KYAUsagePanel
- (void)cancelOperation:(id)sender { [self orderOut:sender]; }
@end

@interface KYAUsagePanelController ()
@property (nonatomic, weak) id target;
@property (nonatomic) NSMenu *menu;
@property (nonatomic) KYAUsagePanel *panel;
@property (nonatomic) NSTextView *usageText;
@property (nonatomic) NSButton *awakeButton;
@property (nonatomic) NSButton *refreshButton;
@property (nonatomic) NSButton *codexButton;
@property (nonatomic) NSButton *kimiButton;
@property (nonatomic) NSButton *dockButton;
@property (nonatomic) NSButton *legacyButton;
@property (nonatomic) NSButton *shortcutEnabled;
@property (nonatomic) NSPopUpButton *shortcutKey;
@property (nonatomic) NSArray<NSButton *> *modifierButtons;
@property (nonatomic) NSTextField *shortcutStatus;
@property (nonatomic) NSString *shortcutMessage;
@property (nonatomic) EventHotKeyRef hotKey;
@property (nonatomic) EventHandlerRef hotKeyHandler;
@property (nonatomic) UInt32 registeredKey;
@property (nonatomic) UInt32 registeredModifiers;
@property (nonatomic) UInt32 registrationID;
@property (nonatomic) BOOL awake;
@property (nonatomic) BOOL refreshing;
@end

static OSStatus KYAHandleUsageHotKey(EventHandlerCallRef next, EventRef event, void *context)
{
    EventHotKeyID identifier;
    if(GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                         sizeof(identifier), NULL, &identifier) != noErr) return eventNotHandledErr;
    KYAUsagePanelController *controller = (__bridge KYAUsagePanelController *)context;
    if(identifier.signature != 'KYAU' || identifier.id != controller.registrationID) return eventNotHandledErr;
    [NSNotificationCenter.defaultCenter postNotificationName:KYAUsagePanelRequestedNotification object:nil];
    return noErr;
}

static NSArray<NSNumber *> *KYAUsageKeyCodes(void)
{
    return @[@(kVK_ANSI_A), @(kVK_ANSI_B), @(kVK_ANSI_C), @(kVK_ANSI_D), @(kVK_ANSI_E),
             @(kVK_ANSI_F), @(kVK_ANSI_G), @(kVK_ANSI_H), @(kVK_ANSI_I), @(kVK_ANSI_J),
             @(kVK_ANSI_K), @(kVK_ANSI_L), @(kVK_ANSI_M), @(kVK_ANSI_N), @(kVK_ANSI_O),
             @(kVK_ANSI_P), @(kVK_ANSI_Q), @(kVK_ANSI_R), @(kVK_ANSI_S), @(kVK_ANSI_T),
             @(kVK_ANSI_U), @(kVK_ANSI_V), @(kVK_ANSI_W), @(kVK_ANSI_X), @(kVK_ANSI_Y), @(kVK_ANSI_Z),
             @(kVK_F1), @(kVK_F2), @(kVK_F3), @(kVK_F4), @(kVK_F5), @(kVK_F6),
             @(kVK_F7), @(kVK_F8), @(kVK_F9), @(kVK_F10), @(kVK_F11), @(kVK_F12)];
}

@implementation KYAUsagePanelController

- (instancetype)initWithTarget:(id)target menu:(NSMenu *)menu
{
    self = [super init];
    if(self)
    {
        self.target = target;
        self.menu = menu;
        [NSUserDefaults.standardUserDefaults registerDefaults:@{@"usageShortcutEnabled": @YES,
            @"usageShortcutKey": @(kVK_ANSI_U), @"usageShortcutModifiers": @(controlKey | optionKey | cmdKey),
            @"usageShowInDock": @NO}];
        EventTypeSpec type = {kEventClassKeyboard, kEventHotKeyPressed};
        EventHandlerRef handler = NULL;
        OSStatus result = InstallEventHandler(GetApplicationEventTarget(), KYAHandleUsageHotKey, 1,
                                              &type, (__bridge void *)self, &handler);
        self.hotKeyHandler = handler;
        if(result == noErr)
        {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            [self registerKey:(UInt32)[defaults integerForKey:@"usageShortcutKey"]
                   modifiers:(UInt32)[defaults integerForKey:@"usageShortcutModifiers"]
                     enabled:[defaults boolForKey:@"usageShortcutEnabled"]];
        }
        else self.shortcutMessage = @"Global shortcut unavailable. Open the panel through Finder or the menu.";
    }
    return self;
}

- (void)dealloc
{
    if(self.hotKey) UnregisterEventHotKey(self.hotKey);
    if(self.hotKeyHandler) RemoveEventHandler(self.hotKeyHandler);
}

- (BOOL)registerKey:(UInt32)key modifiers:(UInt32)modifiers enabled:(BOOL)enabled
{
    if(!enabled)
    {
        if(self.hotKey) UnregisterEventHotKey(self.hotKey);
        self.hotKey = NULL;
        self.shortcutMessage = @"Global shortcut disabled.";
        return YES;
    }
    if(!(modifiers & (cmdKey | controlKey)) || ![KYAUsageKeyCodes() containsObject:@(key)])
    {
        self.shortcutMessage = @"Choose a key and include Command or Control.";
        return NO;
    }
    if(self.hotKey && self.registeredKey == key && self.registeredModifiers == modifiers)
    {
        self.shortcutMessage = @"Shortcut active. Try it from another app; Escape closes this panel.";
        return YES;
    }
    if(!self.hotKeyHandler)
    {
        self.shortcutMessage = @"Global shortcut unavailable. Open the panel through Finder or the menu.";
        return NO;
    }
    CFArrayRef symbolic = NULL;
    if(CopySymbolicHotKeys(&symbolic) == noErr && symbolic)
    {
        NSArray *shortcuts = CFBridgingRelease(symbolic);
        for(NSDictionary *shortcut in shortcuts)
        {
            if([shortcut[(__bridge NSString *)kHISymbolicHotKeyEnabled] boolValue]
               && [shortcut[(__bridge NSString *)kHISymbolicHotKeyCode] unsignedIntValue] == key
               && [shortcut[(__bridge NSString *)kHISymbolicHotKeyModifiers] unsignedIntValue] == modifiers)
            {
                self.shortcutMessage = @"That shortcut is used by macOS. Choose another combination.";
                return NO;
            }
        }
    }
    EventHotKeyRef replacement = NULL;
    EventHotKeyID identifier = {'KYAU', self.registrationID + 1};
    OSStatus result = RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &replacement);
    if(result != noErr)
    {
        self.shortcutMessage = @"Could not register that shortcut. Your previous shortcut is unchanged.";
        return NO;
    }
    if(self.hotKey) UnregisterEventHotKey(self.hotKey);
    self.hotKey = replacement;
    self.registrationID = identifier.id;
    self.registeredKey = key;
    self.registeredModifiers = modifiers;
    self.shortcutMessage = @"Shortcut active. Try it from another app; Escape closes this panel.";
    return YES;
}

- (NSButton *)button:(NSString *)title action:(SEL)action target:(id)target frame:(NSRect)frame
{
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.frame = frame;
    [self.panel.contentView addSubview:button];
    return button;
}

- (void)createPanel
{
    self.panel = [[KYAUsagePanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 660)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self.panel.title = @"KeepingYouAwake-Usage";
    self.panel.releasedWhenClosed = NO;
    self.panel.hidesOnDeactivate = NO;
    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.frameAutosaveName = @"UsagePanel";
    [self.panel center];

    NSTextField *heading = [NSTextField labelWithString:@"Usage & Keep Awake"];
    heading.font = [NSFont boldSystemFontOfSize:20];
    heading.frame = NSMakeRect(20, 616, 520, 28);
    [self.panel.contentView addSubview:heading];
    self.awakeButton = [NSButton checkboxWithTitle:@"Keep Awake" target:self.target action:@selector(toggleKeepAwake:)];
    self.awakeButton.frame = NSMakeRect(20, 578, 130, 28);
    [self.panel.contentView addSubview:self.awakeButton];
    [self button:@"Activate for Duration…" action:@selector(showUsageDurationMenu:) target:self.target frame:NSMakeRect(156, 576, 200, 30)];
    self.refreshButton = [self button:@"Refresh Usage" action:@selector(reloadUsageSnapshot:) target:self.target frame:NSMakeRect(378, 576, 162, 30)];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 272, 520, 292)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.usageText = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    self.usageText.editable = NO;
    self.usageText.selectable = YES;
    self.usageText.textContainerInset = NSMakeSize(12, 10);
    self.usageText.autoresizingMask = NSViewWidthSizable;
    self.usageText.textContainer.widthTracksTextView = YES;
    scroll.documentView = self.usageText;
    [self.panel.contentView addSubview:scroll];
    self.codexButton = [self button:@"Connect Codex…" action:@selector(toggleCodexConnection:) target:self.target frame:NSMakeRect(20, 230, 250, 30)];
    self.kimiButton = [self button:@"Connect Kimi Code…" action:@selector(toggleKimiConnection:) target:self.target frame:NSMakeRect(284, 230, 256, 30)];

    self.dockButton = [NSButton checkboxWithTitle:@"Show in Dock" target:self action:@selector(toggleDock:)];
    self.dockButton.frame = NSMakeRect(20, 196, 190, 24);
    [self.panel.contentView addSubview:self.dockButton];
    self.legacyButton = [NSButton checkboxWithTitle:@"Legacy Click Behavior" target:self.target action:@selector(toggleLegacyClickBehavior:)];
    self.legacyButton.frame = NSMakeRect(284, 196, 256, 24);
    [self.panel.contentView addSubview:self.legacyButton];
    self.shortcutEnabled = [NSButton checkboxWithTitle:@"Global shortcut" target:nil action:nil];
    self.shortcutEnabled.frame = NSMakeRect(20, 156, 180, 24);
    [self.panel.contentView addSubview:self.shortcutEnabled];
    NSMutableArray *buttons = [NSMutableArray array];
    NSArray *titles = @[@"⌃ Control", @"⌥ Option", @"⇧ Shift", @"⌘ Command"];
    NSArray *masks = @[@(controlKey), @(optionKey), @(shiftKey), @(cmdKey)];
    for(NSUInteger i = 0; i < titles.count; i++)
    {
        NSButton *button = [NSButton checkboxWithTitle:titles[i] target:nil action:nil];
        button.frame = NSMakeRect(20 + (CGFloat)i * 110, 126, 110, 24);
        button.tag = [masks[i] integerValue];
        [self.panel.contentView addSubview:button];
        [buttons addObject:button];
    }
    self.modifierButtons = buttons;
    self.shortcutKey = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(464, 125, 76, 26) pullsDown:NO];
    for(NSUInteger i = 0; i < KYAUsageKeyCodes().count; i++)
    {
        NSString *title = i < 26 ? [NSString stringWithFormat:@"%c", (int)('A' + i)] : [NSString stringWithFormat:@"F%lu", (unsigned long)i - 25];
        [self.shortcutKey addItemWithTitle:title];
        self.shortcutKey.lastItem.tag = [KYAUsageKeyCodes()[i] integerValue];
    }
    self.shortcutKey.toolTip = @"Letter keys use their physical US-keyboard positions.";
    [self.panel.contentView addSubview:self.shortcutKey];
    [self button:@"Apply Shortcut" action:@selector(applyShortcut:) target:self frame:NSMakeRect(20, 88, 150, 30)];
    self.shortcutStatus = [NSTextField wrappingLabelWithString:self.shortcutMessage ?: @""];
    self.shortcutStatus.frame = NSMakeRect(182, 78, 358, 44);
    self.shortcutStatus.font = [NSFont systemFontOfSize:11];
    [self.panel.contentView addSubview:self.shortcutStatus];
    [self button:@"Settings…" action:@selector(showSettingsWindow:) target:NSApp.delegate frame:NSMakeRect(20, 20, 120, 30)];
    [self button:@"Quit" action:@selector(terminate:) target:NSApp frame:NSMakeRect(450, 20, 90, 30)];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.shortcutEnabled.state = [defaults boolForKey:@"usageShortcutEnabled"];
    [self.shortcutKey selectItemWithTag:[defaults integerForKey:@"usageShortcutKey"]];
    for(NSButton *button in self.modifierButtons)
        button.state = ([defaults integerForKey:@"usageShortcutModifiers"] & button.tag) != 0;
}

- (void)showPanel
{
    if(self.panel == nil) [self createPanel];
    [self updateWithAwake:self.awake refreshing:self.refreshing];
    // Recover a saved frame after unplugging a monitor.
    BOOL onScreen = NO;
    for(NSScreen *screen in NSScreen.screens)
        if(NSIntersectsRect(screen.visibleFrame, self.panel.frame)) onScreen = YES;
    if(!onScreen) [self.panel center];
    [NSApp activateIgnoringOtherApps:YES];
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)applyDockPreference
{
    [NSApp setActivationPolicy:[NSUserDefaults.standardUserDefaults boolForKey:@"usageShowInDock"] ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
}

- (void)toggleDock:(id)sender
{
    BOOL enabled = self.dockButton.state == NSControlStateValueOn;
    if([NSApp setActivationPolicy:enabled ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory])
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"usageShowInDock"];
    else self.dockButton.state = [NSUserDefaults.standardUserDefaults boolForKey:@"usageShowInDock"];
    [self showPanel];
}

- (void)applyShortcut:(id)sender
{
    UInt32 modifiers = 0;
    for(NSButton *button in self.modifierButtons)
        if(button.state == NSControlStateValueOn) modifiers |= (UInt32)button.tag;
    UInt32 key = (UInt32)self.shortcutKey.selectedTag;
    BOOL enabled = self.shortcutEnabled.state == NSControlStateValueOn;
    if([self registerKey:key modifiers:modifiers enabled:enabled])
    {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setBool:enabled forKey:@"usageShortcutEnabled"];
        [defaults setInteger:key forKey:@"usageShortcutKey"];
        [defaults setInteger:modifiers forKey:@"usageShortcutModifiers"];
    }
    self.shortcutStatus.stringValue = self.shortcutMessage ?: @"";
}

- (void)updateWithAwake:(BOOL)awake refreshing:(BOOL)refreshing
{
    self.awake = awake;
    self.refreshing = refreshing;
    if(self.panel == nil) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.awakeButton.state = awake;
    self.refreshButton.enabled = !refreshing;
    self.refreshButton.title = refreshing ? @"Refreshing…" : @"Refresh Usage";
    self.codexButton.title = [defaults boolForKey:@"usageCodexConnected"] ? @"Disconnect Codex" : @"Connect Codex…";
    self.kimiButton.title = [defaults boolForKey:@"usageKimiConnected"] ? @"Disconnect Kimi Code" : @"Connect Kimi Code…";
    self.dockButton.state = [defaults boolForKey:@"usageShowInDock"];
    self.legacyButton.state = [defaults boolForKey:@"usageLegacyClickBehavior"];
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    for(NSInteger tag = 810; tag <= 811; tag++)
    {
        NSMenuItem *provider = [self.menu itemWithTag:tag];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[provider.title stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:14], NSForegroundColorAttributeName: NSColor.labelColor}]];
        for(NSMenuItem *row in provider.submenu.itemArray)
        {
            NSColor *color = NSColor.labelColor;
            if([row.view.subviews.firstObject isKindOfClass:NSTextField.class])
                color = [(NSTextField *)row.view.subviews.firstObject textColor] ?: color;
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:[row.title stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: color}]];
        }
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    [self.usageText.textStorage setAttributedString:text];
}
@end
