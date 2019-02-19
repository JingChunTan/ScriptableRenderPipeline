using UnityEditor.Rendering;
using UnityEngine.Experimental.Rendering.HDPipeline;
using UnityEngine.Rendering;

namespace UnityEditor.Experimental.Rendering.HDPipeline
{
    [CanEditMultipleObjects]
    [VolumeComponentEditor(typeof(VolumetricLightingController))]
    public class VolumetricLightingControllerEditor : VolumeComponentEditor
    {
        public override void OnInspectorGUI()
        {
            base.OnInspectorGUI();

            if (!(GraphicsSettings.renderPipelineAsset as HDRenderPipelineAsset)
                ?.currentPlatformRenderPipelineSettings.supportVolumetrics ?? false)
            {
                EditorGUILayout.Space();
                EditorGUILayout.HelpBox("Volumetrics is not supported by the current HDRenderPipelineAsset or there is no one in use.", MessageType.Error, wide: true);
            }
        }
    }
}
