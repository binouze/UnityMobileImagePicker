//#undef UNITY_EDITOR

using System;
using System.Collections.Generic;
using JetBrains.Annotations;
using UnityEngine;

#if !UNITY_EDITOR
using System.IO;
#endif

#if !UNITY_EDITOR && UNITY_IOS
using AOT;
#endif

namespace com.binouze
{
    #if !UNITY_EDITOR && UNITY_ANDROID
    public class MediaPickerCallback : AndroidJavaProxy
    {
        private readonly MobileMediaPicker.UrlPickedCallback Callback;

        public MediaPickerCallback( MobileMediaPicker.UrlPickedCallback callback ) : base(
            "com.binouze.MediaPickerCallback" )
        {
            Callback = callback;
        }
        
        [UsedImplicitly]
        public void onUrlPicked(string url)
        {
            Debug.Log( $"onUrlPicked {url}" );
            MobileMediaPicker.CallOnMainThread( () => Callback?.Invoke( url ) );
        }
    }
    #endif

    public enum MediaType
    {
        Image = 1,
        Video = 2,
        Any   = 3
    }
    
    public class MobileMediaPicker : MonoBehaviour
    {
        public delegate void UrlPickedCallback( string path );

        /// <summary>
        /// pick unique image in the gallery
        /// </summary>
        /// <param name="callback"></param>
        [UsedImplicitly]
        public static void PickImage( UrlPickedCallback callback )
        {
            PickMedia(callback, MediaType.Image);
        }
        
        /// <summary>
        /// pick unique video in the gallery
        /// </summary>
        /// <param name="callback"></param>
        [UsedImplicitly]
        public static void PickVideo( UrlPickedCallback callback )
        {
            PickMedia(callback, MediaType.Video);
        }
        
        /// <summary>
        /// pick unique video or image in the gallery
        /// </summary>
        /// <param name="callback"></param>
        [UsedImplicitly]
        public static void Pick( UrlPickedCallback callback )
        {
            PickMedia(callback, MediaType.Any);
        }
        
        
        private static void PickMedia( UrlPickedCallback callback, MediaType mediaType )
        {
            Init();
            
            #if UNITY_EDITOR
            PickMediaEditor( callback, mediaType );
            #elif UNITY_ANDROID
            PickMediaAndroid( callback, mediaType );
            #elif UNITY_IOS
            PickMediaIOS( callback, mediaType );
            #else
            Debug.LogError( "MobileMediaPicker.PickMedia: Unsupported Platform" );
            callback?.Invoke(null)
            #endif
        }
        
        // EDITOR
        
        #if UNITY_EDITOR
        private static void PickMediaEditor( UrlPickedCallback callback, MediaType mediaType )
        {
            var editorFilters = new List<string>(2);

            if( mediaType is MediaType.Image or MediaType.Any )
            {
                editorFilters.Add( "Image files" );
                editorFilters.Add( "png,jpg,jpeg" );
            }

            if( mediaType is MediaType.Video or MediaType.Any )
            {
                editorFilters.Add( "Video files" );
                editorFilters.Add( "mp4,mov,webm,avi" );
            }

            var pickedFile = UnityEditor.EditorUtility.OpenFilePanelWithFilters( "Select file", "", editorFilters.ToArray() );

            callback?.Invoke( pickedFile != "" ? pickedFile : null );
        }
        #endif
        
        
        #if !UNITY_EDITOR
        private static string m_selectedMediaPath = null;
        private static string SelectedMediaPath
        {
            get
            {
                if( m_selectedMediaPath == null )
                {
                    m_selectedMediaPath = Path.Combine( Application.temporaryCachePath, "pickedMedia" );
                    Directory.CreateDirectory( Application.temporaryCachePath );
                }

                return m_selectedMediaPath;
            }
        }
        
        // ANDROID
        
        #if UNITY_ANDROID
        private static AndroidJavaClass m_ajc;
        private static AndroidJavaClass AJC
        {
            get { return m_ajc ??= new AndroidJavaClass( "com.binouze.MobileMediaPicker" ); }
        }
        private static void PickMediaAndroid( UrlPickedCallback callback, MediaType mediaType )
        {
            var selectImages = mediaType is MediaType.Image or MediaType.Any;
            var selectVideos = mediaType is MediaType.Video or MediaType.Any;
            
            AJC.CallStatic( "PickMedia", new MediaPickerCallback( callback ), SelectedMediaPath, selectImages, selectVideos);
        }
        #endif // UNITY_ANDROID
        
        // IOS
        
        #if UNITY_IOS
        [System.Runtime.InteropServices.DllImport( "__Internal" )]
	    private static extern void _MobileMediaPicker_PickMedia( string mediaSavePath, bool selectImages, bool selectVideos, MediaPickedDelegate callback );
        
        private delegate void MediaPickedDelegate(string path);
         
        [MonoPInvokeCallback(typeof(MediaPickedDelegate))] 
        private static void delegateMediaPicked( string path ) 
        {
            Debug.Log("Picked: " + path);

            var callback = _currentIosCallback;
            _currentIosCallback = null;

            if( callback != null )
                CallOnMainThread( () => { callback.Invoke( path ); } );
        }

        private static UrlPickedCallback _currentIosCallback;

        private static void PickMediaIOS( UrlPickedCallback callback, MediaType mediaType )
        {
            _currentIosCallback = callback;

            var selectImages = mediaType is MediaType.Image or MediaType.Any;
            var selectVideos = mediaType is MediaType.Video or MediaType.Any;
            
            _MobileMediaPicker_PickMedia( SelectedMediaPath, selectImages, selectVideos, delegateMediaPicked );
        }
        #endif //UNITY_IOS
        #endif //!UNITY_EDITOR
        
        
        // MAIN THREAD DISPATCHER
        
        
        private static bool Destroyed;
        private static readonly Queue<Action> ActionsToCall = new();
        
        public void OnDestroy()
        {
            Destroyed = true;
        }

        private void Update() 
        {
            lock( ActionsToCall ) 
            {
                while( ActionsToCall.Count > 0 ) 
                {
                    ActionsToCall.Dequeue().Invoke();
                }
            }
        }
        
        private void _Enqueue( Action action )
        {
            lock( ActionsToCall )
            {
                ActionsToCall.Enqueue( action );
            }
        }
        public static void CallOnMainThread( Action action )
        {
            GetInstance()?._Enqueue( action );
        }
        private static void Init()
        {
            GetInstance();
        }
        
        private static MobileMediaPicker _instance;
        private static MobileMediaPicker GetInstance()
        {
            if( Destroyed )
                return null;
            
            if( _instance == null && !Destroyed ) 
            {
                _instance = (MobileMediaPicker)FindObjectOfType( typeof(MobileMediaPicker) );
                if( _instance == null ) 
                {
                    const string goName = "[com.binouze.mobilemediapicker]";          

                    var go = GameObject.Find( goName );
                    if( go == null ) 
                    {
                        go = new GameObject {name = goName};
                        DontDestroyOnLoad( go );
                    }
                    _instance = go.AddComponent<MobileMediaPicker>();                   
                }
            }
            return _instance;
        }
    }
}