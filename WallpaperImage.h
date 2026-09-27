#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

size_t WallpaperImageIndex(CGImageSourceRef source, BOOL dark);
CGImageRef CopyWallpaperImage(NSURL *url, BOOL dark, NSUInteger maxPixelSize,
                             size_t *selectedIndex) CF_RETURNS_RETAINED;
