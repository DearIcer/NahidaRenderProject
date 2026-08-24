#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float4 color        : COLOR;
    float2 uv           : TEXCOORD0;
    float2 backUV       : TEXCOORD1;
};

struct Varyings
{
    float2 uv           : TEXCOORD0;
    float2 backUV       : TEXCOORD1;
    float3 positionWS   : TEXCOORD2;
    half3 tangentWS     : TEXCOORD3;
    half3 bitangentWS   : TEXCOORD4;
    half3 normalWS      : TEXCOORD5;
    float4 positionNDC  : TEXCOORD6;
    half4 color         : COLOR;
    float4 positionCS   : SV_POSITION;
};

half GetShadow(Varyings input, half3 lightDirection, half aoFactor)
{
    half NDotL = dot(input.normalWS, lightDirection);
    half halfLambert = 0.5 * NDotL + 0.5;
    half shadow = saturate(2.0 * halfLambert * aoFactor);
    return lerp(shadow, 1.0, step(0.9, aoFactor));
}

half GetFaceShadow(Varyings input, half3 lightDirection)
{
    half3 F = SafeNormalize(half3(_FaceDirection.x, 0.0, _FaceDirection.z));
    half3 L = SafeNormalize(half3(lightDirection.x, 0.0, lightDirection.z));
    half FDotL = dot(F, L);
    half FCrossL = cross(F, L).y;
    
    half2 shadowUV = input.uv;
    shadowUV.x = lerp(shadowUV.x, 1.0 - shadowUV.x, step(0.0, FCrossL));
    half faceShadowMap = SAMPLE_TEXTURE2D(_FaceLightMap, sampler_FaceLightMap, shadowUV).r;
    half faceShadow = step(-0.5 * FDotL + 0.5 + _FaceShadowOffset, faceShadowMap);

    half faceMask = SAMPLE_TEXTURE2D(_FaceShadow, sampler_FaceShadow, input.uv).a;
    half maskedFaceShadow = lerp(faceShadow, 1.0, faceMask);

    return maskedFaceShadow;
}

half3 GetShadowColor(half shadow, half material, half day)
{
    int index = 4;
    index = lerp(index, 1, step(0.2, material));
    index = lerp(index, 2, step(0.4, material));
    index = lerp(index, 0, step(0.6, material));
    index = lerp(index, 3, step(0.8, material));

    half rangeMin = 0.5 + _ShadowOffset - _ShadowSmoothness;
    half rangeMax = 0.5 + _ShadowOffset;
    half2 rampUV = half2(smoothstep(rangeMin, rangeMax, shadow), index / 10.0 + 0.5 * day + 0.05);
    half3 shadowRamp = SAMPLE_TEXTURE2D(_ShadowRamp, sampler_ShadowRamp, rampUV);

    half3 shadowColor = shadowRamp * lerp(_ShadowColor, 1.0, smoothstep(0.9, 1.0, rampUV.x));
    shadowColor = lerp(shadowColor, 1.0, step(rangeMax, shadow));

    return shadowColor;
}

half3 GetSpecular(Varyings input, half3 lightDirection, half3 albedo, half3 lightMap)
{
    half3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);
    half3 H = SafeNormalize(lightDirection + V);
    half NDotH = dot(input.normalWS, H);
    half blinnPhong = pow(saturate(NDotH), _SpecularSmoothness);

    half3 normalVS = TransformWorldToViewNormal(input.normalWS, true);
    half2 matcapUV = 0.5 * normalVS.xy + 0.5;
    half3 metalMap = SAMPLE_TEXTURE2D(_MetalMap, sampler_MetalMap, matcapUV);

    half3 nonMetallic = step(1.1, lightMap.b + blinnPhong) * lightMap.r * _NonmetallicIntensity;
    half3 metallic = blinnPhong * lightMap.b * albedo * metalMap * _MetallicIntensity;
    half3 specular = lerp(nonMetallic, metallic, step(0.9, lightMap.r));

    return specular;
}

half GetRim(Varyings input)
{
    half3 normalVS = TransformWorldToViewNormal(input.normalWS, true);
    float2 uv = input.positionNDC.xy / input.positionNDC.w;
    float2 offset = float2(_RimOffset * normalVS.x / _ScreenParams.x, 0.0);

    float depth = LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);
    float offsetDepth = LinearEyeDepth(SampleSceneDepth(uv + offset), _ZBufferParams);
    half rim = smoothstep(0.0, _RimThreshold, offsetDepth - depth) * _RimIntensity;

    half3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);
    half NDotV = dot(input.normalWS, V);
    half fresnel = pow(saturate(1.0 - NDotV), 5.0);

    return rim * fresnel;
}

