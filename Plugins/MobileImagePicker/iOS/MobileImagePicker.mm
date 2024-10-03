// Credit: https://github.com/yasirkula/UnityNativeGallery/blob/master/Plugins/NativeGallery/iOS/NativeGallery.mm

#import <PhotosUI/PhotosUI.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <ImageIO/ImageIO.h>

extern UIViewController* UnityGetGLViewController();


typedef void (*DelegateCallbackFunction)(char* path);

@protocol MediaPickedDelegate <NSObject>
- (void)mediaPicked:(char*)path;
@end

@interface MediaPickedClass : NSObject
+ (void)sendPathToDelegate:(char*) path;
+ (void)setDelegate:(id<MediaPickedDelegate>)delegate;
@end

@implementation MediaPickedClass
    id __mpdelegate = nil;

    + (void)sendPathToDelegate:(char*) path{
        if (__mpdelegate && [__mpdelegate respondsToSelector:@selector(mediaPicked:)]) {
            [__mpdelegate mediaPicked:path];
        }
    }
    
    +(void)setDelegate:(id<MediaPickedDelegate>)delegate {
        __mpdelegate = delegate;
    }
@end

@interface MobileImagePicker:NSObject<MediaPickedDelegate>
+ (void)pickMedia:(NSString *)mediaSavePath selectImages:(BOOL)selectImages selectVideos:(BOOL)selectVideos callback:(DelegateCallbackFunction)callback;
+ (void)setCallback:(DelegateCallbackFunction)delegate;
@end


@implementation MobileImagePicker

static MobileImagePicker        *__MMPDelegate = nil;
static DelegateCallbackFunction _MMPCallback   = nil;

+(void)setCallback:(DelegateCallbackFunction)delegate
{
    if( !__MMPDelegate ){
        __MMPDelegate = [[MobileImagePicker alloc] init];
    }
    
    [MediaPickedClass setDelegate:__MMPDelegate];
    _MMPCallback = delegate;
}

-(void)mediaPicked:(char *)path
{
    if( _MMPCallback != NULL ){
        _MMPCallback(path);
    }
}

+(void)sendPathToUnity:(NSString*) path
{
    if( pickedType == 1 && path != nil && path.length > 0 )
    {
        char* cspath = [self loadImageAtPath:path tempFilePath:pickedMediaSavePath maximumSize:4096];
        [MediaPickedClass sendPathToDelegate:cspath];
    }
    else
    {
        [MediaPickedClass sendPathToDelegate:[self getCString:path]];
    }
}

static NSString                 *pickedMediaSavePath;
static int                      imagePickerState;
static int                      pickedType;
static PHPickerViewController   *imagePickerNew;

// Credit: https://stackoverflow.com/a/10531752/2373034
+ (void)pickMedia:(NSString *)mediaSavePath selectImages:(BOOL)selectImages selectVideos:(BOOL)selectVideos callback:(DelegateCallbackFunction)callback
{
    [self setCallback:callback];
    
	pickedMediaSavePath  = mediaSavePath;
    imagePickerState     = 1;
    
    // PHPickerViewController is used on iOS 14
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    config.selectionLimit = 1;
    
    // selection filter
    if( selectImages && !selectVideos )
    {
        pickedType = 1;
        config.filter = [PHPickerFilter anyFilterMatchingSubfilters:[NSArray arrayWithObjects:[PHPickerFilter imagesFilter], [PHPickerFilter livePhotosFilter], nil]];
    }
    else if( selectVideos && !selectImages )
    {
        pickedType = 2;
        config.filter = [PHPickerFilter videosFilter];
    }
    else
    {
        pickedType = 3;
        config.filter = [PHPickerFilter anyFilterMatchingSubfilters:[NSArray arrayWithObjects:[PHPickerFilter imagesFilter], [PHPickerFilter livePhotosFilter], [PHPickerFilter videosFilter], nil]];
    }

    
    imagePickerNew = [[PHPickerViewController alloc] initWithConfiguration:config];
    imagePickerNew.delegate = (id)self;
    [UnityGetGLViewController() presentViewController:imagePickerNew animated:YES completion:^{ imagePickerState = 0; }];
}


