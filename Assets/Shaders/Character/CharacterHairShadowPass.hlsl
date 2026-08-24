#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

// 刘海投影遮罩 Pass：R = 头发标记（1），G = 视空间深度（米）。
// 只有头发材质（_HairShadowCaster = 1）实际绘制；
// 其他材质输出零面积三角形，不产生任何片元。

struct HairShadowMaskAttributes
{
    float4 positionOS   : POSITION;
};

struct HairShadowMaskVaryings
{
    float4 positionCS   : SV_POSITION;
    half   viewDepth    : TEXCOORD0;
};

HairShadowMaskVaryings HairShadowMaskVertex(HairShadowMaskAttributes input)
{
    HairShadowMaskVaryings output = (HairShadowMaskVaryings)0;
    if (_HairShadowCaster < 0.5)
    {
        output.positionCS = float4(0.0, 0.0, 0.0, 1.0);
        return output;
    }
    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.positionCS = TransformWorldToHClip(positionWS);
    output.viewDepth = -TransformWorldToView(positionWS).z;
    return output;
}

half4 HairShadowMaskFragment(HairShadowMaskVaryings input) : SV_TARGET
{
    return half4(1.0, input.viewDepth, 0.0, 1.0);
}
