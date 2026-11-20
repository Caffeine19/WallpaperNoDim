#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ServiceManagement/ServiceManagement.h>
#import "WallpaperImage.h"

static void *AppearanceObservation = &AppearanceObservation;

static NSDictionary *DecodePropertyList(id value) {
    if ([value isKindOfClass:NSDictionary.class]) return value;
    if (![value isKindOfClass:NSData.class]) return nil;
    id decoded = [NSPropertyListSerialization propertyListWithData:value options:0
                                                          format:NULL error:NULL];
    return [decoded isKindOfClass:NSDictionary.class] ? decoded : nil;
}

// Read recognized appearance options without depending on a private framework.
static NSString *AppearanceValue(id value) {
    if ([value isKindOfClass:NSString.class]) {
        NSString *name = [value lowercaseString];
        return [@[@"dark", @"light", @"automatic", @"auto", @"dynamic"] containsObject:name]
            ? name : nil;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        for (NSString *name in @[@"dark", @"light", @"automatic", @"dynamic"])
            if (value[name]) return name;
        for (id nested in [value allValues]) {
            NSString *name = AppearanceValue(nested);
            if (name) return name;
        }
    }
    return nil;
}

static NSString *FindAppearanceOption(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *key in value) {
        NSString *name = key.lowercaseString;
        if ([name containsString:@"appearance"] || [name containsString:@"dynamicstyle"] ||
            [name containsString:@"dynamicdesktopstyle"]) {
            NSString *option = AppearanceValue(value[key]);
            if (option) return option;
        }
    }
    for (id nested in [value allValues]) {
        NSString *option = FindAppearanceOption(nested);
        if (option) return option;
    }
    return nil;
}

static NSArray<NSDictionary *> *WallpaperSettings(NSScreen *screen, NSDictionary *store) {
    CGDirectDisplayID displayID = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    NSString *identifier = uuid ? CFBridgingRelease(CFUUIDCreateString(NULL, uuid)) : nil;
    if (uuid) CFRelease(uuid);
    NSMutableArray<NSDictionary *> *sets = [NSMutableArray array];
    NSDictionary *displays = DecodePropertyList(store[@"Displays"]);
    NSDictionary *display = identifier ? DecodePropertyList(displays[identifier]) : nil;
    if (display) [sets addObject:display];
    for (NSString *key in @[@"AllSpacesAndDisplays", @"SystemDefault"])
        if ([store[key] isKindOfClass:NSDictionary.class]) [sets addObject:store[key]];
    return sets;
}

static NSDictionary *DesktopContent(NSDictionary *settings) {
    NSDictionary *desktop = DecodePropertyList(settings[@"Desktop"]);
    if (!desktop) desktop = DecodePropertyList(settings[@"Linked"]);
    return DecodePropertyList(desktop[@"Content"]);
}

static NSArray *WallpaperChoices(NSDictionary *content) {
    id choices = content[@"Choices"];
    return [choices isKindOfClass:NSArray.class] ? choices : nil;
}

