# UnityMobileMediaPicker

Unity plugin to select media content from gallery on iOS and Android.

 - MobileMediaPicker on Android uses  [Android PhotoPicker API](https://developer.android.com/training/data-storage/shared/photopicker#java).
 - MobileMediaPicker on iOS uses a big part of: [https://github.com/yasirkula/UnityNativeGallery](https://github.com/yasirkula/UnityNativeGallery).

## PACKAGE INSTALLATION:

- in the package manager, click on the + 
- select `add package from GIT url`
- paste the following url: `"https://github.com/binouze/UnityMobileMediaPicker.git"`


## USAGE

```csharp

// pick an image
MobileMediaPicker.PickImage( path =>
{
    if( !string.IsNullOrEmpty(path) )
    {
      // do what you want with the image path
    }
} );

// pick an video
MobileMediaPicker.PickVideo( path =>
{
    if( !string.IsNullOrEmpty(path) )
    {
      // do what you want with the video path
    }
} );

// pick any media
MobileMediaPicker.Pick( path =>
{
    if( !string.IsNullOrEmpty(path) )
    {
      // do what you want with the image or video path
    }
} );

```
