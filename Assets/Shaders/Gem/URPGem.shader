Shader "URPGem"
{
    Properties
    {
        [Header(General)]
        [MainTexture]_BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 0.3, 0.05, 1)
        _DeepColor("Deep Color", Color) = (0.35, 0.03, 0, 1)
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull", Float) = 2
        [Toggle(_DOUBLE_SIDED)] _DoubleSided("Double Sided", Float) = 0

        [Header(Refraction)]
        _IOR("Index Of Refraction", Range(1, 3)) = 2.4
        _Dispersion("Dispersion", Range(0, 0.2)) = 0.02
        _RefractionIntensity("Refraction Intensity", Range(0, 2)) = 1.3
        _DepthFactor("Fake Depth Factor", Range(0.1, 8)) = 1
        _InnerGlowIntensity("Inner Glow Intensity", Range(0, 2)) = 0.5
        [Toggle(_SCENE_REFRACTION)] _SceneRefraction("Use Scene Refraction", Float) = 1
        _RefractionDistortion("Refraction Distortion", Range(0, 0.5)) = 0.15

        [Header(Transmission)]
        _TransmissionPower("Transmission Power", Range(0.1, 8)) = 2
        _TransmissionIntensity("Transmission Intensity", Range(0, 4)) = 1.5

        [Header(Reflection)]
        _ReflectionIntensity("Reflection Intensity", Range(0, 2)) = 1
        _FresnelPower("Fresnel Power", Range(0.1, 10)) = 5
        [Toggle(_USE_ENV_CUBE)] _UseEnvCube("Use Custom Env Cube", Float) = 0
        [NoScaleOffset] _EnvCube("Env Cube", Cube) = "black" {}
        _EnvIntensity("Env Intensity", Range(0, 4)) = 1
        _EnvCubeMip("Env Cube Mip", Range(0, 8)) = 0

        [Header(Sparkle)]
        _SparklePower("Sparkle Power", Range(1, 2048)) = 512
        _SparkleIntensity("Sparkle Intensity", Range(0, 20)) = 5
        [HDR] _SparkleColor("Sparkle Color", Color) = (2, 1.6, 1.2, 1)
        _SparkleSpread("Sparkle Spread", Range(0, 1)) = 0.15

        [Header(Facet Color)]
        [Toggle(_FACET_COLOR)] _FacetColor("Enable Facet Color", Float) = 0
        _FacetColorCount("Facet Color Count (0 = Random)", Range(0, 24)) = 0
        _FacetColorHueRange("Facet Color Hue Range", Range(0, 1)) = 0.15
        _FacetColorSaturation("Facet Color Saturation", Range(0, 1)) = 0.8
        _FacetColorBrightness("Facet Color Brightness", Range(0, 2)) = 1.2
        _FacetColorHueShift("View Hue Shift", Range(0, 1)) = 0.3
        _FacetColorStrength("Facet Color Strength", Range(0, 1)) = 1

        [Header(Rim Light)]
        _RimColor("Rim Color", Color) = (1, 0.85, 0.6, 1)
        _RimPower("Rim Power", Range(0.1, 10)) = 3
        _RimIntensity("Rim Intensity", Range(0, 2)) = 0.5

        [Header(Facet)]
        [Toggle(_FLAT_NORMAL)] _FlatNormal("Force Flat Facet Normal", Float) = 0
    }

    Subshader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "Forward"
            Tags {"LightMode" = "UniversalForward"}

            Cull[_Cull]
            ZWrite On

            HLSLPROGRAM

            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fog

            #pragma shader_feature_local _DOUBLE_SIDED
            #pragma shader_feature_local _FLAT_NORMAL
            #pragma shader_feature_local_fragment _USE_ENV_CUBE
            #pragma shader_feature_local_fragment _FACET_COLOR
            #pragma shader_feature_local_fragment _SCENE_REFRACTION

            #pragma vertex ForwardPassVertex
            #pragma fragment ForwardPassFragment

            #include "GemInput.hlsl"
            #include "GemForwardPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask R
            Cull[_Cull]

            HLSLPROGRAM

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"

            ENDHLSL
        }
    }
}
