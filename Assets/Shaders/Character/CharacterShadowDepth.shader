Shader "Hidden/Character/ShadowDepth"
{
    // 角色专用阴影贴图的深度写入 shader：
    // 由 CharacterShadowMap.cs 通过 CommandBuffer.DrawRenderer 调用，
    // 将线性深度（clip.z / clip.w）写入 RFloat RT。
    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        Pass
        {
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

            #pragma vertex ShadowDepthVertex
            #pragma fragment ShadowDepthFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings ShadowDepthVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half ShadowDepthFragment(Varyings input) : SV_TARGET
            {
                return input.positionCS.z / input.positionCS.w;
            }

            ENDHLSL
        }
    }
}
