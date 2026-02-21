Shader "InPlanaria/SimpleFog/FogFakeLightSphere"
{
    Properties
    {
        [Toggle( _FastMode_ON )] _FastMode ("Fast Mode", Float) = 0
        
        [Toggle( _Halo_ON )] _Halo ("Use Halo", Float) = 1.0
        [HDR]_HaloColor ("Halo Color", Color) = (1,1,1,1)
        _HaloStrength ("Halo Strength", Range(0, 5)) = 1
        _HaloMeshEdgeFade ("Halo Mesh Edge Fade", Range(0, 5)) = 0.1

        [Toggle( _FakeReflection_ON )] _FakeReflection ("Use Fake Reflection", Float) = 1
        _FakeReflectionStrength ("Fake Reflection Strength", Range(0, 5)) = 0.5

        [Toggle( _FakeReflectSpotMode_ON )] _FakeReflectionSpot ("Use Fake Reflection Spot", Float) = 0
        _FakeReflectionSpotAngle ("Fake Reflection SpotAngle", Range(0, 360)) = 60.0
        _FakeReflectionSpotAngleFade ("Fake Reflection SpotAngleFade", Range(0, 360)) = 10.0
        

        
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Int) = 8
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull Mode", Int) = 0
        
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
        Tags { "Queue"="Transparent+98" "RenderType"="Overlay" "IgnoreProjector"="True" }
        
        // 設定: 両面描画、深度テスト常にパス、書き込みなし
        Cull [_Cull]
        ZTest [_ZTest]
        ZWrite Off
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
            #include "UnityCG.cginc"

            #pragma shader_feature_local _FastMode_ON
            #pragma shader_feature_local _Halo_ON
            #pragma shader_feature_local _SpotMode_ON
            #pragma shader_feature_local _FakeReflection_ON
            #pragma shader_feature_local _FakeReflectSpotMode_ON
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_instancing


            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 projPos : TEXCOORD0;
                float3 viewDir : TEXCOORD1; // モデル空間での視線方向
                float3 rayOrigin : TEXCOORD3; // モデル空間でのカメラ位置
                float3 normal : TEXCOORD2; // メッシュ法線
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(half4, _HaloColor)
                UNITY_DEFINE_INSTANCED_PROP(float, _HaloStrength)
                UNITY_DEFINE_INSTANCED_PROP(float, _HaloMeshEdgeFade)
                UNITY_DEFINE_INSTANCED_PROP(float, _FakeReflectionStrength)
                UNITY_DEFINE_INSTANCED_PROP(float, _FakeReflectionSpotAngle)
                UNITY_DEFINE_INSTANCED_PROP(float, _FakeReflectionSpotAngleFade)

            UNITY_INSTANCING_BUFFER_END(Props)
            
            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
            

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = UnityObjectToClipPos(v.vertex);
                o.projPos = ComputeScreenPos(o.pos);
                // モデル空間でのカメラ位置と頂点方向を計算
                o.rayOrigin = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1.0)).xyz;
                o.viewDir = v.vertex.xyz - o.rayOrigin;
                o.normal = v.normal;
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                // 1. 深度バッファから背景までの距離を取得
                float sceneDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.projPos)));
                
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
                
                // 3. 球体との交差判定 (中心0,0,0、半径0.5)
                // 方程式: |ro + rd*t|^2 = r^2
                float r = 0.49;
                float b = dot(ro, rd);
                float c = dot(ro, ro) - r * r;
                float d = b * b - c;

                if (d < 0.0) discard; // 交差しない場合は描画しない

                float sqrtD = sqrt(d);
                float t1 = -b - sqrtD; // 手前の交差点
                float t2 = -b + sqrtD; // 奥の交差点

                // 4. カメラ座標から交差点までの実際の距離(World)に変換するための係数
                float worldDistK = length(mul(unity_ObjectToWorld, float4(rd, 0)).xyz);
                
                // 5. 線分の終了を制限
                float start = max(0, t1); // カメラより手前は 0
                float end = t2;

                // 6. 深度バッファによるクリッピング
                // シーンの深度をモデル空間の距離に近似して計算
                float sceneDistModel = sceneDepth / worldDistK;
                float end_dist = min(end, sceneDistModel);

                #ifdef _Halo_ON                                       
                    // 線分start~endと球体中心(0,0,0)の最短距離を求める
                    float t_closest = clamp(dot(-ro, rd) / dot(rd, rd), start, end);
                    float3 closest_point = ro + rd * t_closest;
                    float distance_ray_to_center = length(closest_point);

                    #ifdef _FastMode_ON
                        float fogAmount=UNITY_ACCESS_INSTANCED_PROP(Props, _HaloStrength);
                    #else
                        // 厚みの計算
                        float thickness = max(0, end_dist - start);
                        // ワールド空間の厚みに変換して密度を掛ける
                        float fogAmount=thickness *UNITY_ACCESS_INSTANCED_PROP(Props, _HaloStrength);
                    #endif

                    //_MeshEdgeFadeに応じて、メッシュ法線と視線方向の角度でフェード
                    float normalDotView = abs(dot(normalize(i.normal), -rd));
                    float meshEdgeFadeFactor = saturate(pow(normalDotView, UNITY_ACCESS_INSTANCED_PROP(Props, _HaloMeshEdgeFade)));

                    half4 col = UNITY_ACCESS_INSTANCED_PROP(Props, _HaloColor);
                    float distanceSq= 1/(distance_ray_to_center*distance_ray_to_center+1)-1/(1+r*r);
                    col.a = distanceSq * fogAmount * meshEdgeFadeFactor * col.a; 
                    col.rgb = col.rgb * distanceSq;
                #else
                    half4 col = half4(0, 0, 0, 0);
                #endif

                #ifdef _FakeReflection_ON
                  //もしレイが球体の中で終わっている場合、レイの終了地点end_distから球体中心までの距離をdistance_refとし、
                  //_FakeReflectionStrengthに応じて反射光をcolに加算する

                  float distance_ref = (end>sceneDistModel) ? length(ro + rd * end_dist) : r;

                  half4 col_ref = UNITY_ACCESS_INSTANCED_PROP(Props, _HaloColor);
                  float distance_refSq= saturate(1/(distance_ref*distance_ref+1)-1/(1+r*r));
                  float refpower=UNITY_ACCESS_INSTANCED_PROP(Props, _FakeReflectionStrength)*distance_refSq;

                    #ifdef _FakeReflectSpotMode_ON
                        // スポットモードの場合、球体中心からレイの終了地点までのベクトルと、メッシュの-Z軸のベクトルのなす角度が_FakeReflectionSpotAngleを超えていたら、refpowerを0にする
                        // _FakeReflectionSpotAngleから_FakeReflectionSpotAngle-_FakeReflectionSpotAngleFadeの範囲で線形補間する
                        // _FakeReflectionSpotAngle-_FakeReflectionSpotAngleFadeより角度が小さいなら、refpowerはそのまま
                        
                        float3 vec_to_ray_end = ro + rd * end_dist;
                        float3 mesh_neg_z = float3(0, 0, -1);
                        
                        float cos_angle = dot(normalize(vec_to_ray_end), mesh_neg_z);
                        float angle = acos(clamp(cos_angle, -1.0, 1.0)) * 57.2957795; // ラジアンから度に変換
                        
                        float spot_angle = UNITY_ACCESS_INSTANCED_PROP(Props, _FakeReflectionSpotAngle);
                        float spot_angle_fade = UNITY_ACCESS_INSTANCED_PROP(Props, _FakeReflectionSpotAngleFade);
                        
                        refpower *= step(angle, spot_angle) * saturate((spot_angle - angle) / max(spot_angle_fade, 0.001));

                    #endif

                    col.rgb += col_ref.rgb * refpower;
                    col.a +=  col_ref.a * refpower;

                #endif



                #ifdef LOD_FADE_CROSSFADE
                    col.a = col.a * saturate(unity_LODFade.x);
                #endif
                
                return col;
            }
            ENDCG
        }
    }
}