#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
@interface WallpaperTest : NSObject <NSApplicationDelegate>
@property NSMutableArray<NSWindow *> *windows;
@property NSStatusItem *status;
@end
@implementation WallpaperTest
- (void)applicationDidFinishLaunching:(NSNotification *)note {
 self.windows=[NSMutableArray array];
 for(NSScreen *screen in NSScreen.screens) {
  NSURL *url=[NSWorkspace.sharedWorkspace desktopImageURLForScreen:screen];
  NSImage *image=url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
  if(!image) continue;
  NSWindow *window=[[NSWindow alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.level=CGWindowLevelForKey(kCGDesktopWindowLevelKey)+1;
  window.ignoresMouseEvents=YES;
  window.opaque=YES;
  window.backgroundColor=NSColor.blackColor;
  window.hasShadow=NO;
  window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorStationary|NSWindowCollectionBehaviorIgnoresCycle;
  NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,screen.frame.size.width,screen.frame.size.height)];
  view.wantsLayer=YES;
  NSRect proposed=view.bounds;
  view.layer.contents=(__bridge id)[image CGImageForProposedRect:&proposed context:nil hints:nil];
  view.layer.contentsGravity=kCAGravityResizeAspectFill;
  window.contentView=view;
  [window orderFrontRegardless];
  [self.windows addObject:window];
 }
 self.status=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
 self.status.button.title=@"Wallpaper Test";
 NSMenu *menu=[NSMenu new];
 [menu addItemWithTitle:@"Quit and restore wallpaper" action:@selector(terminate:) keyEquivalent:@"q"];
 self.status.menu=menu;
 printf("Desktop overlay running: %lu screens; use menu-bar item to quit.\n",(unsigned long)self.windows.count);fflush(stdout);
}
@end
int main(void) { @autoreleasepool {
 NSApplication *app=NSApplication.sharedApplication;
 [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
 WallpaperTest *delegate=[WallpaperTest new];
 app.delegate=delegate;
 [app run];
}return 0;}
