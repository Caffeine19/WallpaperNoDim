#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreServices/CoreServices.h>
#import <ServiceManagement/ServiceManagement.h>
#include <sys/stat.h>
#import "WallpaperImage.h"

static void *AppearanceObservation = &AppearanceObservation;
static NSString *const WallpaperCachePath = @"/private/var/db/Wallpapers";
static NSString *const WallpaperRevealAnimation = @"WallpaperReveal";

static NSString *WallpaperStoreDirectory(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/com.apple.wallpaper/Store"];
}

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

static NSURL *WallpaperConfigurationFileURL(NSDictionary *configuration) {
    id location = configuration[@"url"];
    if ([location isKindOfClass:NSDictionary.class]) location = location[@"relative"];
    if (![location isKindOfClass:NSString.class]) return nil;
    NSString *value = location;
    if (value.isAbsolutePath) return [NSURL fileURLWithPath:value];
    NSURL *url = [NSURL URLWithString:value];
    return url.isFileURL && url.path.isAbsolutePath ? url : nil;
}

static NSString *ConfiguredAppearance(NSURL *url, NSArray<NSDictionary *> *settings) {
    for (NSDictionary *set in settings) {
        NSDictionary *content = DesktopContent(set);
        NSArray *choices = WallpaperChoices(content);
        for (id choice in choices) {
            if (![choice isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *configuration = DecodePropertyList(choice[@"Configuration"]);
            NSURL *choiceURL = WallpaperConfigurationFileURL(configuration);
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

static NSDictionary *ConfiguredWallpaperContent(NSArray<NSDictionary *> *settings) {
    for (NSDictionary *set in settings) {
        NSDictionary *content = DesktopContent(set);
        if (WallpaperChoices(content).count) return content;
    }
    return nil;
}

static BOOL IsDefaultWallpaperURL(NSURL *url) {
    if (!url) return YES;
    NSURL *defaultURL = [NSURL fileURLWithPath:@"/System/Library/CoreServices/DefaultDesktop.heic"];
    return [url.URLByResolvingSymlinksInPath.path
        isEqualToString:defaultURL.URLByResolvingSymlinksInPath.path];
}

static NSURL *CachedWallpaperURL(NSDictionary *configured, NSURL *cacheDirectory) {
    NSArray *choices = WallpaperChoices(configured);
    if (!choices.count) return nil;
    id options = configured[@"EncodedOptionValues"] ?: configured[@"OptionValues"];
    NSDictionary *configuredOptions = DecodePropertyList(options);
    if (options && !configuredOptions) return nil;
    id configuredShuffle = configured[@"Shuffle"] ?: @"$null";

    NSFileManager *files = NSFileManager.defaultManager;
    NSArray<NSURL *> *entries = [files contentsOfDirectoryAtURL:cacheDirectory
        includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    for (NSURL *entry in entries) {
        NSURL *metadataURL = [entry URLByAppendingPathComponent:@"Metadata.plist"];
        NSDictionary *metadata = DecodePropertyList([NSData dataWithContentsOfURL:metadataURL]);
        NSDictionary *content = DecodePropertyList(metadata[@"Content"]);
        // The system cache is shared across wallpaper providers and screens.
        if (![WallpaperChoices(content) isEqualToArray:choices]) continue;
        if (![configuredShuffle isEqual:content[@"Shuffle"] ?: @"$null"]) continue;
        NSDictionary *cachedOptions = DecodePropertyList(content[@"OptionValues"] ?: content[@"EncodedOptionValues"]);
        if (configuredOptions && ![configuredOptions isEqual:cachedOptions]) continue;
        NSURL *imageURL = [entry URLByAppendingPathComponent:@"Wallpaper.png"];
        if ([files isReadableFileAtPath:imageURL.path]) return imageURL;
    }
    return nil;
}

static NSURL *ConfiguredWallpaperFileURL(NSDictionary *content) {
    NSArray *choices = WallpaperChoices(content);
    if (choices.count != 1) return nil;
    NSDictionary *choice = DecodePropertyList(choices.firstObject);
    return WallpaperConfigurationFileURL(DecodePropertyList(choice[@"Configuration"]));
}

static NSArray *WallpaperImageFileState(NSURL *url) {
    NSString *path = url.URLByResolvingSymlinksInPath.path;
    struct stat info;
    if (!path || stat(path.fileSystemRepresentation, &info) != 0) return nil;
    // WallpaperAgent may rewrite its store without touching the selected image.
    return @[path, @(info.st_dev), @(info.st_ino), @(info.st_size),
             @(info.st_mtimespec.tv_sec), @(info.st_mtimespec.tv_nsec)];
}

static CALayer *WallpaperImageLayer(CALayer *parent, CGImageRef image) {
    CALayer *layer = [CALayer layer];
    layer.frame = parent.bounds;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.contentsGravity = kCAGravityResizeAspectFill;
    layer.contents = (__bridge id)image;
    return layer;
}

static CABasicAnimation *WallpaperOpacityAnimation(NSNumber *from, NSNumber *to) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = from;
    animation.toValue = to;
    animation.duration = 0.4;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    return animation;
}

@interface WallpaperOverlay : NSObject
@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, copy) NSArray *renderInput;
@property (nonatomic) size_t imageIndex;
@property (nonatomic) CALayer *canvas;
@property (nonatomic, weak) CALayer *imageLayer;
@property (nonatomic) NSTimer *pendingHide;
- (instancetype)initWithFrame:(NSRect)frame;
- (void)moveToFrame:(NSRect)frame;
- (void)showImage:(CGImageRef)image inFrame:(NSRect)frame transition:(BOOL)transition;
- (void)deferHiding;
- (void)cancelPendingHide;
- (void)hide;
@end

@implementation WallpaperOverlay
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super init];
    if (!self) return nil;

    _window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless
        backing:NSBackingStoreBuffered defer:NO];
    _window.releasedWhenClosed = NO;
    _window.level = CGWindowLevelForKey(kCGDesktopWindowLevelKey) + 1;
    _window.ignoresMouseEvents = YES;
    _window.opaque = NO;
    _window.backgroundColor = NSColor.clearColor;
    _window.hasShadow = NO;
    _window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    view.wantsLayer = YES;
    _canvas = [CALayer layer];
    _canvas.frame = view.bounds;
    _canvas.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _canvas.backgroundColor = NSColor.blackColor.CGColor;
    _canvas.allowsGroupOpacity = YES;
    [view.layer addSublayer:_canvas];
    _window.contentView = view;
    return self;
}

- (void)moveToFrame:(NSRect)frame {
    if (!NSEqualRects(self.window.frame, frame))
        [self.window setFrame:frame display:YES animate:NO];
}

- (void)showImage:(CGImageRef)image inFrame:(NSRect)frame transition:(BOOL)transition {
    [self cancelPendingHide];
    BOOL showingWindow = !self.window.isVisible;
    BOOL animate = (showingWindow || transition) &&
        !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self moveToFrame:frame];
    CALayer *previous = self.imageLayer;
    if (animate || !previous) {
        CALayer *incoming = WallpaperImageLayer(self.canvas, image);
        incoming.backgroundColor = NSColor.blackColor.CGColor;
        incoming.allowsGroupOpacity = YES;
        [self.canvas addSublayer:incoming];
        self.imageLayer = incoming;
        if (animate) {
            CALayer *fadeLayer = showingWindow ? self.canvas : incoming;
            [self animateImage:image overLayer:previous fadingLayer:fadeLayer];
        }
    } else {
        previous.contents = (__bridge id)image;
    }
    [CATransaction commit];
    if (showingWindow) [self.window orderFrontRegardless];
}