// 刘海投影：沿视线空间光照方向偏移屏幕 UV 采样头发遮罩（HairShadowFeature 渲染），
// 1 = 受光，0 = 刘海阴影。带深度校验，排除脑后头发造成的错误投影。
half GetHairShadow(Varyings input, half3 lightDirection)
{
    float2 scrUV = input.positionNDC.xy / input.positionNDC.w;
    float4 scaledScreenParams = GetScaledScreenParams();

    // 视线空间光照方向；除以 NDC.w 修正相机距离（近小远大）
    half3 viewLightDir = normalize(TransformWorldToViewDir(lightDirection));
    float2 offset = _HairShadowDistance * viewLightDir.xy * (1.0 / input.positionNDC.w);
    float2 sampleUV = scrUV + offset / scaledScreenParams.xy;

    half2 mask = SAMPLE_TEXTURE2D(_HairMaskTexture, sampler_HairMaskTexture, sampleUV).rg;
    float faceDepth = -TransformWorldToView(input.positionWS).z;

    // 遮罩处必须有头发（R=1），且头发须在脸部之前（G < 脸部深度 + 偏移）
    half occluded = step(0.5, mask.r) * step(mask.g, faceDepth + _HairShadowDepthBias);
    return 1.0 - occluded;
}

// 角色专用高精度 ShadowMap 采样（CharacterShadowMap.cs 渲染），
// 1 = 受光，0 = 投影遮挡。2x2 PCF 柔化边缘，视锥外视为受光。
half GetCharacterShadowMap(float3 positionWS)
{
    float4 shadowCS = mul(_CharacterShadowMatrix, float4(positionWS, 1.0));
    float3 shadowNDC = shadowCS.xyz / shadowCS.w;
    float2 shadowUV = shadowNDC.xy * 0.5 + 0.5;
    // D3D 纹理 V=0 在顶部，NDC y 需要翻转
    shadowUV.y = 1.0 - shadowUV.y;

    // 阴影视锥之外不参与遮挡
    float inFrustum = step(0.0, shadowUV.x) * step(shadowUV.x, 1.0)
                    * step(0.0, shadowUV.y) * step(shadowUV.y, 1.0)
                    * step(0.0, shadowNDC.z) * step(shadowNDC.z, 1.0);

    // 注意反转 Z（D3D11/Vulkan 等）：近平面 z=1、远平面 z=0，"z 越大越近"，
    // 比较方向和 bias 符号都要翻转，否则所有像素都会误判为受光（阴影完全消失）
    float depth = shadowNDC.z;
    half castShadow = 0.0;
    half occ0 = SAMPLE_TEXTURE2D(_CharacterShadowMap, sampler_CharacterShadowMap, shadowUV + float2(-0.5, -0.5) * _CharacterShadowMap_TexelSize.xy).r;
    half occ1 = SAMPLE_TEXTURE2D(_CharacterShadowMap, sampler_CharacterShadowMap, shadowUV + float2( 0.5, -0.5) * _CharacterShadowMap_TexelSize.xy).r;
    half occ2 = SAMPLE_TEXTURE2D(_CharacterShadowMap, sampler_CharacterShadowMap, shadowUV + float2(-0.5,  0.5) * _CharacterShadowMap_TexelSize.xy).r;
    half occ3 = SAMPLE_TEXTURE2D(_CharacterShadowMap, sampler_CharacterShadowMap, shadowUV + float2( 0.5,  0.5) * _CharacterShadowMap_TexelSize.xy).r;
#if UNITY_REVERSED_Z
    castShadow += step(occ0, depth + _CharacterShadowBias);
    castShadow += step(occ1, depth + _CharacterShadowBias);
    castShadow += step(occ2, depth + _CharacterShadowBias);
    castShadow += step(occ3, depth + _CharacterShadowBias);
#else
    castShadow += step(depth - _CharacterShadowBias, occ0);
    castShadow += step(depth - _CharacterShadowBias, occ1);
    castShadow += step(depth - _CharacterShadowBias, occ2);
    castShadow += step(depth - _CharacterShadowBias, occ3);
#endif
    castShadow *= 0.25;
    return lerp(1.0, castShadow, inFrustum);
}

