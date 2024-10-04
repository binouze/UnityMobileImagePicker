package com.binouze;

// implementation pour le Android PhotoPicker: 
// https://developer.android.com/training/data-storage/shared/photopicker#java
// ajouter <activity android:name="com.binouze.NativeMediaPicker" android:exported="true" android:theme="@style/Theme.AppCompat.Translucent" />
// dans le AndroidManifest.xml

// il faut également ajouter les lignes uisvantes pour la rétrocompatibilité
//
//<!-- Trigger Google Play services to install the backported photo picker module. -->
//<service android:name="com.google.android.gms.metadata.ModuleDependencies"
//         android:enabled="false"
//         android:exported="false"
//         tools:ignore="MissingClass">
//    <intent-filter>
//        <action android:name="com.google.android.gms.metadata.MODULE_DEPENDENCIES" />
//    </intent-filter>
//    <meta-data android:name="photopicker_activity:0:required" android:value="" />
//</service>

import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.provider.MediaStore;
import android.webkit.MimeTypeMap;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.PickVisualMediaRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;

import com.unity3d.player.UnityPlayer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Objects;

public class MobileImagePicker extends AppCompatActivity
{
    private static final String TAG = "MobileImagePicker";

    // Registers a photo picker activity launcher in single-select mode.
    ActivityResultLauncher<PickVisualMediaRequest> pickMedia =
            registerForActivityResult(new ActivityResultContracts.PickVisualMedia(), uri ->
            {
                String path;
                // Callback is invoked after the user selects a media item or closes the
                // photo picker.
                if( uri != null )
                {
                    Log.d(TAG, "Selected URI: " + uri);
                    path = copyToTempFile(this,uri);
                    Log.d(TAG, "Selected PATH: " + path);
                }
                else
                {
                    Log.d(TAG, "No media selected");
                    path = "";
                }

                // re-open unityplayer activity
                Intent intent = new Intent(this, UnityPlayer.currentActivity.getClass());
                startActivity( intent );

                // send message to unity
                if( _pickerCallback != null )
                {
                    _pickerCallback.onUrlPicked(path);
                    _pickerCallback = null;
                }
            });

    @Override
    protected void onCreate( Bundle savedInstanceState )
    {
        super.onCreate(savedInstanceState);

        Intent intent        = getIntent();
        boolean selectImages = intent.getBooleanExtra("selectImages", false);
        boolean selectVideos = intent.getBooleanExtra("selectVideos", false);

        ActivityResultContracts.PickVisualMedia.VisualMediaType mediaType;
        if( selectImages && !selectVideos )
            mediaType = ActivityResultContracts.PickVisualMedia.ImageOnly.INSTANCE;
        else if( selectVideos && !selectImages )
            mediaType = ActivityResultContracts.PickVisualMedia.VideoOnly.INSTANCE;
        else
            mediaType = ActivityResultContracts.PickVisualMedia.ImageAndVideo.INSTANCE;

        // Launch the photo picker and let the user choose only images.
        pickMedia.launch(new PickVisualMediaRequest.Builder()
                .setMediaType(mediaType)
                .build());
    }

    private static ImagePickerCallback _pickerCallback;
    private static String  _tempPathDirectory;

    public static void PickMedia(final ImagePickerCallback callback, String tempPathDirectory, boolean selectImages, boolean selectVideos)
    {
        _pickerCallback    = callback;
        _tempPathDirectory = tempPathDirectory;

        Intent myIntent = new Intent(UnityPlayer.currentActivity, MobileImagePicker.class);
        myIntent.putExtra("selectImages", selectImages);
        myIntent.putExtra("selectVideos", selectVideos);
        UnityPlayer.currentActivity.startActivity(myIntent);
    }