// Credit: https://ikyle.me/blog/2020/phpickerviewcontroller
+(void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
	imagePickerNew   = nil;
	imagePickerState = 2;
	
	[picker dismissViewControllerAnimated:NO completion:nil];
	
	if( results != nil && [results count] > 0 )
	{
		NSMutableArray<NSString *> *resultPaths = [NSMutableArray arrayWithCapacity:[results count]];
		NSLock *arrayLock = [[NSLock alloc] init];
		dispatch_group_t group = dispatch_group_create();
		
		for( int i = 0; i < [results count]; i++ )
		{
            // this plugin don't support multiple selections
            if( i > 0 )
                break;
            
			PHPickerResult   *result       = results[i];
			NSItemProvider   *itemProvider = result.itemProvider;
			__block NSString *resultPath   = nil;
			
			int j = i + 1;

			if( [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeImage] )
			{
				NSLog( @"PHPickerViewController Picked an image" );
				
                dispatch_group_enter( group );
                
                [itemProvider loadFileRepresentationForTypeIdentifier:(NSString *)kUTTypeImage completionHandler:^( NSURL *url, NSError *error )
                {
                    if( url != nil )
                    {
                        // Copy the image to a temporary location because the returned image will be deleted by the OS after this callback is completed
                        resultPath = [url path];
                        NSString *newPath = [[NSString stringWithFormat:@"%@%d", pickedMediaSavePath, j] stringByAppendingPathExtension:[resultPath pathExtension]];
                        
                        if( ![[NSFileManager defaultManager] fileExistsAtPath:newPath] || [[NSFileManager defaultManager] removeItemAtPath:newPath error:&error] )
                        {
                            if( [[NSFileManager defaultManager] copyItemAtPath:resultPath toPath:newPath error:&error])
                                resultPath = newPath;
                            else
                            {
                                NSLog( @"Error copying image: %@", error );
                                resultPath = nil;
                            }
                        }
                        else
                        {
                            NSLog( @"Error deleting existing image: %@", error );
                            resultPath = nil;
                        }
                    }
                    else
                        NSLog( @"Error getting the picked image's path: %@", error );
                    
                    if( resultPath != nil )
                    {
                        [arrayLock lock];
                        [resultPaths addObject:resultPath];
                        [arrayLock unlock];
                    }
                    else
                    {
                        if( [itemProvider canLoadObjectOfClass:[UIImage class]] )
                        {
                            dispatch_group_enter( group );
                            
                            [itemProvider loadObjectOfClass:[UIImage class] completionHandler:^( __kindof id<NSItemProviderReading> object, NSError *error )
                            {
                                if( object != nil && [object isKindOfClass:[UIImage class]] )
                                {
                                    resultPath = [[NSString stringWithFormat:@"%@%d", pickedMediaSavePath, j] stringByAppendingPathExtension:@"png"];
                                    if( ![self saveImageAsPNG:(UIImage *)object toPath:resultPath] )
                                    {
                                        NSLog( @"Error creating PNG image" );
                                        resultPath = nil;
                                    }
                                }
                                else
                                    NSLog( @"Error generating UIImage from picked image: %@", error );
                                
                                [arrayLock lock];
                                [resultPaths addObject:( resultPath != nil ? resultPath : @"" )];
                                [arrayLock unlock];
                                
                                dispatch_group_leave( group );
                            }];
                        }
                        else
                        {
                            NSLog( @"Can't generate UIImage from picked image" );
                            
                            [arrayLock lock];
                            [resultPaths addObject:@""];
                            [arrayLock unlock];
                        }
                    }
                    
                    dispatch_group_leave( group );
                }];
				
			}
			else if( [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeLivePhoto] )
			{
				NSLog( @"Picked a live photo" );
				
				if( [itemProvider canLoadObjectOfClass:[UIImage class]] )
				{
					dispatch_group_enter( group );
					
					[itemProvider loadObjectOfClass:[UIImage class] completionHandler:^( __kindof id<NSItemProviderReading> object, NSError *error )
					{
						if( object != nil && [object isKindOfClass:[UIImage class]] )
						{
							resultPath = [[NSString stringWithFormat:@"%@%d", pickedMediaSavePath, j] stringByAppendingPathExtension:@"png"];
							if( ![self saveImageAsPNG:(UIImage *)object toPath:resultPath] )
							{
								NSLog( @"Error creating PNG image" );
								resultPath = nil;
							}
						}
						else
							NSLog( @"Error generating UIImage from picked live photo: %@", error );
						
						[arrayLock lock];
						[resultPaths addObject:( resultPath != nil ? resultPath : @"" )];
						[arrayLock unlock];
						
						dispatch_group_leave( group );
					}];
				}
				else if( [itemProvider canLoadObjectOfClass:[PHLivePhoto class]] )
				{
					dispatch_group_enter( group );
					
					[itemProvider loadObjectOfClass:[PHLivePhoto class] completionHandler:^( __kindof id<NSItemProviderReading> object, NSError *error )
					{
						if( object != nil && [object isKindOfClass:[PHLivePhoto class]] )
						{
							// Extract image data from live photo
							// Credit: https://stackoverflow.com/a/41341675/2373034
							NSArray<PHAssetResource*>* livePhotoResources = [PHAssetResource assetResourcesForLivePhoto:(PHLivePhoto *)object];
							
							PHAssetResource *livePhotoImage = nil;
							for( int k = 0; k < [livePhotoResources count]; k++ )
							{
								if( livePhotoResources[k].type == PHAssetResourceTypePhoto )
								{
									livePhotoImage = livePhotoResources[k];
									break;
								}
							}
							
							if( livePhotoImage == nil )
							{
								NSLog( @"Error extracting image data from live photo" );
							
								[arrayLock lock];
								[resultPaths addObject:@""];
								[arrayLock unlock];
							}
							else
							{
								dispatch_group_enter( group );
								
								NSString *originalFilename = livePhotoImage.originalFilename;
								if( originalFilename == nil || [originalFilename length] == 0 )
									resultPath = [NSString stringWithFormat:@"%@%d", pickedMediaSavePath, j];
								else
									resultPath = [[NSString stringWithFormat:@"%@%d", pickedMediaSavePath, j] stringByAppendingPathExtension:[originalFilename pathExtension]];
								
								[[PHAssetResourceManager defaultManager] writeDataForAssetResource:livePhotoImage toFile:[NSURL fileURLWithPath:resultPath] options:nil completionHandler:^( NSError * _Nullable error2 )
								{
									if( error2 != nil )
									{
										NSLog( @"Error saving image data from live photo: %@", error2 );
										resultPath = nil;
									}
									
									[arrayLock lock];
									[resultPaths addObject:( resultPath != nil ? resultPath : @"" )];
									[arrayLock unlock];
									
									dispatch_group_leave( group );
								}];
							}
						}
						else
						{
							NSLog( @"Error generating PHLivePhoto from picked live photo: %@", error );
						
							[arrayLock lock];
							[resultPaths addObject:@""];
							[arrayLock unlock];
						}
						
						dispatch_group_leave( group );
					}];
				}
				else
				{
					NSLog( @"Can't convert picked live photo to still image" );
					
					[arrayLock lock];
					[resultPaths addObject:@""];
					[arrayLock unlock];
				}
			}
			else if( [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie] || [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeVideo] )
			{
				NSLog( @"Picked a video" );
				
				// Get the video file's path
				dispatch_group_enter( group );
				
				[itemProvider loadFileRepresentationForTypeIdentifier:([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie] ? (NSString *)kUTTypeMovie : (NSString *)kUTTypeVideo) completionHandler:^( NSURL *url, NSError *error )
				{
					if( url != nil )
					{
						// Copy the video to a temporary location because the returned video will be deleted by the OS after this callback is completed
						resultPath = [url path];
						NSString *newPath = [[NSString stringWithFormat:@"%@%d", pickedMediaSavePath, j] stringByAppendingPathExtension:[resultPath pathExtension]];
						
						if( ![[NSFileManager defaultManager] fileExistsAtPath:newPath] || [[NSFileManager defaultManager] removeItemAtPath:newPath error:&error] )
						{
							if( [[NSFileManager defaultManager] copyItemAtPath:resultPath toPath:newPath error:&error])
								resultPath = newPath;
							else
							{
								NSLog( @"Error copying video: %@", error );
								resultPath = nil;
							}
						}
						else
						{
							NSLog( @"Error deleting existing video: %@", error );
							resultPath = nil;
						}
					}
					else
						NSLog( @"Error getting the picked video's path: %@", error );
					
					[arrayLock lock];
					[resultPaths addObject:( resultPath != nil ? resultPath : @"" )];
					[arrayLock unlock];
					
					dispatch_group_leave( group );
				}];
			}
			else
			{
				// Unknown media type picked?
				NSLog( @"Couldn't determine type of picked media: %@", itemProvider );
				
				[arrayLock lock];
				[resultPaths addObject:@""];
				[arrayLock unlock];
			}
		}
		
		dispatch_group_notify( group, dispatch_get_main_queue(),
		^{
            [self sendPathToUnity:resultPaths[0]];
		});
	}
	else
	{
		NSLog( @"No media picked" );
        [self sendPathToUnity:@""];
	}
}


