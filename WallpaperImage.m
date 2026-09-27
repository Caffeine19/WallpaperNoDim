#import "WallpaperImage.h"
#import <math.h>

static NSDictionary *AppearanceMapping(CGImageMetadataRef metadata, NSString *key) {
    CFStringRef raw = CGImageMetadataCopyStringValueWithPath(
        metadata, NULL, (__bridge CFStringRef)[@"apple_desktop:" stringByAppendingString:key]);
    if (!raw) return nil;
    NSString *encoded = CFBridgingRelease(raw);
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded
                                                     options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) return nil;
    id decoded = [NSPropertyListSerialization propertyListWithData:data options:0
                                                          format:NULL error:NULL];
    if (![decoded isKindOfClass:NSDictionary.class]) return nil;
    id mapping = decoded[@"ap"] ?: decoded;
    return [mapping isKindOfClass:NSDictionary.class] ? mapping : nil;
}

size_t WallpaperImageIndex(CGImageSourceRef source, BOOL dark) {
    size_t count = CGImageSourceGetCount(source);
    if (!count) return 0;
    size_t primary = CGImageSourceGetPrimaryImageIndex(source);
    if (primary >= count) primary = 0;
    for (NSNumber *candidate in @[@0, @(primary)]) {
        CGImageMetadataRef metadata = CGImageSourceCopyMetadataAtIndex(
            source, candidate.unsignedIntegerValue, NULL);
        if (!metadata) continue;
        for (NSString *key in @[@"apr", @"solar", @"h24"]) {
            id value = AppearanceMapping(metadata, key)[dark ? @"d" : @"l"];
            if (![value isKindOfClass:NSNumber.class]) continue;
            double number = [value doubleValue];
            if (!isfinite(number) || number < 0 || number >= count || floor(number) != number)
                continue;
            CFRelease(metadata);
            return (size_t)number;
        }
        CFRelease(metadata);
    }
    return primary;
}

CGImageRef CopyWallpaperImage(NSURL *url, BOOL dark, NSUInteger maxPixelSize,
                             size_t *selectedIndex) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return NULL;
    if (!CGImageSourceGetCount(source)) { CFRelease(source); return NULL; }
    size_t index = WallpaperImageIndex(source, dark);
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(maxPixelSize, 1)),
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(
        source, index, (__bridge CFDictionaryRef)options);
    if (selectedIndex) *selectedIndex = index;
    CFRelease(source);
    return image;
}
