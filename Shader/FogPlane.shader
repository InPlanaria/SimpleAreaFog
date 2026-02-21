Shader "InPlanaria/SimpleFog/FogPlane"
{
    Properties
    {
        [HDR]_NearColor ("Near Fog Color", Color) = (0,0,0,1)
        [HDR]_FarColor ("Far Fog Color", Color) = (0,0,0,1)
        _FarColorStart ("Far Fog Color Start Distance", Float) = 50.0
        _FarColorEnd ("Far Fog Color End Distance", Float) = 200.0

        [KeywordEnum(Linear, Exponential, ExponentialSquared)] _FogMode ("Fog Mode", Int) = 1

        _Strength ("Strength (Exponential Modes)", Range(0, 5)) = 0.002
        _Start_onLinear ("Fog Start Distance (Linear Only)", Float) = 0.0
        _End_onLinear ("Fog End Distance (Linear Only)", Float) = 100.0
        _StrengthOnSkybox ("Strength On Skybox", Range(0, 1)) = 1

        
        

        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Int) = 4
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull Mode", Int) = 2

        [Enum(UnityEngine.Rendering.BlendMode)] _BlendSrcMode ("Blend Src Mode", Int) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _BlendDstMode ("Blend Dst Mode", Int) = 10
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp ("Blend Op", Int) = 0
        
        _StencilRef ("Stencil Reference", Int) = 0
        _StencilReadMask ("Stencil Read Mask", Int) = 255
        _StencilWriteMask ("Stencil Write Mask", Int) = 255
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("Stencil Compare", Int) = 8
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilOp ("Stencil Operation", Int) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilFail ("Stencil Fail", Int) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilZFail ("Stencil ZFail", Int) = 0
    }
    SubShader
    {
        Tags { "Queue"="Transparent+190" "RenderType"="Overlay" "IgnoreProjector"="True" }
        
        // 設定: 両面描画、深度テスト常にパス、書き込みなし
        Cull [_Cull]
        ZTest [_ZTest]
        ZWrite Off
        ZClip Off
        BlendOp [_BlendOp]
        
        Blend [_BlendSrcMode] [_BlendDstMode]
        
        Stencil
        {
            Ref [_StencilRef]
            ReadMask [_StencilReadMask]
            WriteMask [_StencilWriteMask]
            Comp [_StencilComp]
            Pass [_StencilOp]
            Fail [_StencilFail]
            ZFail [_StencilZFail]
        }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_local _FOGMODE_LINEAR _FOGMODE_EXPONENTIAL _FOGMODE_EXPONENTIALSQUARED
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"
            #include "SimpleAreaFogCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 projPos : TEXCOORD0;
                float3 localPos : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            fixed4 _NearColor;
            fixed4 _FarColor;
            float _FarColorStart;
            float _FarColorEnd;
            float _Strength;
            float _StrengthOnSkybox;
            int _FogMode;
            float _Start_onLinear;
            float _End_onLinear;
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_CameraDepthTexture);

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                //// カメラがCubeの外にいる場合、頂点を退化させて描画をスキップ
                //float3 cameraLocalPos = mul(unity_WorldToObject, float4(SAF_GetStereoSafeWorldSpaceCameraPos(), 1.0)).xyz;
                //float3 absCameraPos = abs(cameraLocalPos);
                //bool outsideCube = (absCameraPos.x > 0.5 || absCameraPos.y > 0.5 || absCameraPos.z > 0.5);

                //// 外にいる場合は退化三角形（NaN）にしてラスタライズを完全スキップ
                //float cullMask = outsideCube ? asfloat(0x7FC00000) : 1.0; // NaN or 1.0

                o.pos = UnityObjectToClipPos(v.vertex);// * cullMask;
                o.projPos = ComputeScreenPos(o.pos);
                o.localPos = v.vertex.xyz;
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                // ローカルスペースでカメラ位置を取得
                float3 cameraLocalPos = mul(unity_WorldToObject, float4(SAF_GetStereoSafeWorldSpaceCameraPos(), 1.0)).xyz;
                
                              
                // 深度バッファから背景までの距離を取得
                float2 screenUV = i.projPos.xy / i.projPos.w;
                float sceneDepth = LinearEyeDepth(UNITY_SAMPLE_SCREENSPACE_TEXTURE(_CameraDepthTexture, screenUV));
                
                // sceneDepthに1/cosΘをかける。Θはレイとカメラ方向のなす角。
                // ローカルスペースでのレイ方向をワールド空間に変換してカメラ前方との角度を計算
                float3 localViewDir = i.localPos - cameraLocalPos;
                float3 rd_world = normalize(mul(unity_ObjectToWorld, float4(localViewDir, 0)).xyz);
                float3 camForward = -UNITY_MATRIX_V[2].xyz; // カメラの前方ベクトル（ビュー空間の-Z方向）
                float cosTheta = abs(dot(rd_world, camForward));
                sceneDepth *= 1.0 / max(cosTheta, 0.001); // ゼロ除算対策
                sceneDepth = max(sceneDepth, 0.0); // 負の深度を防止

                // フォグモードに応じて濃さを計算
                float fogAmount = 0.0;
                
                #ifdef _FOGMODE_LINEAR
                {
                    // Linear mode (single clamped expression)
                    fogAmount = saturate((sceneDepth - _Start_onLinear) / max(_End_onLinear - _Start_onLinear, 1e-5));
                }
                #elif _FOGMODE_EXPONENTIAL
                {
                    // Exponential mode
                    fogAmount = 1.0 - exp(-_Strength * sceneDepth);
                }

                #elif _FOGMODE_EXPONENTIALSQUARED
                {
                    // Exponential Squared mode
                    fogAmount = 1.0 - exp(-_Strength * sceneDepth * sceneDepth);
                }
                #endif

                // スカイボックスをスキップ（深度が遠クリップ面に近い場合、0.94～1.00で線形補間）
                float skyboxT = saturate((sceneDepth - _ProjectionParams.z * 0.94) / (_ProjectionParams.z * 0.06));
                fogAmount *= lerp(1.0, _StrengthOnSkybox, skyboxT);
                


                
                // Interpolate between Fog Color and Far Fog Color based on depth range
                float farColorBlend = saturate((sceneDepth - _FarColorStart) / max(_FarColorEnd - _FarColorStart, 0.001));
                fixed4 col = lerp(_NearColor, _FarColor, farColorBlend);
                col.a = saturate(fogAmount) * col.a;
                return col;
            }
            ENDCG
        }
    }
}