- (void)animateImage:(CGImageRef)image overLayer:(CALayer *)previous fadingLayer:(CALayer *)fadeLayer {
    // Keep older layers in place until the incoming image covers them.
    CGImageRef blurredImage = CopyBlurredWallpaperPreview(image);
    CALayer *preview = nil;
    if (blurredImage) {
        preview = WallpaperImageLayer(self.imageLayer, blurredImage);
        CFRelease(blurredImage);
        preview.opacity = 0;
        [self.imageLayer addSublayer:preview];
    }
    [CATransaction setCompletionBlock:^{
        [preview removeFromSuperlayer];
        [previous removeFromSuperlayer];
    }];
    [fadeLayer addAnimation:WallpaperOpacityAnimation(@0, @1) forKey:WallpaperRevealAnimation];
    [preview addAnimation:WallpaperOpacityAnimation(@1, @0) forKey:WallpaperRevealAnimation];
}

- (void)deferHiding {
    if (!self.imageLayer || self.pendingHide) return;
    // The new wallpaper's rendered cache can arrive after its configuration.
    __weak WallpaperOverlay *overlay = self;
    self.pendingHide = [NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
        [overlay hide];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.pendingHide forMode:NSRunLoopCommonModes];
}

- (void)cancelPendingHide {
    [self.pendingHide invalidate];
    self.pendingHide = nil;
}

