# UnityMobileImagePicker

Unity plugin to select an image from gallery on iOS and Android.

 - MobileImagePicker on Android uses  [Android PhotoPicker API](https://developer.android.com/training/data-storage/shared/photopicker#java).
 - MobileImagePicker on iOS uses a big part of: [https://github.com/yasirkula/UnityNativeGallery](https://github.com/yasirkula/UnityNativeGallery).
 - iOS minimum version is 14.

## PACKAGE INSTALLATION:

- in the package manager, click on the + 
- select `add package from GIT url`
- paste the following url: `"https://github.com/binouze/UnityMobileImagePicker.git"`


## USAGE

```csharp

// pick an image
MobileImagePicker.PickImage( path =>
{
    if( !string.IsNullOrEmpty(path) )
    {
      // do what you want with the image path
    }
} );

```