+ (BOOL)saveImageAsPNG:(UIImage *)image toPath:(NSString *)resultPath
{
    return [UIImagePNGRepresentation( [self scaleImage:image maxSize:4096] ) writeToFile:resultPath atomically:YES];
}


// Credit: https://stackoverflow.com/a/4170099/2373034
+ (NSArray *)getImageMetadata:(NSString *)path
{
    int width       = 0;
    int height      = 0;
    int orientation = -1;
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL( (__bridge CFURLRef) [NSURL fileURLWithPath:path], nil );
    if( imageSource != nil )
    {
        NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:(__bridge NSString *)kCGImageSourceShouldCache];
        CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex( imageSource, 0, (__bridge CFDictionaryRef) options );
        CFRelease( imageSource );
        
        CGFloat widthF = 0.0f, heightF = 0.0f;
        if( imageProperties != nil )
        {
            if( CFDictionaryContainsKey( imageProperties, kCGImagePropertyPixelWidth ) )
                CFNumberGetValue( (CFNumberRef) CFDictionaryGetValue( imageProperties, kCGImagePropertyPixelWidth ), kCFNumberCGFloatType, &widthF );
            
            if( CFDictionaryContainsKey( imageProperties, kCGImagePropertyPixelHeight ) )
                CFNumberGetValue( (CFNumberRef) CFDictionaryGetValue( imageProperties, kCGImagePropertyPixelHeight ), kCFNumberCGFloatType, &heightF );
            
            if( CFDictionaryContainsKey( imageProperties, kCGImagePropertyOrientation ) )
            {
                CFNumberGetValue( (CFNumberRef) CFDictionaryGetValue( imageProperties, kCGImagePropertyOrientation ), kCFNumberIntType, &orientation );
                
                if( orientation > 4 )
                {
                    // Landscape image
                    CGFloat temp = widthF;
                    widthF = heightF;
                    heightF = temp;
                }
            }
            
            CFRelease( imageProperties );
        }
        
        width = (int) roundf( widthF );
        height = (int) roundf( heightF );
    }
    
    return [[NSArray alloc] initWithObjects:[NSNumber numberWithInt:width], [NSNumber numberWithInt:height], [NSNumber numberWithInt:orientation], nil];
}