- (void)hide {
    [self cancelPendingHide];
    if (self.window.isVisible) [self.window orderOut:nil];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.canvas removeAnimationForKey:WallpaperRevealAnimation];
    self.canvas.sublayers = nil;
    self.imageLayer = nil;
    [CATransaction commit];
    self.renderInput = nil;
}
@end

@interface WallpaperTest : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property NSDictionary<NSNumber *, WallpaperOverlay *> *overlays;
@property NSStatusItem *status;
@property NSMenuItem *loginItem;
@property NSMenuItem *loginSettingsItem;
@property (nonatomic, assign) FSEventStreamRef wallpaperEvents;
- (void)scheduleWallpaperRefresh;
@end

static void WallpaperFilesDidChange(ConstFSEventStreamRef stream, void *context,
                                    size_t count, void *eventPaths,
                                    const FSEventStreamEventFlags flags[],
                                    const FSEventStreamEventId eventIDs[]) {
    NSArray<NSString *> *paths = (__bridge NSArray *)eventPaths;
    WallpaperTest *app = (__bridge WallpaperTest *)context;
    for (size_t i = 0; i < count; i++) {
        NSString *name = paths[i].lastPathComponent;
        BOOL replacedDirectory = (flags[i] & kFSEventStreamEventFlagItemIsDir) &&
            (flags[i] & (kFSEventStreamEventFlagItemCreated |
                         kFSEventStreamEventFlagItemRemoved |
                         kFSEventStreamEventFlagItemRenamed));
        if ((flags[i] & kFSEventStreamEventFlagMustScanSubDirs) || replacedDirectory ||
            [name isEqualToString:@"Index.plist"] || [name isEqualToString:@"Metadata.plist"] ||
            [name isEqualToString:@"Wallpaper.png"]) {
            [app scheduleWallpaperRefresh];
            return;
        }
    }
}

@implementation WallpaperTest
- (void)applicationDidFinishLaunching:(NSNotification *)note {
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
    [self watchWallpaperDirectories:@[WallpaperStoreDirectory(), WallpaperCachePath]];
    [self refreshWallpaper:nil];
}

- (void)watchWallpaperDirectories:(NSArray<NSString *> *)paths {
    FSEventStreamContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    FSEventStreamRef stream = FSEventStreamCreate(NULL, WallpaperFilesDidChange, &context,
        (__bridge CFArrayRef)paths, kFSEventStreamEventIdSinceNow, 0.2,
        kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents);
    if (stream) {
        FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue());
        if (FSEventStreamStart(stream)) {
            self.wallpaperEvents = stream;
            NSLog(@"Watching wallpaper configuration and cache for changes");
            return;
        }
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
    }
    NSLog(@"Unable to start automatic wallpaper refresh");
}

- (void)stopWatchingWallpaperDirectories {
    if (self.wallpaperEvents) {
        FSEventStreamStop(self.wallpaperEvents);
        FSEventStreamInvalidate(self.wallpaperEvents);
        FSEventStreamRelease(self.wallpaperEvents);
        self.wallpaperEvents = NULL;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(refreshAfterWallpaperChange) object:nil];
}

