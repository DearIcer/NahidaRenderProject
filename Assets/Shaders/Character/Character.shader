Shader "Character"
{
    Properties
    {
        [Header(General)]
        [MainTexture]_BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [ToggleUI] _IsDay("Is Day", Float) = 1
        [Toggle(_DOUBLE_SIDED)] _DoubleSided("Double Sided", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull", Float) = 2
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Src Blend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Dst Blend", Float) = 0
        _StencilRef("Stencil Ref", Float) = 0

        [Header(Show Through)]
        [Toggle(_BROW_SHOW_THROUGH)] _BrowShowThrough("Brow Show Through", Float) = 0
        _ShowThroughAlpha("Show Through Alpha", Range(0, 1)) = 0.65
        _ShowThroughMaxDepth("Show Through Max Depth", Float) = 0.2
        _ShowThroughStencilRef("Show Through Stencil Ref", Float) = 1

        [Header(Shadow)]
        _LightMap("Light Map", 2D) = "white" {}
        [Toggle(_RECEIVE_SHADOWS)] _ReceiveShadows("Receive Shadows (Hair Shadow On Face)", Float) = 1
        _HairShadowDistance("Hair Shadow Distance", Range(0, 50)) = 15
        _HairShadowDepthBias("Hair Shadow Depth Bias", Range(0, 0.1)) = 0.02
        [ToggleUI] _HairShadowCaster("Hair Shadow Caster", Float) = 0
        [Toggle(_RECEIVE_SHADOW_MAP)] _ReceiveShadowMap("Receive Shadow Map (Dedicated RT)", Float) = 0
        _LightDirectionMultiplier("Light Direction Multiplier", Vector) = (1,1,1,0)
        _ShadowOffset("Shadow Offset", Float) = 0
        _ShadowSmoothness("Shadow Smoothness", Float) = 0
        [HDR] _ShadowColor("Shadow Color", Color) = (1,1,1,1)
        _ShadowRamp("Shadow Ramp", 2D) = "white" {}
        [ToggleUI] _UseCustomMaterialType("Use Custom Material Type", Float) = 0
        _CustomMaterialType("Custom Material Type", Float) = 1

        [Header(Emission)]
        [Toggle(_EMISSION)] _UseEmission("Use Emission", Float) = 0
        _EmissionIntensity("Emission Intensity", Float) = 1

        [Header(Normal)]
        [Toggle(_NORMAL_MAP)] _UseNormalMap("Use Normal Map", Float) = 0
        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}

        [Header(Face)]
        [Toggle(_IS_FACE)] _IsFace("Is Face", Float) = 0
        _FaceDirection("Face Direction", Vector) = (0,0,1,0)
        _FaceShadowOffset("Face Shadow Offset", Float) = 0
        _FaceBlushColor("Face Blush Color", Color) = (1,1,1,1)
        _FaceBlushStrength("Face Blush Strength", Float) = 1
        _FaceLightMap("Face Light Map", 2D) = "white" {}
        _FaceShadow("Face Shadow", 2D) = "white" {}

        [Header(Specular)]
        [Toggle(_SPECULAR)] _UseSpecular("Use Specular", Float) = 0
        _SpecularSmoothness("Specular Smoothness", Float) = 1
        _NonmetallicIntensity("Nonmetallic Intensity", Float) = 1
        _MetallicIntensity("Metallic Intensity", Float) = 1
        _MetalMap("Metal Map", 2D) = "white" {}

        [Header(Rim Light)]
        [Toggle(_RIM)] _UseRim("Use Rim", Float) = 0
        _RimOffset("Rim Offset", Float) = 1
        _RimThreshold("Rim Threshold", Float) = 1
        _RimIntensity("Rim Intensity", Float) = 1

        [Header(Outline)]
        [ToggleUI] _UseSmoothNormal("Use Smooth Normal", Float) = 0
        _OutlineWidth("Outline Width", Float) = 1
        _OutlineWidthParams("Outline Width Params", Vector) = (0,1,0,1)
        _OutlineZOffset("Outline Z Offset", Float) = 0
        _ScreenOffset("Screen Offset", Vector) = (0,0,0,0)
        _OutlineColor("Outline Color", Color) = (0,0,0,1)
        _OutlineColor2("Outline Color 2", Color) = (0,0,0,1)
        _OutlineColor3("Outline Color 3", Color) = (0,0,0,1)
        _OutlineColor4("Outline Color 4", Color) = (0,0,0,1)
        _OutlineColor5("Outline Color 5", Color) = (0,0,0,1)
    }

    Subshader
    {
        Tags
        {
            "RenderType" = "Opaque"
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
            Blend[_SrcBlend][_DstBlend]

            Stencil
            {
                Ref[_StencilRef]
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM

            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fragment _ _WRITE_RENDERING_LAYERS

            // Unity defined keywords
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog
            #pragma multi_compile_fragment _ DEBUG_DISPLAY

            #pragma shader_feature_local_fragment _DOUBLE_SIDED
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _NORMAL_MAP
            #pragma shader_feature_local_fragment _IS_FACE
            #pragma shader_feature_local_fragment _SPECULAR
            #pragma shader_feature_local_fragment _RIM
            #pragma shader_feature_local_fragment _RECEIVE_SHADOWS
            #pragma shader_feature_local_fragment _RECEIVE_SHADOW_MAP

            #pragma vertex ForwardPassVertex
            #pragma fragment ForwardPassFragment

            #include "CharacterInput.hlsl"
            #include "CharacterForwardPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "BrowShowThrough"
            Tags {"LightMode" = "UniversalForwardOnly"}

            Cull[_Cull]
            ZWrite Off
            ZTest Greater
            Blend SrcAlpha OneMinusSrcAlpha

            Stencil
            {
                Ref[_ShowThroughStencilRef]
                Comp Equal
            }

            HLSLPROGRAM

            #pragma shader_feature_local _BROW_SHOW_THROUGH

            #pragma shader_feature_local_fragment _DOUBLE_SIDED
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _NORMAL_MAP
            #pragma shader_feature_local_fragment _IS_FACE
            #pragma shader_feature_local_fragment _SPECULAR
            #pragma shader_feature_local_fragment _RIM
            #pragma shader_feature_local_fragment _RECEIVE_SHADOWS
            #pragma shader_feature_local_fragment _RECEIVE_SHADOW_MAP

            #pragma vertex BrowShowThroughVertex
            #pragma fragment BrowShowThroughFragment

            #include "CharacterInput.hlsl"
            #include "CharacterForwardPass.hlsl"
            #include "CharacterBrowShowThroughPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "HairShadowMask"
            Tags {"LightMode" = "HairShadowMask"}

            Cull Off
            ZWrite Off
            ZTest Always
            ColorMask RG

            HLSLPROGRAM

            #pragma vertex HairShadowMaskVertex
            #pragma fragment HairShadowMaskFragment

            #include "CharacterInput.hlsl"
            #include "CharacterHairShadowPass.hlsl"

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

        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags {"LightMode" = "SRPDefaultUnlit"}

            Cull Front

            HLSLPROGRAM

            #pragma vertex OutlinePassVertex
            #pragma fragment OutlinePassFragment

            #include "CharacterInput.hlsl"
            #include "CharacterOutlinePass.hlsl"

            ENDHLSL
        }
    }
}
