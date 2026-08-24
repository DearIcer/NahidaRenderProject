#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

CBUFFER_START(UnityPerMaterial)
    float4  _BaseMap_ST;
    half4   _BaseColor;
    half    _IsDay;
    half    _Cull;
    half    _SrcBlend;
    half    _DstBlend;
    half    _StencilRef;

    half    _BrowShowThrough;
    half    _ShowThroughAlpha;
    half    _ShowThroughMaxDepth;
    half    _ShowThroughStencilRef;

    half4   _LightDirectionMultiplier;
    half    _ReceiveShadows;
    half    _ReceiveShadowMap;
    half    _HairShadowDistance;
    half    _HairShadowDepthBias;
    half    _HairShadowCaster;
    half    _ShadowOffset;
    half    _ShadowSmoothness;
    half4   _ShadowColor;
    half    _UseCustomMaterialType;
    half    _CustomMaterialType;

    half    _EmissionIntensity;

    half4   _FaceDirection;
    half    _FaceShadowOffset;
    half4   _FaceBlushColor;
    half    _FaceBlushStrength;

    half    _SpecularSmoothness;
    half    _NonmetallicIntensity;
    half    _MetallicIntensity;

    half    _RimOffset;
    half    _RimThreshold;
    half    _RimIntensity;

    half    _UseSmoothNormal;
    half    _OutlineWidth;
    half4   _OutlineWidthParams;
    half    _OutlineZOffset;
    half4   _ScreenOffset;
    half4   _OutlineColor;
    half4   _OutlineColor2;
    half4   _OutlineColor3;
    half4   _OutlineColor4;
    half4   _OutlineColor5;
CBUFFER_END

TEXTURE2D(_BaseMap);            SAMPLER(sampler_BaseMap);
TEXTURE2D(_LightMap);           SAMPLER(sampler_LightMap);
TEXTURE2D(_ShadowRamp);         SAMPLER(sampler_ShadowRamp);
TEXTURE2D(_NormalMap);          SAMPLER(sampler_NormalMap);
TEXTURE2D(_FaceLightMap);       SAMPLER(sampler_FaceLightMap);
TEXTURE2D(_FaceShadow);         SAMPLER(sampler_FaceShadow);
TEXTURE2D(_MetalMap);           SAMPLER(sampler_MetalMap);

// 刘海投影遮罩（由 HairShadowFeature 每帧渲染：R=头发标记，G=视空间深度/米）
TEXTURE2D(_HairMaskTexture);      SAMPLER(sampler_HairMaskTexture);

// 角色专用高精度 ShadowMap（由 CharacterShadowMap.cs 每帧渲染并写入全局变量）
TEXTURE2D(_CharacterShadowMap);   SAMPLER(sampler_CharacterShadowMap);
float4x4 _CharacterShadowMatrix;
half    _CharacterShadowBias;
float4  _CharacterShadowMap_TexelSize;
float   _CharacterShadowDebug;
