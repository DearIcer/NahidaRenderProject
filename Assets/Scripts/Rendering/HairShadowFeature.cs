using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Nahida.Rendering
{
    /// <summary>
    /// 刘海投影（屏幕空间）：在不透明物体渲染前，把头发（带有 HairShadowMask
    /// Pass 且 _HairShadowCaster=1 的材质）以“R=头发标记、G=视空间深度”渲染到
    /// 屏幕 RT _HairMaskTexture。Character shader 的脸部随后沿视线空间光照方向
    /// 偏移屏幕 UV 采样该 RT，得到干净的刘海投影（非 ShadowMap 方案）。
    /// 参考：《【Unity URP】以Render Feature实现卡通渲染中的刘海投影》
    /// </summary>
    public class HairShadowFeature : ScriptableRendererFeature
    {
        private HairShadowPass _hairShadowPass;

        public override void Create()
        {
            _hairShadowPass = new HairShadowPass(RenderPassEvent.BeforeRenderingOpaques);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_hairShadowPass);
        }

        protected override void Dispose(bool disposing)
        {
            _hairShadowPass?.Dispose();
            _hairShadowPass = null;
        }
    }

    public class HairShadowPass : ScriptableRenderPass
    {
        private static readonly ShaderTagId HairShadowMaskTag = new ShaderTagId("HairShadowMask");

        // 清空色：R=0（无头发），G=9999（视距无穷远，任何脸部都比它近）
        private static readonly Color ClearColor = new Color(0f, 9999f, 0f, 0f);

        private RTHandle _hairMask;

        public HairShadowPass(RenderPassEvent renderPassEvent)
        {
            base.profilingSampler = new ProfilingSampler(nameof(HairShadowPass));
            base.renderPassEvent = renderPassEvent;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cameraType = renderingData.cameraData.cameraType;
            if (cameraType == CameraType.Preview || cameraType == CameraType.Reflection)
            {
                return;
            }

            var descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.depthBufferBits = 0;
            descriptor.msaaSamples = 1;
            descriptor.graphicsFormat = GraphicsFormat.R16G16_SFloat;
            RenderingUtils.ReAllocateIfNeeded(ref _hairMask, descriptor, FilterMode.Bilinear,
                name: "_HairMaskTexture");

            var command = CommandBufferPool.Get();
            using (new ProfilingScope(command, profilingSampler))
            {
                command.SetRenderTarget(_hairMask);
                command.ClearRenderTarget(false, true, ClearColor);
                command.SetGlobalTexture("_HairMaskTexture", _hairMask);
                context.ExecuteCommandBuffer(command);
                command.Clear();

                // 只有 Character shader 带 "HairShadowMask" Pass，其他物体不会被绘制
                var drawingSettings = CreateDrawingSettings(HairShadowMaskTag, ref renderingData,
                    SortingCriteria.CommonOpaque);
                var filteringSettings = new FilteringSettings(RenderQueueRange.all);
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
            }
            context.ExecuteCommandBuffer(command);
            CommandBufferPool.Release(command);
        }

        public void Dispose()
        {
            _hairMask?.Release();
            _hairMask = null;
        }
    }
}
