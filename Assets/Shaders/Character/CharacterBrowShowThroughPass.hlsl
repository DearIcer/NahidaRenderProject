#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

// 眉毛透发 Pass：在头发之后渲染（UniversalForwardOnly），
// 通过 ZTest Greater + Stencil(Equal) 只在被头发遮挡的像素上以半透明叠加眉毛。

Varyings BrowShowThroughVertex(Attributes input)
{
#if _BROW_SHOW_THROUGH
    return ForwardPassVertex(input);
#else
    // 功能关闭时输出零面积三角形（所有顶点裁剪到同一点），避免任何片元开销
    Varyings output = (Varyings)0;
    output.positionCS = float4(0.0, 0.0, 0.0, 1.0);
    return output;
#endif
}

half4 BrowShowThroughFragment(Varyings input, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_TARGET
{
    // 遮挡物距离眉毛太远（如从背后看到的后脑勺头发）时不透眉
    float2 uv = input.positionNDC.xy / input.positionNDC.w;
    float sceneDepth = LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);
    float browDepth = -TransformWorldToView(input.positionWS).z;
    if (sceneDepth - browDepth > _ShowThroughMaxDepth)
        discard;

    half3 finalColor = ComputeToonShading(input, facing);

    half3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);

    // 视线越贴近表面（侧面视角）透出越弱，避免侧发上出现悬浮的透视斑块
    half viewFade = saturate(dot(input.normalWS, V));

    // 只有镜头位于面部前方半球时才透出，杜绝从脑后看到眉眼
    //（眼部面片的法线方向不可靠，用 MaterialUpdater 每帧写入的脸部朝向判断）
    half3 F = SafeNormalize(_FaceDirection.xyz);
    half faceFade = smoothstep(0.0, 0.3, dot(F, V));

    return half4(finalColor, _ShowThroughAlpha * viewFade * faceFade);
}
