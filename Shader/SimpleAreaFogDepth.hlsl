#ifndef SIMPLE_AREA_FOG_DEPTH_INCLUDED
#define SIMPLE_AREA_FOG_DEPTH_INCLUDED

// URP depth texture sampling helper.
// Include this file from URP SubShader HLSLPROGRAM blocks.
// SampleSceneDepth() handles stereo and depth buffer format automatically.
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

float SAF_SampleDepthEye(float2 screenUV)
{
    return LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
}

#endif // SIMPLE_AREA_FOG_DEPTH_INCLUDED
