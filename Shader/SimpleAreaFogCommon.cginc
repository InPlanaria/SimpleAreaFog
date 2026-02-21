#ifndef SIMPLE_AREA_FOG_STEREO_INCLUDED
#define SIMPLE_AREA_FOG_STEREO_INCLUDED

float3 SAF_GetStereoSafeWorldSpaceCameraPos()
{
#if defined(USING_STEREO_MATRICES)
    return unity_StereoWorldSpaceCameraPos[unity_StereoEyeIndex];
#else
    return _WorldSpaceCameraPos;
#endif
}

#endif