static NSString *ConfiguredAppearance(NSURL *url, NSArray<NSDictionary *> *settings) {
    for (NSDictionary *set in settings) {
        NSDictionary *content = DesktopContent(set);
        NSArray *choices = WallpaperChoices(content);
        for (id choice in choices) {
            if (![choice isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *configuration = DecodePropertyList(choice[@"Configuration"]);
            id configuredURL = configuration[@"url"];
            NSString *location = [configuredURL isKindOfClass:NSDictionary.class]
                ? configuredURL[@"relative"] : nil;
            if (![location isKindOfClass:NSString.class]) continue;
            NSURL *choiceURL = [NSURL URLWithString:location];
            if (![choiceURL.URLByResolvingSymlinksInPath.path
                    isEqualToString:url.URLByResolvingSymlinksInPath.path]) continue;
            NSString *option = FindAppearanceOption(configuration);
            if (!option) option = FindAppearanceOption(
                DecodePropertyList(content[@"EncodedOptionValues"]));
            if (option) return option;
        }
    }
    return nil;
}

static NSArray *ConfiguredPhotoChoices(NSArray<NSDictionary *> *settings) {
    for (NSDictionary *set in settings) {
        NSArray *choices = WallpaperChoices(DesktopContent(set));
        if (!choices.count) continue;
        NSDictionary *choice = DecodePropertyList(choices.firstObject);
        NSDictionary *configuration = DecodePropertyList(choice[@"Configuration"]);
        if (choices.count == 1 &&
            [choice[@"Provider"] isEqual:@"com.apple.wallpaper.extension.photos"] &&
            [configuration[@"type"] isEqual:@"asset"] &&
            [configuration[@"identifier"] isKindOfClass:NSString.class]) return choices;
        break;
    }
    return nil;
}

static BOOL IsDefaultWallpaperURL(NSURL *url) {
    if (!url) return YES;
    NSURL *defaultURL = [NSURL fileURLWithPath:@"/System/Library/CoreServices/DefaultDesktop.heic"];
    return [url.URLByResolvingSymlinksInPath.path
        isEqualToString:defaultURL.URLByResolvingSymlinksInPath.path];
}

static NSURL *CachedPhotoWallpaperURL(NSArray *choices, NSURL *cacheDirectory) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSArray<NSURL *> *entries = [files contentsOfDirectoryAtURL:cacheDirectory
        includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    for (NSURL *entry in entries) {
        NSURL *metadataURL = [entry URLByAppendingPathComponent:@"Metadata.plist"];
        NSDictionary *metadata = DecodePropertyList([NSData dataWithContentsOfURL:metadataURL]);
        NSDictionary *content = DecodePropertyList(metadata[@"Content"]);
        // The system cache is shared. A matching choice proves it contains this photo.
        if (![WallpaperChoices(content) isEqualToArray:choices]) continue;
        NSURL *imageURL = [entry URLByAppendingPathComponent:@"Wallpaper.png"];
        if ([files isReadableFileAtPath:imageURL.path]) return imageURL;
    }
    return nil;
}

@interface WallpaperTest : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property NSMutableArray<NSWindow *> *windows;
@property NSStatusItem *status;
@property NSMenuItem *loginItem;
@property NSMenuItem *loginSettingsItem;
@end

@implementation WallpaperTest
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.windows = [NSMutableArray array];
    self.status = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"warninglight"
                            accessibilityDescription:@"WallpaperNoDim"];
    icon.template = YES;
    self.status.button.image = icon;
    self.status.button.toolTip = @"WallpaperNoDim";
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    NSMenuItem *refresh = [menu addItemWithTitle:@"Refresh Wallpaper"
                                        action:@selector(refreshWallpaper:) keyEquivalent:@"r"];
    refresh.target = self;
    self.loginItem = [menu addItemWithTitle:@"Launch at Login"
        action:@selector(toggleLaunchAtLogin:) keyEquivalent:@""];
    self.loginItem.target = self;
    self.loginSettingsItem = [menu addItemWithTitle:@"Open Login Items Settings…"
        action:@selector(openLoginSettings:) keyEquivalent:@""];
    self.loginSettingsItem.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit and restore wallpaper" action:@selector(terminate:)
            keyEquivalent:@"q"];
    self.status.menu = menu;
    // Register once by default. Later launches respect changes made in System Settings.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:@"DidInitializeLaunchAtLogin"]) {
        [defaults setBool:YES forKey:@"DidInitializeLaunchAtLogin"];
        if (SMAppService.mainAppService.status == SMAppServiceStatusNotRegistered)
            [self setLaunchAtLogin:YES];
    }
    [self updateLoginMenu];
    [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0
               context:AppearanceObservation];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshWallpaper:)
        name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [self refreshWallpaper:nil];
}

- (void)updateLoginMenu {
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    BOOL pending = status == SMAppServiceStatusRequiresApproval;
    self.loginItem.state = status == SMAppServiceStatusEnabled ? NSControlStateValueOn :
                           pending ? NSControlStateValueMixed : NSControlStateValueOff;
    self.loginItem.toolTip = pending ? @"Approval is required in System Settings." : nil;
    self.loginSettingsItem.hidden = !pending;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [self updateLoginMenu];
}