+ (char *)loadImageAtPath:(NSString *)path tempFilePath:(NSString *)tempFilePath maximumSize:(int)maximumSize
{
    // Check if the image can be loaded by Unity without requiring a conversion to PNG
    // Credit: https://stackoverflow.com/a/12048937/2373034
    NSString *extension = [path pathExtension];
    BOOL conversionNeeded = [extension caseInsensitiveCompare:@"jpg"] != NSOrderedSame && [extension caseInsensitiveCompare:@"jpeg"] != NSOrderedSame && [extension caseInsensitiveCompare:@"png"] != NSOrderedSame;

    if( !conversionNeeded )
    {
        // Check if the image needs to be processed at all
        NSArray *metadata = [self getImageMetadata:path];
        int orientationInt = [metadata[2] intValue];  // 1: correct orientation, [1,8]: valid orientation range
        if( orientationInt == 1 && [metadata[0] intValue] <= maximumSize && [metadata[1] intValue] <= maximumSize )
            return [self getCString:path];
    }
    
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if( image == nil )
        return [self getCString:path];
    
    UIImage *scaledImage = [self scaleImage:image maxSize:maximumSize];
    if( conversionNeeded || scaledImage != image )
    {
        if( ![UIImagePNGRepresentation( scaledImage ) writeToFile:tempFilePath atomically:YES] )
        {
            NSLog( @"Error creating scaled image" );
            return [self getCString:path];
        }
        
        return [self getCString:tempFilePath];
    }
    else
        return [self getCString:path];
}

