// Credit: https://github.com/yasirkula/UnityNativeGallery/blob/master/Plugins/NativeGallery/iOS/NativeGallery.mm

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <ImageIO/ImageIO.h>
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 80000
#import <AssetsLibrary/AssetsLibrary.h>
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
#import <PhotosUI/PhotosUI.h>
#endif

#ifdef UNITY_4_0 || UNITY_5_0
#import "iPhone_View.h"
#else
extern UIViewController* UnityGetGLViewController();
#endif


#define CHECK_IOS_VERSION( version )  ([[[UIDevice currentDevice] systemVersion] compare:version options:NSNumericSearch] != NSOrderedAscending)


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

@interface MobileMediaPicker:NSObject<MediaPickedDelegate>
+ (void)pickMedia:(NSString *)mediaSavePath selectImages:(BOOL)selectImages selectVideos:(BOOL)selectVideos callback:(DelegateCallbackFunction)callback;
+ (void)setCallback:(DelegateCallbackFunction)delegate;
@end


@implementation MobileMediaPicker

static MobileMediaPicker        *__MMPDelegate = nil;
static DelegateCallbackFunction _MMPCallback   = nil;

+(void)setCallback:(DelegateCallbackFunction)delegate
{
    if( !__MMPDelegate ){
        __MMPDelegate = [[MobileMediaPicker alloc] init];
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
    [MediaPickedClass sendPathToDelegate:[self getCString:path]];
}


static NSString                 *pickedMediaSavePath;
static int                      imagePickerState;
static BOOL                     simpleMediaPickMode;
static BOOL                     pickingMultipleFiles;
static UIPopoverController      *popup;
static UIImagePickerController  *imagePicker;
API_AVAILABLE(ios(14))
static PHPickerViewController   *imagePickerNew;

// Credit: https://stackoverflow.com/a/10531752/2373034
+ (void)pickMedia:(NSString *)mediaSavePath selectImages:(BOOL)selectImages selectVideos:(BOOL)selectVideos callback:(DelegateCallbackFunction)callback
{
    [self setCallback:callback];
    
	pickedMediaSavePath  = mediaSavePath;
    imagePickerState     = 1;
    pickingMultipleFiles = false;
    
    if( @available(iOS 11, *) ){
        simpleMediaPickMode = true;
    }
    else{
        simpleMediaPickMode = false;
    }
    
	
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
    if( @available(iOS 14, *) )
	{
		// PHPickerViewController is used on iOS 14
		PHPickerConfiguration *config = simpleMediaPickMode ? [[PHPickerConfiguration alloc] init] : [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
		config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
		config.selectionLimit = 1;
		
		// selection filter
		if( selectImages && !selectVideos )
			config.filter = [PHPickerFilter anyFilterMatchingSubfilters:[NSArray arrayWithObjects:[PHPickerFilter imagesFilter], [PHPickerFilter livePhotosFilter], nil]];
		else if( selectVideos && !selectImages )
			config.filter = [PHPickerFilter videosFilter];
		else
			config.filter = [PHPickerFilter anyFilterMatchingSubfilters:[NSArray arrayWithObjects:[PHPickerFilter imagesFilter], [PHPickerFilter livePhotosFilter], [PHPickerFilter videosFilter], nil]];

		
        imagePickerNew = [[PHPickerViewController alloc] initWithConfiguration:config];
		imagePickerNew.delegate = (id)self;
		[UnityGetGLViewController() presentViewController:imagePickerNew animated:YES completion:^{ imagePickerState = 0; }];
	}
	else
#endif
	{
		// UIImagePickerController is used on previous versions
        imagePicker = [[UIImagePickerController alloc] init];
		imagePicker.delegate = (id) self;
		imagePicker.allowsEditing = NO;
		imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
		
		// selection filter
		if( selectImages && !selectVideos )
		{
			if( @available(iOS 9.1, *) )
				imagePicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeLivePhoto, nil];
			else
				imagePicker.mediaTypes = [NSArray arrayWithObject:(NSString *)kUTTypeImage];
		}
		else if( selectVideos && !selectImages )
        {
            imagePicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeMovie, (NSString *)kUTTypeVideo, nil];
        }
		else
		{
			if( @available(iOS 9.1, *) )
				imagePicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeLivePhoto, (NSString *)kUTTypeMovie, (NSString *)kUTTypeVideo, nil];
			else
				imagePicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, (NSString *)kUTTypeVideo, nil];
		}
		
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
		if( selectVideos )
		{
			// Don't compress picked videos if possible
			if( @available(iOS 11, *) )
				imagePicker.videoExportPreset = AVAssetExportPresetPassthrough;
		}