    private static String copyToTempFile( Context context, Uri uri )
    {
        String path    = uri.toString();
        String newPath = EnsureImageCompatibility(context,path,_tempPathDirectory,4096);
        if( !Objects.equals(newPath, path) )
            return newPath;

        // Credit: https://developer.android.com/training/secure-file-sharing/retrieve-info.html#RetrieveFileInfo
        ContentResolver resolver = context.getContentResolver();
        String filename          = "temp";

        // try get extension
        String extension = null;
        String mime      = resolver.getType( uri );
        if( mime != null )
        {
            String mimeExtension = MimeTypeMap.getSingleton().getExtensionFromMimeType( mime );
            if( mimeExtension != null && !mimeExtension.isEmpty() )
                extension = "." + mimeExtension;
        }

        if( extension == null )
            extension = ".tmp";

        try
        {
            InputStream input = resolver.openInputStream( uri );
            if( input == null )
            {
                Log.w( TAG, "Couldn't open input stream: " + uri );
                return null;
            }


            OutputStream output = null;
            try
            {
                // create temp file
                String fullName = filename + extension;
                File tempFile   = new File( _tempPathDirectory, fullName );
                //noinspection ResultOfMethodCallIgnored
                Objects.requireNonNull(tempFile.getParentFile()).mkdirs();
                //noinspection ResultOfMethodCallIgnored
                tempFile.createNewFile();

                // copy selected file to temp file
                output = new FileOutputStream( tempFile, false );

                byte[] buf = new byte[4096];
                int len;
                while( ( len = input.read( buf ) ) > 0 )
                {
                    output.write( buf, 0, len );
                }

                Log.d( TAG, "Copied media from " + uri + " to: " + tempFile.getAbsolutePath() );
                return tempFile.getAbsolutePath();
            }
            catch( Exception e )
            {
                Log.e( TAG, "Exception:", e );
            }
            finally
            {
                if( output != null )
                    output.close();

                input.close();
            }
        }
        catch( Exception e )
        {
            Log.e( TAG, "Exception:", e );
        }

        return null;
    }




    private static BitmapFactory.Options GetImageMetadata(final String path )
    {
        try
        {
            BitmapFactory.Options result = new BitmapFactory.Options();
            result.inJustDecodeBounds = true;
            BitmapFactory.decodeFile( path, result );

            return result;
        }
        catch( Exception e )
        {
            Log.e( TAG, "Exception:", e );
            return null;
        }
    }
    // Credit: https://stackoverflow.com/a/30572852/2373034
    public static int GetImageOrientation( Context context, final String path )
    {
        try
        {
            ExifInterface exif = new ExifInterface( path );
            int orientationEXIF = exif.getAttributeInt( ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED );
            if( orientationEXIF != ExifInterface.ORIENTATION_UNDEFINED )
                return orientationEXIF;
        }
        catch( Exception e )
        {
        }

        Cursor cursor = null;
        try
        {
            cursor = context.getContentResolver().query( Uri.fromFile( new File( path ) ), new String[] { MediaStore.Images.Media.ORIENTATION }, null, null, null );
            if( cursor != null && cursor.moveToFirst() )
            {
                int or = cursor.getColumnIndex( MediaStore.Images.Media.ORIENTATION );
                if( or >= 0 )
                {
                    int orientation = cursor.getInt( or );
                    if( orientation == 90 )
                        return ExifInterface.ORIENTATION_ROTATE_90;
                    if( orientation == 180 )
                        return ExifInterface.ORIENTATION_ROTATE_180;
                    if( orientation == 270 )
                        return ExifInterface.ORIENTATION_ROTATE_270;
                }

                return ExifInterface.ORIENTATION_NORMAL;
            }
        }
        catch( Exception e )
        {
            // nothing to do here
        }
        finally
        {
            if( cursor != null )
                cursor.close();
        }

        return ExifInterface.ORIENTATION_UNDEFINED;
    }