- (void)scheduleWallpaperRefresh {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(refreshAfterWallpaperChange) object:nil];
    [self performSelector:@selector(refreshAfterWallpaperChange) withObject:nil
        afterDelay:0.3 inModes:@[NSRunLoopCommonModes]];
}

- (void)refreshAfterWallpaperChange {
    NSLog(@"Wallpaper files changed; checking overlays");
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
    NSString *storePath = [WallpaperStoreDirectory() stringByAppendingPathComponent:@"Index.plist"];
    NSDictionary *store = DecodePropertyList([NSData dataWithContentsOfFile:storePath]);
    NSURL *cacheDirectory = [NSURL fileURLWithPath:WallpaperCachePath isDirectory:YES];
    BOOL forceReload = [sender isKindOfClass:NSMenuItem.class];
    NSMutableDictionary<NSNumber *, WallpaperOverlay *> *attachedOverlays = [NSMutableDictionary dictionary];

    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *displayID = screen.deviceDescription[@"NSScreenNumber"];
        if (!displayID) continue;
        WallpaperOverlay *overlay = self.overlays[displayID];
        if (overlay) attachedOverlays[displayID] = overlay;

        NSArray<NSDictionary *> *settings = WallpaperSettings(screen, store);
        NSURL *url = [NSWorkspace.sharedWorkspace desktopImageURLForScreen:screen];
        BOOL usesSystemCache = NO;
        if (IsDefaultWallpaperURL(url)) {
            NSDictionary *content = ConfiguredWallpaperContent(settings);
            url = CachedWallpaperURL(content, cacheDirectory);
            usesSystemCache = url != nil;
            if (!url) url = ConfiguredWallpaperFileURL(content);
        }
        if (!url) {
            NSLog(@"No matching wallpaper image for %@", screen.localizedName);
            [overlay deferHiding];
            continue;
        }
        NSString *override = ConfiguredAppearance(url, settings);
        BOOL dark = !usesSystemCache && ([override isEqualToString:@"dark"] ||
            (systemDark && ![override isEqualToString:@"light"]));
        NSUInteger maxPixels = (NSUInteger)ceil(MAX(screen.frame.size.width,
            screen.frame.size.height) * screen.backingScaleFactor);
        NSArray *fileState = WallpaperImageFileState(url);
        NSArray *renderInput = fileState ? @[fileState, @(dark), @(maxPixels)] : nil;
        if (!forceReload && renderInput && [overlay.renderInput isEqualToArray:renderInput]) {
            [overlay cancelPendingHide];
            [overlay moveToFrame:screen.frame];
            continue;
        }

        size_t index = 0;
        CGImageRef image = CopyWallpaperImage(url, dark, maxPixels, &index);
        if (!image) {
            NSLog(@"Unable to load wallpaper for %@: %@", screen.localizedName, url.path);
            [overlay deferHiding];
            continue;
        }

        if (!overlay) {
            overlay = [[WallpaperOverlay alloc] initWithFrame:screen.frame];
            attachedOverlays[displayID] = overlay;
        }
        BOOL newImage = (fileState && ![fileState isEqual:overlay.renderInput.firstObject]) ||
            overlay.imageIndex != index;
        [overlay showImage:image inFrame:screen.frame transition:newImage];
        overlay.renderInput = renderInput;
        overlay.imageIndex = index;
        CFRelease(image);
        NSString *renderedAppearance = usesSystemCache ? @"rendered snapshot" : (dark ? @"dark" : @"light");
        NSLog(usesSystemCache ? @"Wallpaper refreshed from system cache: %@, %@, frame %zu, %@" :
              @"Wallpaper refreshed: %@, %@, frame %zu, %@", screen.localizedName,
              url.lastPathComponent, index, renderedAppearance);
    }
    for (NSNumber *displayID in self.overlays) {
        if (attachedOverlays[displayID]) continue;
        WallpaperOverlay *overlay = self.overlays[displayID];
        [overlay hide];
        [overlay.window close];
    }
    self.overlays = attachedOverlays;
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
    [self stopWatchingWallpaperDirectories];
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