#endif
		
		UIViewController *rootViewController = UnityGetGLViewController();
		// iPhone
		if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone ) 
        {
            [rootViewController presentViewController:imagePicker animated:YES completion:^{ imagePickerState = 0; }];
        }
        // iPad
		else
		{
            popup = [[UIPopoverController alloc] initWithContentViewController:imagePicker];
			popup.delegate = (id) self;
			[popup presentPopoverFromRect:CGRectMake( rootViewController.view.frame.size.width / 2, rootViewController.view.frame.size.height / 2, 1, 1 ) inView:rootViewController.view permittedArrowDirections:0 animated:YES];
		}
	}
}











+ (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	NSString *resultPath = nil;
	
	if( [info[UIImagePickerControllerMediaType] isEqualToString:(NSString *)kUTTypeImage] )
	{
		NSLog( @"UIImagePickerController Picked an image" );
		
		// On iOS 8.0 or later, try to obtain the raw data of the image (which allows picking gifs properly or preserving metadata)
		if( @available(iOS 8, *) )
		{
			PHAsset *asset = nil;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
			if( @available(iOS 11, *) )
			{
				// Try fetching the source image via UIImagePickerControllerImageURL
				NSURL *mediaUrl = info[UIImagePickerControllerImageURL];
				if( mediaUrl != nil )
				{
					NSString *imagePath = [mediaUrl path];
					if( imagePath != nil && [[NSFileManager defaultManager] fileExistsAtPath:imagePath] )
					{
						NSError *error;
						NSString *newPath = [pickedMediaSavePath stringByAppendingPathExtension:[imagePath pathExtension]];
						
						if( ![[NSFileManager defaultManager] fileExistsAtPath:newPath] || [[NSFileManager defaultManager] removeItemAtPath:newPath error:&error] )
						{
							if( [[NSFileManager defaultManager] copyItemAtPath:imagePath toPath:newPath error:&error] )
							{
								resultPath = newPath;
								NSLog( @"Copied source image from UIImagePickerControllerImageURL" );
							}
							else
								NSLog( @"Error copying image: %@", error );
						}
						else
							NSLog( @"Error deleting existing image: %@", error );
					}
				}
				
				if( resultPath == nil )
					asset = info[UIImagePickerControllerPHAsset];
			}
#endif
			
			if( resultPath == nil && !simpleMediaPickMode )
			{
				if( asset == nil )
				{
					NSURL *mediaUrl = info[UIImagePickerControllerReferenceURL] ?: info[UIImagePickerControllerMediaURL];
					if( mediaUrl != nil )
						asset = [[PHAsset fetchAssetsWithALAssetURLs:[NSArray arrayWithObject:mediaUrl] options:nil] firstObject];
				}
				
				resultPath = [self trySavePHAsset:asset atIndex:1];
			}
		}
		
		if( resultPath == nil )
		{
			// Save image as PNG
			UIImage *image = info[UIImagePickerControllerOriginalImage];
			if( image != nil )
			{
				resultPath = [pickedMediaSavePath stringByAppendingPathExtension:@"png"];
				if( ![self saveImageAsPNG:image toPath:resultPath] )
				{
					NSLog( @"Error creating PNG image" );
					resultPath = nil;
				}
			}
			else
				NSLog( @"Error fetching original image from picker" );
		}
	}
	else if( CHECK_IOS_VERSION( @"9.1" ) && [info[UIImagePickerControllerMediaType] isEqualToString:(NSString *)kUTTypeLivePhoto] )
	{
		NSLog( @"Picked a live photo" );
		
		// Save live photo as PNG
		UIImage *image = info[UIImagePickerControllerOriginalImage];
		if( image != nil )
		{
			resultPath = [pickedMediaSavePath stringByAppendingPathExtension:@"png"];
			if( ![self saveImageAsPNG:image toPath:resultPath] )
			{
				NSLog( @"Error creating PNG image" );
				resultPath = nil;
			}
		}
		else
			NSLog( @"Error fetching live photo's still image from picker" );
	}
	else
	{
		NSLog( @"Picked a video" );
		
		NSURL *mediaUrl = info[UIImagePickerControllerMediaURL] ?: info[UIImagePickerControllerReferenceURL];
		if( mediaUrl != nil )
		{
			resultPath = [mediaUrl path];
			
			// On iOS 13, picked file becomes unreachable as soon as the UIImagePickerController disappears,
			// in that case, copy the video to a temporary location
			if( CHECK_IOS_VERSION( @"13.0" ) )
			{
				NSError *error;
				NSString *newPath = [pickedMediaSavePath stringByAppendingPathExtension:[resultPath pathExtension]];
				
				if( ![[NSFileManager defaultManager] fileExistsAtPath:newPath] || [[NSFileManager defaultManager] removeItemAtPath:newPath error:&error] )
				{
					if( [[NSFileManager defaultManager] copyItemAtPath:resultPath toPath:newPath error:&error] )
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
		}
	}
	
	popup = nil;
	imagePicker = nil;
	imagePickerState = 2;
    
    [self sendPathToUnity:resultPath];
    
	//UnitySendMessage( "NGMediaReceiveCallbackiOS", "OnMediaReceived", [self getCString:resultPath] );
	
	[picker dismissViewControllerAnimated:NO completion:nil];
}
#pragma clang diagnostic pop

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
// Credit: https://ikyle.me/blog/2020/phpickerviewcontroller
+(void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
API_AVAILABLE(ios(14)){
	imagePickerNew = nil;
	imagePickerState = 2;
	
	[picker dismissViewControllerAnimated:NO completion:nil];
	
	if( results != nil && [results count] > 0 )
	{
		NSMutableArray<NSString *> *resultPaths = [NSMutableArray arrayWithCapacity:[results count]];
		NSLock *arrayLock = [[NSLock alloc] init];
		dispatch_group_t group = dispatch_group_create();
		
		for( int i = 0; i < [results count]; i++ )
		{
			PHPickerResult *result = results[i];
			NSItemProvider *itemProvider = result.itemProvider;
			NSString *assetIdentifier = result.assetIdentifier;
			__block NSString *resultPath = nil;
			
			int j = i + 1;
			
			//NSLog( @"result: %@", result );
			//NSLog( @"%@", result.assetIdentifier);
			//NSLog( @"%@", result.itemProvider);

			if( [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeImage] )
			{
				NSLog( @"PHPickerViewController Picked an image" );
				
				if( !simpleMediaPickMode && assetIdentifier != nil )
				{
					PHAsset *asset = [[PHAsset fetchAssetsWithLocalIdentifiers:[NSArray arrayWithObject:assetIdentifier] options:nil] firstObject];
					resultPath = [self trySavePHAsset:asset atIndex:j];
				}
				
				if( resultPath != nil )
				{
					[arrayLock lock];
					[resultPaths addObject:resultPath];
					[arrayLock unlock];
				}
				else
				{
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
			}
			else if( CHECK_IOS_VERSION( @"9.1" ) && [itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeLivePhoto] )
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
            
			/*if( !pickingMultipleFiles )
				UnitySendMessage( "NGMediaReceiveCallbackiOS", "OnMediaReceived", [self getCString:resultPaths[0]] );
			else
				UnitySendMessage( "NGMediaReceiveCallbackiOS", "OnMultipleMediaReceived", [self getCString:[resultPaths componentsJoinedByString:@">"]] );*/
		});
	}
	else
	{
		NSLog( @"No media picked" );
		
        [self sendPathToUnity:@""];
        
		/*if( !pickingMultipleFiles )
			UnitySendMessage( "NGMediaReceiveCallbackiOS", "OnMediaReceived", "" );
		else
			UnitySendMessage( "NGMediaReceiveCallbackiOS", "OnMultipleMediaReceived", "" );*/
	}
}
#endif


+ (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
	NSLog( @"UIImagePickerController cancelled" );

	popup = nil;
	imagePicker = nil;
    [self sendPathToUnity:@""];
	//UnitySendMessage( "NGMediaReceiveCallbackiOS", "OnMediaReceived", "" );
	
	[picker dismissViewControllerAnimated:NO completion:nil];
}

+ (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
	NSLog( @"UIPopoverController dismissed" );

	popup = nil;
	imagePicker = nil;
    
    [self sendPathToUnity:@""];
	//UnitySendMessage( "NGMediaReceiveCallbackiOS", "OnMediaReceived", "" );
}


+ (NSString *)trySavePHAsset:(PHAsset *)asset atIndex:(int)filenameIndex
{
    if( asset == nil )
        return nil;
    
    __block NSString *resultPath = nil;
    
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.synchronous = YES;
    options.version = PHImageRequestOptionsVersionCurrent;
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if( CHECK_IOS_VERSION( @"13.0" ) )
    {
        [[PHImageManager defaultManager] requestImageDataAndOrientationForAsset:asset options:options resultHandler:^( NSData *imageData, NSString *dataUTI, CGImagePropertyOrientation orientation, NSDictionary *imageInfo )
        {
            if( imageData != nil )
                resultPath = [self trySaveSourceImage:imageData withInfo:imageInfo atIndex:filenameIndex];
            else
                NSLog( @"Couldn't fetch raw image data" );
        }];
    }
    else
#endif
    {
        [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^( NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *imageInfo )
        {
            if( imageData != nil )
                resultPath = [self trySaveSourceImage:imageData withInfo:imageInfo atIndex:filenameIndex];
            else
                NSLog( @"Couldn't fetch raw image data" );
        }];
    }
    
    return resultPath;
}


+ (NSString *)trySaveSourceImage:(NSData *)imageData withInfo:(NSDictionary *)info atIndex:(int)filenameIndex
{
    NSString *filePath = info[@"PHImageFileURLKey"];
    if( filePath != nil ) // filePath can actually be an NSURL, convert it to NSString
        filePath = [NSString stringWithFormat:@"%@", filePath];
    
    if( filePath == nil || [filePath length] == 0 )
    {
        filePath = info[@"PHImageFileUTIKey"];
        if( filePath != nil )
            filePath = [NSString stringWithFormat:@"%@", filePath];
    }
    
    NSString *resultPath;
    if( filePath == nil || [filePath length] == 0 )
        resultPath = [NSString stringWithFormat:@"%@%d", pickedMediaSavePath, filenameIndex];
    else
        resultPath = [[NSString stringWithFormat:@"%@%d", pickedMediaSavePath, filenameIndex] stringByAppendingPathExtension:[filePath pathExtension]];
    
    NSError *error;
    if( ![[NSFileManager defaultManager] fileExistsAtPath:resultPath] || [[NSFileManager defaultManager] removeItemAtPath:resultPath error:&error] )
    {
        if( ![imageData writeToFile:resultPath atomically:YES] )
        {
            NSLog( @"Error copying source image to file" );
            resultPath = nil;
        }
    }
    else
    {
        NSLog( @"Error deleting existing image: %@", error );
        resultPath = nil;
    }
    
    return resultPath;
}

+ (BOOL)saveImageAsPNG:(UIImage *)image toPath:(NSString *)resultPath
{
    return [UIImagePNGRepresentation( [self scaleImage:image maxSize:16384] ) writeToFile:resultPath atomically:YES];
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
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 100000
    // Resize image with UIGraphicsImageRenderer (Apple's recommended API) if possible
    if( CHECK_IOS_VERSION( @"10.0" ) )
    {
        UIGraphicsImageRendererFormat *format = [image imageRendererFormat];
        format.opaque = !hasAlpha;
        format.scale = image.scale;
       
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:imageRect.size format:format];
        image = [renderer imageWithActions:^( UIGraphicsImageRendererContext* _Nonnull myContext )
        {
            [image drawInRect:imageRect];
        }];
    }
    else
    #endif
    {
        UIGraphicsBeginImageContextWithOptions( imageRect.size, !hasAlpha, image.scale );
        [image drawInRect:imageRect];
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
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


extern "C" void _MobileMediaPicker_PickMedia( const char* mediaSavePath, int selectImages, int selectVideos, DelegateCallbackFunction callback )
{
    [MobileMediaPicker pickMedia:[NSString stringWithUTF8String:mediaSavePath] selectImages:( selectImages == 1 ) selectVideos:(selectVideos == 1) callback:callback];
}
