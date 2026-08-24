using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;

namespace Nahida.Editor
{
    /// <summary>
    /// 一键配置当前场景的渲染设置，以 SampleScene 为基准：
    /// 1. 创建/更新 "Genshin Volume" 全局 Volume，使用 URPGenshinVolumeProfile
    /// 2. 启用场景中所有相机的 Render Post Processing
    /// 3. 从 SampleScene 复制光照环境（环境光/天空盒/雾）和平行光参数
    /// </summary>
    public static class PostProcessSetupTool
    {
        private const string VolumeObjectName = "Genshin Volume";
        private const string VolumeProfilePath = "Assets/URPSettings/URPGenshinVolumeProfile.asset";
        private const string BaselineScenePath = "Assets/Scenes/SampleScene.unity";

        private struct BaselineEnvironment
        {
            public bool Fog;
            public Color FogColor;
            public FogMode FogMode;
            public float FogDensity;
            public Material Skybox;
            public AmbientMode AmbientMode;
            public float AmbientIntensity;
            public Color AmbientSkyColor;
            public Color AmbientEquatorColor;
            public Color AmbientGroundColor;

            public bool HasDirectionalLight;
            public Vector3 LightEulerAngles;
            public Color LightColor;
            public float LightIntensity;
            public LightShadows LightShadows;
        }

        [MenuItem("Nahida/Setup Post Processing (SampleScene Baseline)")]
        public static void Setup()
        {
            VolumeProfile profile = AssetDatabase.LoadAssetAtPath<VolumeProfile>(VolumeProfilePath);
            if (profile == null)
            {
                Debug.LogError($"[PostProcessSetupTool] 找不到 Volume Profile：{VolumeProfilePath}");
                return;
            }

            SetupVolume(profile);
            int disabledCount = DisableOtherGlobalVolumes();
            int cameraCount = SetupCameras();
            bool environmentAligned = SetupEnvironmentFromBaseline();

            EditorSceneManager.MarkAllScenesDirty();
            Debug.Log($"[PostProcessSetupTool] 配置完成：{VolumeObjectName} 使用 {VolumeProfilePath}，" +
                      $"禁用了 {disabledCount} 个其他全局 Volume，" +
                      $"{cameraCount} 个相机启用了 Render Post Processing，" +
                      $"光照环境{(environmentAligned ? "已按 SampleScene 对齐" : "未对齐（基准场景不可用）")}。");
        }

        // 禁用除 Genshin Volume 外的其他激活全局 Volume，避免叠加导致画面异常
        // （新场景默认自带的 "Global Volume" 就是这个问题的来源）
        private static int DisableOtherGlobalVolumes()
        {
            int count = 0;
            foreach (Volume volume in Object.FindObjectsByType<Volume>(FindObjectsSortMode.None))
            {
                if (!volume.isGlobal || volume.gameObject.name == VolumeObjectName)
                    continue;

                Undo.RecordObject(volume.gameObject, "Disable Global Volume");
                volume.gameObject.SetActive(false);
                Debug.Log($"[PostProcessSetupTool] 已禁用全局 Volume：{volume.gameObject.name}");
                count++;
            }
            return count;
        }

        private static void SetupVolume(VolumeProfile profile)
        {
            GameObject volumeObject = GameObject.Find(VolumeObjectName);
            Volume volume;

            if (volumeObject == null)
            {
                volumeObject = new GameObject(VolumeObjectName);
                Undo.RegisterCreatedObjectUndo(volumeObject, "Create Genshin Volume");
                volume = volumeObject.AddComponent<Volume>();
            }
            else
            {
                volume = volumeObject.GetComponent<Volume>();
                if (volume == null)
                    volume = Undo.AddComponent<Volume>(volumeObject);
                else
                    Undo.RecordObject(volume, "Setup Genshin Volume");
            }

            if (!volumeObject.activeSelf)
                volumeObject.SetActive(true);

            // 与 SampleScene 的 Genshin Volume 保持一致
            volume.isGlobal = true;
            volume.priority = 0;
            volume.weight = 1;
            volume.sharedProfile = profile;
        }