+ (UIImage *)scaleImage:(UIImage *)image maxSize:(int)maxSize
{
    CGFloat width = image.size.width;
    CGFloat height = image.size.height;
    
    UIImageOrientation orientation = image.imageOrientation;
    if( width <= maxSize && height <= maxSize && orientation != UIImageOrientationDown &&
        orientation != UIImageOrientationLeft && orientation != UIImageOrientationRight &&
        orientation != UIImageOrientationLeftMirrored && orientation != UIImageOrientationRightMirrored &&
        orientation != UIImageOrientationUpMirrored && orientation != UIImageOrientationDownMirrored )
        return image;
    
    CGFloat scaleX = 1.0f;
    CGFloat scaleY = 1.0f;
    if( width > maxSize )
        scaleX = maxSize / width;
    if( height > maxSize )
        scaleY = maxSize / height;
    
    // Credit: https://github.com/mbcharbonneau/UIImage-Categories/blob/master/UIImage%2BAlpha.m
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo( image.CGImage );
    BOOL hasAlpha = alpha == kCGImageAlphaFirst || alpha == kCGImageAlphaLast || alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaPremultipliedLast;
    
    CGFloat scaleRatio = scaleX < scaleY ? scaleX : scaleY;
    CGRect imageRect = CGRectMake( 0, 0, width * scaleRatio, height * scaleRatio );
    
    // Resize image with UIGraphicsImageRenderer (Apple's recommended API) if possible
    UIGraphicsImageRendererFormat *format = [image imageRendererFormat];
    format.opaque = !hasAlpha;
    format.scale  = image.scale;
   
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:imageRect.size format:format];
    image = [renderer imageWithActions:^( UIGraphicsImageRendererContext* _Nonnull myContext )
    {
        [image drawInRect:imageRect];
    }];
    
    return image;
}

// Credit: https://stackoverflow.com/a/37052118/2373034
+ (char *)getCString:(NSString *)source
{
    if( source == nil )
        source = @"";
    
    const char *sourceUTF8 = [source UTF8String];
    char *result = (char*) malloc( strlen( sourceUTF8 ) + 1 );
    strcpy( result, sourceUTF8 );
    
    return result;
}



@end


extern "C" void _MobileImagePicker_PickMedia( const char* mediaSavePath, int selectImages, int selectVideos, DelegateCallbackFunction callback )
{
    [MobileImagePicker pickMedia:[NSString stringWithUTF8String:mediaSavePath] selectImages:( selectImages == 1 ) selectVideos:(selectVideos == 1) callback:callback];
}
