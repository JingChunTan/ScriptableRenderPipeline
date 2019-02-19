using UnityEditor.Rendering;
using UnityEngine.Experimental.Rendering.HDPipeline;
using UnityEngine.Rendering;

namespace UnityEditor.Experimental.Rendering.HDPipeline
{
    [CanEditMultipleObjects]
    [VolumeComponentEditor(typeof(AmbientOcclusion))]
    public class AmbientOcclusionEditor : VolumeComponentEditor
    {
        public override void OnInspectorGUI()
        {
            base.OnInspectorGUI();

            if (!(GraphicsSettings.renderPipelineAsset as HDRenderPipelineAsset)
                ?.currentPlatformRenderPipelineSettings.supportSSAO ?? false)
            {
                EditorGUILayout.Space();
                EditorGUILayout.HelpBox("Ambient Occlusion is not supported by the current HDRenderPipelineAsset or there is no one in use.", MessageType.Error, wide: true);
            }
        }
    }
}
