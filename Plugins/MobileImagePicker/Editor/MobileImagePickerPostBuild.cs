#if UNITY_IOS

using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.iOS.Xcode;
using UnityEngine;

namespace com.binouze.Editor
{
    public class MobileImagePickerPostBuild : IPostprocessBuildWithReport
    {
        /// <summary>
        ///   <para>Returns the relative callback order for callbacks.  Callbacks with lower values are called before ones with higher values.</para>
        /// </summary>
        public int callbackOrder { get; } = int.MaxValue-100;

        /// <summary>
        ///   <para>Implement this function to receive a callback after the build is complete.</para>
        /// </summary>
        /// <param name="report">A BuildReport containing information about the build, such as the target platform and output path.</param>
        public void OnPostprocessBuild( BuildReport report )
        {
            Debug.Log($"MobileImagePickerPostBuild {report.summary.result}");
            
            if( report.summary.result is BuildResult.Failed or BuildResult.Cancelled )
                return;

            // read project
            var projectPath = PBXProject.GetPBXProjectPath(report.summary.outputPath);
            var project     = new PBXProject();
            project.ReadFromFile( projectPath );
            
            // add needed frameworks
            var targetGUID = project.GetUnityFrameworkTargetGuid();
            project.AddFrameworkToProject( targetGUID, "Photos.framework",             false );
            project.AddFrameworkToProject( targetGUID, "PhotosUI.framework",           false );
            project.AddFrameworkToProject( targetGUID, "MobileCoreServices.framework", false );
            project.AddFrameworkToProject( targetGUID, "ImageIO.framework",            false );
            
            // save            
            project.WriteToFile( projectPath );
        }
    }
}
#endif

#if UNITY_ANDROID
using System.Xml;
using UnityEngine;
using UnityEditor.Android;
using System.IO;

namespace com.binouze.Editor 
{
    public class MobileImagePickerPostBuild: IPostGenerateGradleAndroidProject
    {
        public int callbackOrder { get; } = int.MaxValue-100;

        public void OnPostGenerateGradleAndroidProject(string basePath)
        {
            ModifyAndroidManifestXmlFile(basePath);
        }
        
        /// <summary>
        /// on android we need to add the activity element in the AndroidManifest
        /// <activity android:name="com.binouze.MobileImagePicker" android:exported="true" android:theme="@style/Theme.AppCompat.MobileImagePicker" />
        ///
        /// we need to add the ModuleDependency service too, for compatibility with older android devices
        /// <!-- Trigger Google Play services to install the backported photo picker module. -->
        /// <service android:name="com.google.android.gms.metadata.ModuleDependencies"
        ///          android:enabled="false"
        ///          android:exported="false"
        ///          tools:ignore="MissingClass">
        ///     <intent-filter>
        ///         <action android:name="com.google.android.gms.metadata.MODULE_DEPENDENCIES" />
        ///     </intent-filter>
        ///     <meta-data android:name="photopicker_activity:0:required" android:value="" />
        /// </service>
        /// </summary>
        /// <param name="basePath"></param>
        private static void ModifyAndroidManifestXmlFile(string basePath)
        {
            var appManifestPath = Path.Combine(basePath, "src/main/AndroidManifest.xml");

            // open the app's AndroidManifest.xml file.
            var doc = new XmlDocument();
            doc.Load(appManifestPath);

            // Add the needed activity entry
            
            var childNode = FindChildNode(FindChildNode(doc, "manifest"), "application");
            if (childNode == null)
            {
                Debug.LogError("Error parsing " + appManifestPath);
            }
            else
            {
                var androidNamespace = childNode.GetNamespaceOfPrefix("android");
                var toolsNamespace   = childNode.GetNamespaceOfPrefix("tools");

                // -----------------------------------------------------------------------------------------------------
                // add the com.binouze.MobileImagePicker activity 
                
                var activityElement = doc.CreateElement("activity");
                activityElement.SetAttribute("name",     androidNamespace, "com.binouze.MobileImagePicker");
                activityElement.SetAttribute("exported", androidNamespace, "true" );
                activityElement.SetAttribute("theme",    androidNamespace, "@style/Theme.AppCompat.MobileImagePicker" );
                SetOrReplaceXmlElement(childNode, activityElement);
			    
                // -----------------------------------------------------------------------------------------------------
                // add the com.google.android.gms.metadata.ModuleDependencies service
                
                var serviceElement = doc.CreateElement("service");
                serviceElement.SetAttribute("name",     androidNamespace, "com.google.android.gms.metadata.ModuleDependencies");
                serviceElement.SetAttribute("enabled",  androidNamespace, "false" );
                serviceElement.SetAttribute("exported", androidNamespace, "false" );
                serviceElement.SetAttribute("ignore",   toolsNamespace,   "MissingClass" );
                
                // prepare the intent-filter element
                var intentFilterElement       = doc.CreateElement("intent-filter");
                var intentFilterActionElement = doc.CreateElement("action");
                intentFilterActionElement.SetAttribute("name", androidNamespace, "com.google.android.gms.metadata.MODULE_DEPENDENCIES");
                intentFilterElement.AppendChild( intentFilterActionElement );
                
                // prepare the meta-data element
                var metaElement = doc.CreateElement("meta-data");
                metaElement.SetAttribute( "name",  androidNamespace, "photopicker_activity:0:required" );
                metaElement.SetAttribute( "value", androidNamespace, "" );
                
                // add the intent-filter to the service element
                serviceElement.AppendChild(intentFilterElement);
                // add the meta-data to the service element
                serviceElement.AppendChild(metaElement);
                
                // add the service in the application
                SetOrReplaceXmlElement(childNode, serviceElement);
                
                
                // -----------------------------------------------------------------------------------------------------
                // save the updated manifest
                
                var settings = new XmlWriterSettings
                {
                    Indent          = true,
                    IndentChars     = "  ",
                    NewLineChars    = "\r\n",
                    NewLineHandling = NewLineHandling.Replace
                };
                
                using var w = XmlWriter.Create(appManifestPath, settings);
                doc.Save(w);
            }
        }

        private static XmlNode FindChildNode( XmlNode parent, string name )
        {
            for( var xmlNode = parent.FirstChild; xmlNode != null; xmlNode = xmlNode.NextSibling )
            {
                if( xmlNode.Name.Equals( name ) )
                    return xmlNode;
            }
            return null;
        }
	
        private static void SetOrReplaceXmlElement( XmlNode parent, XmlElement newElement, XmlNode after = null )
        {
            var attribute = newElement.GetAttribute( "name" );
            var name      = newElement.Name;
            if( TryFindElementWithAndroidName( parent, attribute, out var element, name ) )
                parent.ReplaceChild( newElement, element );
            else
            {
                if( after != null ) parent.InsertAfter( newElement, after );
                else 				parent.AppendChild( newElement );
            }
        }
        
        private static bool TryFindElementWithAndroidName( XmlNode parent, string attrNameValue, out XmlElement element, string elementType = "activity" )
        {
            var namespaceOfPrefix = parent.GetNamespaceOfPrefix( "android" );
            for( var xmlNode = parent.FirstChild; xmlNode != null; xmlNode = xmlNode.NextSibling )
            {
                if( xmlNode is XmlElement xmlElement && xmlElement.Name == elementType && xmlElement.GetAttribute( "name", namespaceOfPrefix ) == attrNameValue )
                {
                    element = xmlElement;
                    return true;
                }
            }
            element = null;
            return false;
        }
    }
}

#endif