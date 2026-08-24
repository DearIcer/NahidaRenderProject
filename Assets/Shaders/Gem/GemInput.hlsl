#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

CBUFFER_START(UnityPerMaterial)
    float4  _BaseMap_ST;
    half4   _BaseColor;
    half4   _DeepColor;
    half    _Cull;

    half    _IOR;
    half    _Dispersion;
    half    _RefractionIntensity;
    half    _DepthFactor;
    half    _InnerGlowIntensity;
    half    _RefractionDistortion;

    half    _TransmissionPower;
    half    _TransmissionIntensity;

    half    _ReflectionIntensity;
    half    _FresnelPower;
    half    _EnvIntensity;
    half    _EnvCubeMip;

    half    _SparklePower;
    half    _SparkleIntensity;
    half4   _SparkleColor;
    half    _SparkleSpread;

    half    _FacetColorCount;
    half    _FacetColorHueRange;
    half    _FacetColorSaturation;
    half    _FacetColorBrightness;
    half    _FacetColorHueShift;
    half    _FacetColorStrength;

    half4   _RimColor;
    half    _RimPower;
    half    _RimIntensity;
CBUFFER_END

TEXTURE2D(_BaseMap);            SAMPLER(sampler_BaseMap);
TEXTURECUBE(_EnvCube);          SAMPLER(sampler_EnvCube);
