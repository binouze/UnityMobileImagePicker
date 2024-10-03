#if UNITY_ANDROID
using System.Xml;
using UnityEngine;
using UnityEditor.Android;
using System.IO;

namespace com.binouze.Editor 
{
    public class MobileMediaPickerPostBuild: IPostGenerateGradleAndroidProject
    {
        public int callbackOrder { get { return 1; } }

        public void OnPostGenerateGradleAndroidProject(string basePath)
        {
            ModifyAndroidManifestXmlFile(basePath);
        }
        
        /// <summary>
        /// on android we need to add the activity element in the AndroidManifest
        /// <activity android:name="com.binouze.MobileMediaPicker" android:exported="true" android:theme="@style/Theme.AppCompat.MobileMediaPicker" />
        /// </summary>
        /// <param name="basePath"></param>
        private void ModifyAndroidManifestXmlFile(string basePath)
        {
            var appManifestPath = Path.Combine(basePath, "src/main/AndroidManifest.xml");

            // Let's open the app's AndroidManifest.xml file.
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
                var namespaceOfPrefix = childNode.GetNamespaceOfPrefix("android");

                TryFindElementWithAndroidName( childNode, "com.binouze.MobileMediaPicker", out var activity );
			    
                var element1 = doc.CreateElement("activity");
                element1.SetAttribute("name",     namespaceOfPrefix, "com.binouze.MobileMediaPicker");
                element1.SetAttribute("exported", namespaceOfPrefix, "true" );
                element1.SetAttribute("theme",    namespaceOfPrefix, "@style/Theme.AppCompat.MobileMediaPicker" );
                SetOrReplaceXmlElement(childNode, element1, activity);
			    
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