    // Credit: https://gist.github.com/aviadmini/4be34097dfdb842ae066fae48501ed41
    private static Matrix GetImageOrientationCorrectionMatrix( final int orientation, final float scale )
    {
        Matrix matrix = new Matrix();

        switch( orientation )
        {
            case ExifInterface.ORIENTATION_ROTATE_270:
            {
                matrix.postRotate( 270 );
                matrix.postScale( scale, scale );

                break;
            }
            case ExifInterface.ORIENTATION_ROTATE_180:
            {
                matrix.postRotate( 180 );
                matrix.postScale( scale, scale );

                break;
            }
            case ExifInterface.ORIENTATION_ROTATE_90:
            {
                matrix.postRotate( 90 );
                matrix.postScale( scale, scale );

                break;
            }
            case ExifInterface.ORIENTATION_FLIP_HORIZONTAL:
            {
                matrix.postScale( -scale, scale );
                break;
            }
            case ExifInterface.ORIENTATION_FLIP_VERTICAL:
            {
                matrix.postScale( scale, -scale );
                break;
            }
            case ExifInterface.ORIENTATION_TRANSPOSE:
            {
                matrix.postRotate( 90 );
                matrix.postScale( -scale, scale );

                break;
            }
            case ExifInterface.ORIENTATION_TRANSVERSE:
            {
                matrix.postRotate( 270 );
                matrix.postScale( -scale, scale );

                break;
            }
            default:
            {
                matrix.postScale( scale, scale );
                break;
            }
        }

        return matrix;
    }

    public static String EnsureImageCompatibility( Context context, String path, final String temporaryFilePath, final int maxSize )
    {
        BitmapFactory.Options metadata = GetImageMetadata( path );
        if( metadata == null )
            return path;

        boolean shouldCreateNewBitmap = false;
        if( metadata.outWidth > maxSize || metadata.outHeight > maxSize )
            shouldCreateNewBitmap = true;

        if( metadata.outMimeType != null && !metadata.outMimeType.equals( "image/jpeg" ) && !metadata.outMimeType.equals( "image/png" ) )
            shouldCreateNewBitmap = true;

        int orientation = GetImageOrientation( context, path );
        if( orientation != ExifInterface.ORIENTATION_NORMAL && orientation != ExifInterface.ORIENTATION_UNDEFINED )
            shouldCreateNewBitmap = true;

        if( shouldCreateNewBitmap )
        {
            Bitmap bitmap = null;
            FileOutputStream out = null;

            try
            {
                // Credit: https://developer.android.com/topic/performance/graphics/load-bitmap.html
                int sampleSize = 1;
                int halfHeight = metadata.outHeight / 2;
                int halfWidth = metadata.outWidth / 2;
                while( ( halfHeight / sampleSize ) >= maxSize || ( halfWidth / sampleSize ) >= maxSize )
                    sampleSize *= 2;

                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inSampleSize = sampleSize;
                options.inJustDecodeBounds = false;
                bitmap = BitmapFactory.decodeFile( path, options );

                float scaleX = 1f, scaleY = 1f;
                if( bitmap.getWidth() > maxSize )
                    scaleX = maxSize / (float) bitmap.getWidth();
                if( bitmap.getHeight() > maxSize )
                    scaleY = maxSize / (float) bitmap.getHeight();

                // Create a new bitmap if it should be scaled down or if its orientation is wrong
                float scale = Math.min(scaleX, scaleY);
                if( scale < 1f || ( orientation != ExifInterface.ORIENTATION_NORMAL && orientation != ExifInterface.ORIENTATION_UNDEFINED ) )
                {
                    Matrix transformationMatrix = GetImageOrientationCorrectionMatrix( orientation, scale );
                    Bitmap transformedBitmap = Bitmap.createBitmap( bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), transformationMatrix, true );
                    if( transformedBitmap != bitmap )
                    {
                        bitmap.recycle();
                        bitmap = transformedBitmap;
                    }
                }

                out = new FileOutputStream( temporaryFilePath );
                if( metadata.outMimeType == null || !metadata.outMimeType.equals( "image/jpeg" ) )
                    bitmap.compress( Bitmap.CompressFormat.PNG, 100, out );
                else
                    bitmap.compress( Bitmap.CompressFormat.JPEG, 100, out );

                path = temporaryFilePath;
            }
            catch( Exception e )
            {
                Log.e( TAG, "Exception:", e );

                try
                {
                    File temporaryFile = new File( temporaryFilePath );
                    if( temporaryFile.exists() )
                        temporaryFile.delete();
                }
                catch( Exception e2 )
                {
                }
            }
            finally
            {
                if( bitmap != null )
                    bitmap.recycle();

                try
                {
                    if( out != null )
                        out.close();
                }
                catch( Exception e )
                {
                }
            }
        }

        return path;
    }
}