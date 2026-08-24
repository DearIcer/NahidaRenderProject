#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float2 uv           : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS   : SV_POSITION;
    float3 positionWS   : TEXCOORD0;
    float3 normalWS     : TEXCOORD1;
    float2 uv           : TEXCOORD2;
    float4 screenPos    : TEXCOORD3;
};

// 折射进入宝石后再折射出射（近似二次折射），全内反射时退化为内部反射
float3 ExitRefract(float3 I, float3 N, half eta)
{
    float3 refrIn = refract(I, N, eta);
    if (all(refrIn == 0))
        return reflect(I, N);

    float3 refrOut = refract(refrIn, -N, rcp(eta));
    // 内部全反射
    if (all(refrOut == 0))
        return reflect(refrIn, -N);

    return refrOut;
}

// 采样环境：优先使用自定义 Cubemap，否则用场景反射探针/天空盒
half3 SampleEnv(float3 dir)
{
#if defined(_USE_ENV_CUBE)
    return SAMPLE_TEXTURECUBE_LOD(_EnvCube, sampler_EnvCube, dir, _EnvCubeMip).rgb * _EnvIntensity;
#else
    return GlossyEnvironmentReflection(dir, 0.0h, 1.0h) * _EnvIntensity;
#endif
}

// 每个晶面一个稳定的随机值，用于闪光强弱差异
half FacetHash(float3 N)
{
    return frac(sin(dot(N, float3(12.9898, 78.233, 45.164))) * 43758.5453);
}

half3 HsvToRgb(half3 c)
{
    half4 K = half4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    half3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

// 每个切面一个颜色，色相随视角流转（虹彩效果）
half3 GetFacetColor(float3 N, half NdotV)
{
#if defined(_FACET_COLOR)
    half hue = FacetHash(N);
    // 量化到固定数量的色板（0 表示完全随机）
    if (_FacetColorCount > 0.5)
        hue = floor(hue * _FacetColorCount) / _FacetColorCount;
    // 视角相关的色相偏移：正对与斜视时颜色不同
    hue = frac(hue + (1.0 - NdotV) * _FacetColorHueShift);
    // 限制色相范围：默认 0.15 即红→橙→黄的暖色系（0 为红，0.167 为黄）
    hue *= _FacetColorHueRange;
    half3 facetColor = HsvToRgb(half3(hue, _FacetColorSaturation, _FacetColorBrightness));
    return lerp(half3(1, 1, 1), facetColor, _FacetColorStrength);
#else
    return half3(1, 1, 1);
#endif
}

Varyings ForwardPassVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

    output.positionCS = positionInputs.positionCS;
    output.positionWS = positionInputs.positionWS;
    output.normalWS = normalInputs.normalWS;
    output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
    output.screenPos = ComputeScreenPos(positionInputs.positionCS);

    return output;
}