// 采样调试：把采样过程的中间量直接输出到屏幕
half4 GetCharacterShadowDebug(float3 positionWS)
{
    float4 shadowCS = mul(_CharacterShadowMatrix, float4(positionWS, 1.0));
    float3 shadowNDC = shadowCS.xyz / shadowCS.w;
    float2 shadowUV = shadowNDC.xy * 0.5 + 0.5;
    // D3D 纹理 V=0 在顶部，NDC y 需要翻转
    shadowUV.y = 1.0 - shadowUV.y;
    float inFrustum = step(0.0, shadowUV.x) * step(shadowUV.x, 1.0)
                    * step(0.0, shadowUV.y) * step(shadowUV.y, 1.0)
                    * step(0.0, shadowNDC.z) * step(shadowNDC.z, 1.0);
    half occ = SAMPLE_TEXTURE2D(_CharacterShadowMap, sampler_CharacterShadowMap, shadowUV).r;

    int mode = (int)(_CharacterShadowDebug + 0.5);
    if (mode == 2) return half4(inFrustum, inFrustum, inFrustum, 1.0);
    if (mode == 3) return half4(occ, occ, occ, 1.0);
    if (mode == 4) return half4(shadowNDC.z, shadowNDC.z, shadowNDC.z, 1.0);
    if (mode == 5) return half4(shadowUV, 0.0, 1.0);

    half dbg = GetCharacterShadowMap(positionWS);
    return half4(dbg, dbg, dbg, 1.0);
}

Varyings ForwardPassVertex(Attributes input)
{
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    Varyings output = (Varyings)0;
    output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
    output.backUV = TRANSFORM_TEX(input.backUV, _BaseMap);
    output.positionWS = vertexInput.positionWS;
    output.tangentWS = normalInput.tangentWS;
    output.bitangentWS = normalInput.bitangentWS;
    output.normalWS = normalInput.normalWS;
    output.color = input.color;
    output.positionNDC = vertexInput.positionNDC;
    output.positionCS = vertexInput.positionCS;

    output.positionCS.xy += _ScreenOffset.xy * output.positionCS.w;

    return output;
}

half3 ComputeToonShading(Varyings input, FRONT_FACE_TYPE facing)
{
#if _DOUBLE_SIDED
    input.uv = lerp(input.uv, input.backUV, IS_FRONT_VFACE(facing, 0.0, 1.0));
#endif

    half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
    half3 albedo = baseMap.rgb * _BaseColor.rgb;
    half alpha = baseMap.a;

#if _IS_FACE
    albedo = lerp(albedo, _FaceBlushColor.rgb, _FaceBlushStrength * alpha);
#endif

#if _NORMAL_MAP
    half3x3 tangentToWorld = half3x3(input.tangentWS, input.bitangentWS, input.normalWS);
    half4 normalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv);
    half3 normalTS = UnpackNormal(normalMap);
    half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld, true);
    input.normalWS = normalWS;
#endif

    Light mainLight = GetMainLight();
    half3 lightDirection = SafeNormalize(mainLight.direction * _LightDirectionMultiplier);

    half4 lightMap = SAMPLE_TEXTURE2D(_LightMap, sampler_LightMap, input.uv);
    half material = lerp(lightMap.a, _CustomMaterialType, _UseCustomMaterialType);
#if _IS_FACE
        half shadow = GetFaceShadow(input, lightDirection);
#else
        half aoFactor = lightMap.g * input.color.r;
        half shadow = GetShadow(input, lightDirection, aoFactor);
#endif
#if _IS_FACE && _RECEIVE_SHADOWS
        // 刘海投影：与脸部 SDF 阴影取交集，任一判定为暗则为暗部
        shadow = min(shadow, GetHairShadow(input, lightDirection));
#endif
#if _RECEIVE_SHADOW_MAP
        // 角色专用高精度 ShadowMap：与 toon/SDF 阴影取交集
        shadow = min(shadow, GetCharacterShadowMap(input.positionWS));
#endif
    half3 shadowColor = GetShadowColor(shadow, material, _IsDay);

    half3 specular = 0.0;
#if _SPECULAR
    specular = GetSpecular(input, lightDirection, albedo, lightMap.rgb);
#endif

    half3 emission = 0.0;
#if _EMISSION
    emission = albedo * _EmissionIntensity * alpha;
#endif

    half3 rim = 0.0;
#if _RIM
    rim = albedo * GetRim(input);
#endif

    half3 finalColor = albedo * shadowColor + specular + rim + emission;

    return finalColor;
}

half4 ForwardPassFragment(Varyings input, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_TARGET
{
#if _RECEIVE_SHADOW_MAP
    // 采样调试：直接显示 shadowmap 采样中间量
    if (_CharacterShadowDebug > 0.5)
    {
        return GetCharacterShadowDebug(input.positionWS);
    }
#endif
    half3 finalColor = ComputeToonShading(input, facing);
    half finalAlpha = 1.0;

    return half4(finalColor, finalAlpha);
}