        private static int SetupCameras()
        {
            int count = 0;
            foreach (Camera camera in Object.FindObjectsByType<Camera>(FindObjectsSortMode.None))
            {
                UniversalAdditionalCameraData cameraData = camera.GetUniversalAdditionalCameraData();
                if (cameraData.renderPostProcessing)
                    continue;

                Undo.RecordObject(cameraData, "Enable Render Post Processing");
                cameraData.renderPostProcessing = true;
                count++;
            }
            return count;
        }

        // 以加载方式打开 SampleScene 读取其 RenderSettings 和平行光，复制到当前场景
        private static bool SetupEnvironmentFromBaseline()
        {
            Scene targetScene = SceneManager.GetActiveScene();
            if (targetScene.path == BaselineScenePath)
                return true; // 当前就是基准场景，无需复制

            if (AssetDatabase.LoadAssetAtPath<SceneAsset>(BaselineScenePath) == null)
            {
                Debug.LogWarning($"[PostProcessSetupTool] 找不到基准场景：{BaselineScenePath}，跳过光照环境对齐。");
                return false;
            }

            Scene baselineScene = EditorSceneManager.OpenScene(BaselineScenePath, OpenSceneMode.Additive);
            SceneManager.SetActiveScene(baselineScene);

            BaselineEnvironment environment = CaptureEnvironment();

            SceneManager.SetActiveScene(targetScene);
            EditorSceneManager.CloseScene(baselineScene, true);

            ApplyEnvironment(environment);
            return true;
        }

        // 读取激活场景的 RenderSettings 与主平行光
        private static BaselineEnvironment CaptureEnvironment()
        {
            BaselineEnvironment environment = new BaselineEnvironment
            {
                Fog = RenderSettings.fog,
                FogColor = RenderSettings.fogColor,
                FogMode = RenderSettings.fogMode,
                FogDensity = RenderSettings.fogDensity,
                Skybox = RenderSettings.skybox,
                AmbientMode = RenderSettings.ambientMode,
                AmbientIntensity = RenderSettings.ambientIntensity,
                AmbientSkyColor = RenderSettings.ambientSkyColor,
                AmbientEquatorColor = RenderSettings.ambientEquatorColor,
                AmbientGroundColor = RenderSettings.ambientGroundColor,
            };

            Light directionalLight = Object
                .FindObjectsByType<Light>(FindObjectsInactive.Include, FindObjectsSortMode.None)
                .FirstOrDefault(light => light.type == LightType.Directional);

            if (directionalLight != null)
            {
                environment.HasDirectionalLight = true;
                environment.LightEulerAngles = directionalLight.transform.eulerAngles;
                environment.LightColor = directionalLight.color;
                environment.LightIntensity = directionalLight.intensity;
                environment.LightShadows = directionalLight.shadows;
            }

            return environment;
        }

        private static void ApplyEnvironment(BaselineEnvironment environment)
        {
            RenderSettings.fog = environment.Fog;
            RenderSettings.fogColor = environment.FogColor;
            RenderSettings.fogMode = environment.FogMode;
            RenderSettings.fogDensity = environment.FogDensity;
            RenderSettings.skybox = environment.Skybox;
            RenderSettings.ambientMode = environment.AmbientMode;
            RenderSettings.ambientIntensity = environment.AmbientIntensity;
            RenderSettings.ambientSkyColor = environment.AmbientSkyColor;
            RenderSettings.ambientEquatorColor = environment.AmbientEquatorColor;
            RenderSettings.ambientGroundColor = environment.AmbientGroundColor;

            if (!environment.HasDirectionalLight)
                return;

            Light light = FindOrCreateDirectionalLight();
            Undo.RecordObject(light, "Align Directional Light");
            light.transform.rotation = Quaternion.Euler(environment.LightEulerAngles);
            light.color = environment.LightColor;
            light.intensity = environment.LightIntensity;
            light.shadows = environment.LightShadows;
            RenderSettings.sun = light;
        }

        private static Light FindOrCreateDirectionalLight()
        {
            Light light = Object
                .FindObjectsByType<Light>(FindObjectsSortMode.None)
                .FirstOrDefault(candidate => candidate.type == LightType.Directional);

            if (light == null)
            {
                GameObject lightObject = new GameObject("Directional Light");
                Undo.RegisterCreatedObjectUndo(lightObject, "Create Directional Light");
                light = lightObject.AddComponent<Light>();
                light.type = LightType.Directional;
            }

            return light;
        }
    }
}
