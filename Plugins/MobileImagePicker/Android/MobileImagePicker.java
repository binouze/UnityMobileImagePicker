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
        // Credit: https://developer.android.com/training/secure-file-sharing/retrieve-info.html#RetrieveFileInfo
        ContentResolver resolver = context.getContentResolver();
        //Cursor returnCursor      = null;
        String filename          = "temp";
        /*long fileSize = -1, copiedBytes = 0;*/

        /*try
        {
            returnCursor = resolver.query( uri, null, null, null, null );
            if( returnCursor != null && returnCursor.moveToFirst() )
            {
                int displayName = returnCursor.getColumnIndex( OpenableColumns.DISPLAY_NAME );
                int size        = returnCursor.getColumnIndex( OpenableColumns.SIZE );
                if( displayName >= 0 && size >= 0 )
                {
                    //filename = returnCursor.getString( displayName );
                    //fileSize = returnCursor.getLong( size );

                    String fname = returnCursor.getString( displayName );
                    Log.d( "Unity", "fname: "+fname );
                }

            }
        }
        catch( Exception e )
        {
            Log.e( "Unity", "Exception:", e );
        }
        finally
        {
            if( returnCursor != null )
                returnCursor.close();
        }

        if( filename == null || filename.length() < 3 )
            filename = "temp";*/

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
}