- (void)setLaunchAtLogin:(BOOL)enabled {
    NSError *error = nil;
    BOOL success = enabled ? [SMAppService.mainAppService registerAndReturnError:&error] :
                             [SMAppService.mainAppService unregisterAndReturnError:&error];
    if (!success) {
        NSLog(@"Unable to %@ launch at login: %@", enabled ? @"enable" : @"disable", error);
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Unable to update Launch at Login";
        alert.informativeText = error.localizedDescription ?: @"Please try again.";
        [alert runModal];
    }
    [self updateLoginMenu];
}

- (void)toggleLaunchAtLogin:(id)sender {
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    [self setLaunchAtLogin:!(status == SMAppServiceStatusEnabled ||
                            status == SMAppServiceStatusRequiresApproval)];
}

- (void)openLoginSettings:(id)sender {
    [SMAppService openSystemSettingsLoginItems];
}

- (void)refreshWallpaper:(id)sender {
    NSString *appearance = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL systemDark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    NSString *storePath = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/com.apple.wallpaper/Store/Index.plist"];
    NSDictionary *store = DecodePropertyList([NSData dataWithContentsOfFile:storePath]);
    NSURL *cacheDirectory = [NSURL fileURLWithPath:@"/private/var/db/Wallpapers" isDirectory:YES];
    NSMutableArray<NSWindow *> *replacement = [NSMutableArray array];

    for (NSScreen *screen in NSScreen.screens) {
        NSArray<NSDictionary *> *settings = WallpaperSettings(screen, store);
        NSURL *url = [NSWorkspace.sharedWorkspace desktopImageURLForScreen:screen];
        BOOL isCachedPhoto = NO;
        if (IsDefaultWallpaperURL(url)) {
            NSArray *choices = ConfiguredPhotoChoices(settings);
            if (choices) {
                url = CachedPhotoWallpaperURL(choices, cacheDirectory);
                if (!url) {
                    NSLog(@"No matching Photos wallpaper cache for %@", screen.localizedName);
                    continue;
                }
                isCachedPhoto = YES;
            }
        }
        if (!url) continue;
        NSString *override = ConfiguredAppearance(url, settings);
        BOOL dark = [override isEqualToString:@"dark"] ? YES :
                    [override isEqualToString:@"light"] ? NO : systemDark;
        NSUInteger maxPixels = (NSUInteger)ceil(MAX(screen.frame.size.width,
            screen.frame.size.height) * screen.backingScaleFactor);
        size_t index = 0;
        CGImageRef image = CopyWallpaperImage(url, dark, maxPixels, &index);
        if (!image) {
            NSLog(@"Unable to load wallpaper for %@: %@", screen.localizedName, url.path);
            continue;
        }

        NSWindow *window = [[NSWindow alloc] initWithContentRect:screen.frame
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.level = CGWindowLevelForKey(kCGDesktopWindowLevelKey) + 1;
        window.ignoresMouseEvents = YES;
        window.opaque = YES;
        window.backgroundColor = NSColor.blackColor;
        window.hasShadow = NO;
        window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0,
            screen.frame.size.width, screen.frame.size.height)];
        view.wantsLayer = YES;
        view.layer.contents = (__bridge id)image;
        view.layer.contentsGravity = kCAGravityResizeAspectFill;
        CFRelease(image);
        window.contentView = view;
        [window orderFrontRegardless];
        [replacement addObject:window];
        NSLog(isCachedPhoto ? @"Wallpaper refreshed from Photos cache: %@, %@, frame %zu, %@" :
              @"Wallpaper refreshed: %@, %@, frame %zu, %@", screen.localizedName,
              url.lastPathComponent, index, dark ? @"dark" : @"light");
    }
    // Close previous overlays so removed screens and unavailable images do not stay stale.
    for (NSWindow *window in self.windows) [window close];
    self.windows = replacement;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                       change:(NSDictionary *)change context:(void *)context {
    if (context == AppearanceObservation) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshWallpaper:nil]; });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:AppearanceObservation];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        WallpaperTest *delegate = [WallpaperTest new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
