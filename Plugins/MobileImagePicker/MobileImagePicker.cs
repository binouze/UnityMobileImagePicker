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
        private readonly MobileImagePicker.UrlPickedCallback Callback;

        public MediaPickerCallback( MobileImagePicker.UrlPickedCallback callback ) : base(
            "com.binouze.MediaPickerCallback" )
        {
            Callback = callback;
        }
        
        [UsedImplicitly]
        public void onUrlPicked(string url)
        {
            Debug.Log( $"onUrlPicked {url}" );
            MobileImagePicker.CallOnMainThread( () => Callback?.Invoke( url ) );
        }
    }
    #endif
    
    public class MobileImagePicker : MonoBehaviour
    {
        public delegate void UrlPickedCallback( string path );

        /// <summary>
        /// pick unique image in the gallery
        /// </summary>
        /// <param name="callback"></param>
        [UsedImplicitly]
        public static void PickImage( UrlPickedCallback callback )
        {
            PickMedia(callback);
        }
        
        private static void PickMedia( UrlPickedCallback callback )
        {
            Init();
            
            #if UNITY_EDITOR
            PickMediaEditor( callback );
            #elif UNITY_ANDROID
            PickMediaAndroid( callback );
            #elif UNITY_IOS
            PickMediaIOS( callback );
            #else
            Debug.LogError( "MobileImagePicker.PickMedia: Unsupported Platform" );
            callback?.Invoke(null)
            #endif
        }
        
        // EDITOR
        
        #if UNITY_EDITOR
        private static void PickMediaEditor( UrlPickedCallback callback )
        {
            var editorFilters = new List<string>(){"Image files", "png,jpg,jpeg"};
            var pickedFile    = UnityEditor.EditorUtility.OpenFilePanelWithFilters( "Select file", "", editorFilters.ToArray() );

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
            get { return m_ajc ??= new AndroidJavaClass( "com.binouze.MobileImagePicker" ); }
        }
        private static void PickMediaAndroid( UrlPickedCallback callback )
        {
            AJC.CallStatic( "PickMedia", new MediaPickerCallback( callback ), SelectedMediaPath, true, false );
        }
        #endif // UNITY_ANDROID
        
        // IOS
        
        #if UNITY_IOS
        [System.Runtime.InteropServices.DllImport( "__Internal" )]
	    private static extern void _MobileImagePicker_PickMedia( string mediaSavePath, bool selectImages, bool selectVideos, MediaPickedDelegate callback );
        
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

        private static void PickMediaIOS( UrlPickedCallback callback )
        {
            _currentIosCallback = callback;
            
            _MobileImagePicker_PickMedia( SelectedMediaPath, true, false, delegateMediaPicked );
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
        
        private static MobileImagePicker _instance;
        private static MobileImagePicker GetInstance()
        {
            if( Destroyed )
                return null;
            
            if( _instance == null && !Destroyed ) 
            {
                _instance = (MobileImagePicker)FindObjectOfType( typeof(MobileImagePicker) );
                if( _instance == null ) 
                {
                    const string goName = "[com.binouze.MobileImagePicker]";          

                    var go = GameObject.Find( goName );
                    if( go == null ) 
                    {
                        go = new GameObject {name = goName};
                        DontDestroyOnLoad( go );
                    }
                    _instance = go.AddComponent<MobileImagePicker>();                   
                }
            }
            return _instance;
        }
    }
}