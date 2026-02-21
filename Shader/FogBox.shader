Shader "InPlanaria/SimpleVolumetric/FogBox"
{
    Properties
    {
        [HDR]_Color ("Fog Color", Color) = (1,1,1,1)
        [KeywordEnum(Linear, Exponential, ExponentialSquared)] _FogMode ("Fog Mode", Int) = 0
        _Strength ("Strength", Range(0, 5)) = 0.002
        _EdgeFade ("Edge Fade", Range(0, 5)) = 1
        

        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Int) = 8
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull Mode", Int) = 1
        
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
        Tags { "Queue"="Transparent+100" "RenderType"="Transparent" "IgnoreProjector"="True" }
        
        // 設定: 両面描画、深度テスト常にパス、書き込みなし
        Cull [_Cull]
        ZTest [_ZTest]
        ZWrite Off
        Blend [_BlendSrcMode] [_BlendDstMode]
        BlendOp [_BlendOp]
        
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
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_local _FOGMODE_LINEAR _FOGMODE_EXPONENTIAL _FOGMODE_EXPONENTIALSQUARED
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 projPos : TEXCOORD0;
                float3 viewDir : TEXCOORD1; // モデル空間での視線方向
                float3 rayOrigin : TEXCOORD3; // モデル空間でのカメラ位置
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(fixed4, _Color)
                UNITY_DEFINE_INSTANCED_PROP(float, _Strength)
                UNITY_DEFINE_INSTANCED_PROP(float, _EdgeFade)
            UNITY_INSTANCING_BUFFER_END(Props)
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_CameraDepthTexture);

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = UnityObjectToClipPos(v.vertex);
                o.projPos = ComputeScreenPos(o.pos);
                
                // モデル空間でのカメラ位置と頂点方向を計算
                // これにより、Scale 1.0 = 辺1mのボックスとして計算可能
                o.rayOrigin = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1.0)).xyz;
                o.viewDir = v.vertex.xyz - o.rayOrigin;
                
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                // 1. 深度バッファから背景までの距離を取得
                float2 screenUV = i.projPos.xy / i.projPos.w;
                float sceneDepth = LinearEyeDepth(UNITY_SAMPLE_SCREENSPACE_TEXTURE(_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(screenUV)).r);
                
                // sceneDepthに1/cosΘをかける。Θはレイとカメラ方向のなす角。
                // レイ方向をワールド空間に変換して、カメラ前方方向との内積からcosを計算
                float3 rd_world = normalize(mul(unity_ObjectToWorld, float4(i.viewDir, 0)).xyz);
                float3 camForward = -UNITY_MATRIX_V[2].xyz; // カメラの前方ベクトル（ビュー空間の-Z方向）
                float cosTheta = abs(dot(rd_world, camForward));
                sceneDepth *= 1.0 / max(cosTheta, 0.001); // ゼロ除算対策
                sceneDepth = max(sceneDepth, 0.0); // 負の深度を防止

                // 2. レイの準備 (モデル空間)
                float3 rd = normalize(i.viewDir);
                float3 ro = i.rayOrigin;
                
                // 3. ボックスとの交差判定 (中心0,0,0、各軸 -0.5〜0.5)
                // スラブ法 (slab method) による AABB 交差
                float3 boxHalf = float3(0.49, 0.49, 0.49);
                float3 invRd = rcp(rd);
                float3 tNearV = (-boxHalf - ro) * invRd;
                float3 tFarV  = ( boxHalf - ro) * invRd;
                float3 tMinV = min(tNearV, tFarV);
                float3 tMaxV = max(tNearV, tFarV);
                float t1 = max(max(tMinV.x, tMinV.y), tMinV.z); // 手前の交差点
                float t2 = min(min(tMaxV.x, tMaxV.y), tMaxV.z); // 奥の交差点

                if (t2 < 0.0 || t1 > t2) discard; // 交差しない場合は描画しない

                // 4. カメラ座標から交差点までの実際の距離(World)に変換するための係数
                float worldDistK = length(mul(unity_ObjectToWorld, float4(rd, 0)).xyz);
                
                // 5. 線分の開始と終了を制限
                float start = max(0, t1); // カメラより手前は 0
                float end = t2;
                
                // 6. 深度バッファによるクリッピング
                // シーンの深度をモデル空間の距離に近似して計算
                float sceneDistModel = sceneDepth / worldDistK;
                end = min(end, sceneDistModel);

                // 7. 厚みの計算
                float thickness = max(0, end - start);
                
                // ワールド空間の厚みに変換して密度を掛ける
                float worldThickness = thickness * worldDistK;
                float fogAmount = 0.0;
                #ifdef _FOGMODE_LINEAR
                {
                    fogAmount = worldThickness * UNITY_ACCESS_INSTANCED_PROP(Props, _Strength);
                }
                #elif _FOGMODE_EXPONENTIAL
                {
                    fogAmount = 1.0 - exp(-UNITY_ACCESS_INSTANCED_PROP(Props, _Strength) * worldThickness);
                }
                #elif _FOGMODE_EXPONENTIALSQUARED
                {
                    fogAmount = 1.0 - exp(-UNITY_ACCESS_INSTANCED_PROP(Props, _Strength) * worldThickness * worldThickness);
                }
                #endif
                
                // 8. エッジフェード（ボックス面からの距離ベース）
                // レイの中点付近でのボックス面への最短距離を計算
                // _EdgeFade = 0 でフェードなし、値が大きいほど内側まで薄くなる
                float edgeFadeWidth = UNITY_ACCESS_INSTANCED_PROP(Props, _EdgeFade);
                float fresnel = 1.0;
                //if (edgeFadeWidth > 0.0)
                {
                    float3 midPoint = ro + rd * ((start + end) * 0.5);
                    float3 distToFace = boxHalf - abs(midPoint); // 各面への距離
                    float minDist = min(min(distToFace.x, distToFace.y), distToFace.z);
                    fresnel = saturate(minDist / edgeFadeWidth);
                }

                fixed4 col = UNITY_ACCESS_INSTANCED_PROP(Props, _Color);
                col.a = saturate(fogAmount) * col.a * fresnel;

                

                #ifdef LOD_FADE_CROSSFADE
                    col.a = col.a * unity_LODFade.x;
                #endif

                return col;
            }
            ENDCG
        }
    }
}