half4 ForwardPassFragment(Varyings input, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
{
    float3 normalWS = normalize(input.normalWS);

#if defined(_FLAT_NORMAL)
    // 用屏幕空间导数求几何平面法线，保证每个切面是平的（即使模型是光滑法线）
    normalWS = normalize(cross(ddy(input.positionWS), ddx(input.positionWS)));
    if (dot(normalWS, normalize(input.normalWS)) < 0)
        normalWS = -normalWS;
#endif

#if defined(_DOUBLE_SIDED)
    normalWS *= IS_FRONT_VFACE(facing, 1.0, -1.0);
#endif

    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    float3 I = -viewDirWS;

    half NdotV = saturate(dot(normalWS, viewDirWS));

    // 菲涅尔（钻石 F0 约 0.17）
    half fresnel = 0.17h + 0.83h * pow(1.0h - NdotV, _FresnelPower);

    // 镜面反射
    half3 reflectCol = SampleEnv(reflect(I, normalWS)) * _ReflectionIntensity;

    // 色散折射：RGB 三通道使用略有差异的折射率
    half eta = rcp(_IOR);
    float3 refrR = ExitRefract(I, normalWS, eta * (1.0h + _Dispersion));
    float3 refrG = ExitRefract(I, normalWS, eta);
    float3 refrB = ExitRefract(I, normalWS, eta * (1.0h - _Dispersion));
#if defined(_SCENE_REFRACTION)
    // 屏幕空间折射：采样宝石身后的场景画面并按折射方向扭曲，
    // 产生真实的"看透内部"感，转动视角时内部画面会随之流动
    float2 screenUV = input.screenPos.xy / input.screenPos.w;
    float3x3 viewRot = (float3x3)UNITY_MATRIX_V;
    float2 offR = mul(viewRot, refrR - I).xy * _RefractionDistortion;
    float2 offG = mul(viewRot, refrG - I).xy * _RefractionDistortion;
    float2 offB = mul(viewRot, refrB - I).xy * _RefractionDistortion;
    half3 refractCol = half3(
        SampleSceneColor(screenUV + offR).r,
        SampleSceneColor(screenUV + offG).g,
        SampleSceneColor(screenUV + offB).b);
#else
    half3 refractCol = half3(SampleEnv(refrR).r, SampleEnv(refrG).g, SampleEnv(refrB).b);
#endif

    // 假内部深度：越正对镜头越浅，边缘颜色越深
    half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
    half depth = pow(NdotV, _DepthFactor);
    half3 tint = lerp(_DeepColor.rgb, _BaseColor.rgb * baseMap.rgb, depth);
    refractCol *= tint * _RefractionIntensity;

    // 每个切面不同颜色，色相随视角流转
    half3 facetColor = GetFacetColor(normalWS, NdotV);
    refractCol *= facetColor;

    // 内部辉光：加法叠加基础色，避免多层乘法让宝石发暗，模拟内部透光感
    half innerGlow = lerp(0.3h, 1.0h, depth);
    refractCol += _BaseColor.rgb * baseMap.rgb * facetColor * innerGlow * _InnerGlowIntensity;

    // 菲涅尔混合反射与折射
    half3 color = lerp(refractCol, reflectCol, fresnel);

    // 钻石闪光：每个切面用哈希随机偏移反射方向，只有转动到特定视角时才被点亮，
    // 视角一变闪光就在切面间跳动，形成"一闪一闪"的效果
    float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
    Light mainLight = GetMainLight(shadowCoord);
    float3 facetRand = float3(
        FacetHash(normalWS),
        FacetHash(normalWS + 17.17),
        FacetHash(normalWS + 31.31)) - 0.5;
    float3 glintDir = normalize(reflect(I, normalWS) + facetRand * _SparkleSpread);
    half glint = pow(saturate(dot(glintDir, mainLight.direction)), _SparklePower);
    // 第二层更尖锐的闪光，错开角度增加层次
    float3 glintDir2 = normalize(reflect(I, normalWS) + facetRand.yzx * _SparkleSpread * 2.0);
    half glint2 = pow(saturate(dot(glintDir2, mainLight.direction)), _SparklePower * 2.0);
    color += _SparkleColor.rgb * facetColor * mainLight.color * mainLight.shadowAttenuation
           * (glint + glint2 * 0.5) * _SparkleIntensity;

    // 背光透射：光源在宝石背后时整颗宝石被点亮，珠宝通透感的关键
    half transmission = pow(saturate(dot(-mainLight.direction, viewDirWS)), _TransmissionPower);
    color += _BaseColor.rgb * facetColor * mainLight.color * mainLight.shadowAttenuation
           * transmission * _TransmissionIntensity;

    // 边缘光
    half rim = pow(1.0h - NdotV, _RimPower) * _RimIntensity;
    color += _RimColor.rgb * rim;

    // 雾效
    half fogFactor = ComputeFogFactor(input.positionCS.z);
    color = MixFog(color, fogFactor);

    return half4(color, _BaseColor.a * baseMap.a);
}
