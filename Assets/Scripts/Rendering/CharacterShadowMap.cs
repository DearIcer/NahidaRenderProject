using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Nahida.Rendering
{
    /// <summary>
    /// 角色专用高精度 ShadowMap（与屏幕空间刘海投影互补的另一种投影方案）。
    /// 每帧沿主光方向构建一个紧贴角色的正交视锥，将角色的 Renderer 深度渲染到
    /// 一张专用 RT，并以全局 shader 变量提供给 Character shader 采样（2x2 PCF）。
    /// 用于角色特写，避免 URP 主光 ShadowMap 精度不足。
    /// </summary>
    [ExecuteAlways]
    public class CharacterShadowMap : MonoBehaviour
    {
        [Header("Target")]
        [Tooltip("角色根节点；留空则自动收集场景中使用 Character shader 的 Renderer")]
        [SerializeField] private Transform m_Target;

        [Tooltip("主平行光；留空则使用 RenderSettings.sun")]
        [SerializeField] private Light m_Light;

        [Header("Shadow Map")]
        [SerializeField] private int m_Resolution = 4096;

        [Tooltip("自动根据角色包围盒调整取景半径，保证整个角色都被拍到")]
        [SerializeField] private bool m_AutoFit = true;

        [Tooltip("正交取景半径（米），仅在 AutoFit 关闭时生效")]
        [SerializeField] private float m_Radius = 0.8f;

        [Tooltip("取景中心相对包围盒中心的偏移（用于特写时对准头部）")]
        [SerializeField] private Vector3 m_CenterOffset = Vector3.zero;

        [Tooltip("自动取景时半径的额外余量系数")]
        [SerializeField] private float m_AutoFitMargin = 1.1f;

        [Tooltip("阴影相机沿 -光方向 的偏移距离")]
        [SerializeField] private float m_Distance = 2f;

        [Tooltip("深度比较偏移，防止自遮挡条纹（shadow acne）")]
        [SerializeField] private float m_DepthBias = 0.001f;

        [Header("Debug")]
        [Tooltip("在屏幕左上角显示阴影贴图和状态，用于排查投影问题")]
        [SerializeField] private bool m_DebugView;

        [Tooltip("把 shader 采样过程的中间量直接显示在角色上，用于定位问题")]
        [SerializeField] private DebugSample m_DebugSample = DebugSample.Off;

        private enum DebugSample
        {
            Off = 0,            // 关闭
            Shadow = 1,         // 灰度：最终阴影值（白=受光，黑=遮挡）
            InFrustum = 2,      // 灰度：片元是否在阴影视锥内（白=在内）
            OccluderDepth = 3,  // 灰度：采样到的遮挡物深度
            FragmentDepth = 4,  // 灰度：片元自身深度
            ShadowUV = 5        // 彩色：采样 UV（R=U，G=V）
        }

        private RenderTexture _shadowMap;
        private Material _depthMaterial;
        private CommandBuffer _commandBuffer;
        private readonly List<Renderer> _renderers = new List<Renderer>();
        private Bounds _bounds;

        private static readonly int ShadowMapId = Shader.PropertyToID("_CharacterShadowMap");
        private static readonly int ShadowMatrixId = Shader.PropertyToID("_CharacterShadowMatrix");
        private static readonly int ShadowBiasId = Shader.PropertyToID("_CharacterShadowBias");
        private static readonly int ShadowTexelId = Shader.PropertyToID("_CharacterShadowMap_TexelSize");
        private static readonly int ShadowDebugId = Shader.PropertyToID("_CharacterShadowDebug");

        private void OnEnable()
        {
            CreateShadowMap();
            Shader depthShader = Shader.Find("Hidden/Character/ShadowDepth");
            if (depthShader != null)
            {
                _depthMaterial = new Material(depthShader) { hideFlags = HideFlags.HideAndDontSave };
            }
            _commandBuffer = new CommandBuffer { name = "Character Shadow Map" };
            RefreshRenderers();

            // 未渲染前先置为安全默认值（全亮）
            Shader.SetGlobalTexture(ShadowMapId, Texture2D.whiteTexture);
            Shader.SetGlobalMatrix(ShadowMatrixId, Matrix4x4.identity);
            Shader.SetGlobalFloat(ShadowBiasId, 0f);
        }

        private void OnDisable()
        {
            if (_commandBuffer != null)
            {
                _commandBuffer.Release();
                _commandBuffer = null;
            }
            if (_depthMaterial != null)
            {
                DestroyImmediate(_depthMaterial);
                _depthMaterial = null;
            }
            if (_shadowMap != null)
            {
                _shadowMap.Release();
                DestroyImmediate(_shadowMap);
                _shadowMap = null;
            }
            Shader.SetGlobalTexture(ShadowMapId, Texture2D.whiteTexture);
            Shader.SetGlobalMatrix(ShadowMatrixId, Matrix4x4.identity);
            Shader.SetGlobalFloat(ShadowDebugId, 0f);
        }

        private void CreateShadowMap()
        {
            if (_shadowMap != null)
            {
                _shadowMap.Release();
                DestroyImmediate(_shadowMap);
            }
            _shadowMap = new RenderTexture(m_Resolution, m_Resolution, 16, RenderTextureFormat.RFloat)
            {
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp
            };
        }

        [ContextMenu("Refresh Renderers")]
        private void RefreshRenderers()
        {
            _renderers.Clear();
            if (m_Target != null)
            {
                foreach (var renderer in m_Target.GetComponentsInChildren<Renderer>(true))
                {
                    if (renderer is MeshRenderer || renderer is SkinnedMeshRenderer)
                    {
                        _renderers.Add(renderer);
                    }
                }
            }
            else
            {
                // 自动收集：场景里使用 Character shader 的 Renderer 即角色部件
                foreach (var renderer in FindObjectsOfType<Renderer>())
                {
                    if (!(renderer is MeshRenderer || renderer is SkinnedMeshRenderer))
                    {
                        continue;
                    }
                    foreach (var material in renderer.sharedMaterials)
                    {
                        if (material != null && material.shader != null &&
                            material.shader.name == "Character")
                        {
                            _renderers.Add(renderer);
                            break;
                        }
                    }
                }
            }

            if (_renderers.Count > 0)
            {
                _bounds = _renderers[0].bounds;
                foreach (var renderer in _renderers)
                {
                    _bounds.Encapsulate(renderer.bounds);
                }
            }
        }

        private void LateUpdate()
        {
            if (_depthMaterial == null)
            {
                return;
            }
            Light light = m_Light != null ? m_Light : RenderSettings.sun;
            if (light == null || light.type != LightType.Directional)
            {
                return;
            }
            _renderers.RemoveAll(r => r == null);
            if (_renderers.Count == 0)
            {
                RefreshRenderers();
                if (_renderers.Count == 0)
                {
                    return;
                }
            }

            if (_shadowMap.width != m_Resolution)
            {
                CreateShadowMap();
            }

            // 阴影视锥：以角色包围盒中心（而非根节点位置，根节点在脚底）为取景中心，
            // 沿 -光方向 后退。
            // 注意：Unity 观察空间是右手系（相机朝 +Z），TRS 逆矩阵需翻转 Z，
            // 与 Camera.worldToCameraMatrix 约定一致
            Bounds bounds = _renderers[0].bounds;
            for (int i = 1; i < _renderers.Count; i++)
            {
                bounds.Encapsulate(_renderers[i].bounds);
            }
            Vector3 center = bounds.center + m_CenterOffset;
            Vector3 lightDir = light.transform.forward;
            Vector3 position = center - lightDir * m_Distance;
            Quaternion rotation = Quaternion.LookRotation(lightDir, Vector3.up);
            Matrix4x4 view = Matrix4x4.Scale(new Vector3(1f, 1f, -1f)) *
                             Matrix4x4.TRS(position, rotation, Vector3.one).inverse;

            // AutoFit：把包围盒 8 个角点变换到灯光空间，取 |x|/|y| 最大值作为半径，
            // 保证任意光向下整个角色都被拍到
            float radius = m_Radius;
            if (m_AutoFit)
            {
                radius = 0f;
                for (int i = 0; i < 8; i++)
                {
                    Vector3 corner = bounds.center + Vector3.Scale(bounds.extents,
                        new Vector3((i & 1) * 2 - 1, (i & 2) - 1, (i & 4) / 2 - 1));
                    Vector3 viewCorner = view.MultiplyPoint(corner);
                    radius = Mathf.Max(radius, Mathf.Abs(viewCorner.x), Mathf.Abs(viewCorner.y));
                }
                radius *= m_AutoFitMargin;
            }
            Matrix4x4 proj = Matrix4x4.Ortho(-radius, radius, -radius, radius,
                0.01f, m_Distance * 2f);

            // 手动 ExecuteCommandBuffer 时 Unity 不会对矩阵做平台转换
            //（D3D 深度 [0,1]、RT 的 V 翻转），渲染与采样必须使用同一个
            // GPU 投影矩阵，否则采样位置与写入位置对不上
            Matrix4x4 gpuProj = GL.GetGPUProjectionMatrix(proj, true);

            _commandBuffer.Clear();
            _commandBuffer.SetRenderTarget(_shadowMap);
            _commandBuffer.ClearRenderTarget(true, true, Color.white, 1f);
            _commandBuffer.SetViewProjectionMatrices(view, gpuProj);
            foreach (var renderer in _renderers)
            {
                if (renderer.enabled)
                {
                    _commandBuffer.DrawRenderer(renderer, _depthMaterial);
                }
            }
            Graphics.ExecuteCommandBuffer(_commandBuffer);

            Matrix4x4 shadowMatrix = gpuProj * view;
            Shader.SetGlobalMatrix(ShadowMatrixId, shadowMatrix);
            Shader.SetGlobalTexture(ShadowMapId, _shadowMap);
            Shader.SetGlobalFloat(ShadowBiasId, m_DepthBias);
            Shader.SetGlobalVector(ShadowTexelId,
                new Vector4(1f / m_Resolution, 1f / m_Resolution, 0f, 0f));
            Shader.SetGlobalFloat(ShadowDebugId, (float)m_DebugSample);
        }

        private void OnGUI()
        {
            if (!m_DebugView || _shadowMap == null)
            {
                return;
            }
            Light light = m_Light != null ? m_Light : RenderSettings.sun;
            GUI.DrawTexture(new Rect(10, 10, 256, 256), _shadowMap, ScaleMode.StretchToFill, false);
            GUI.color = Color.black;
            GUI.DrawTexture(new Rect(10, 270, 400, 24), Texture2D.whiteTexture);
            GUI.color = Color.white;
            GUI.Label(new Rect(14, 272, 600, 22),
                string.Format("renderers: {0}, light: {1}",
                    _renderers.Count,
                    light != null ? light.name : "<none>"));
        }
    }
}
