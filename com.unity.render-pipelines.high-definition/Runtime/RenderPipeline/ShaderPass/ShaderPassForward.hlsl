#if SHADERPASS != SHADERPASS_FORWARD
#error SHADERPASS_is_not_correctly_define
#endif

#ifdef _WRITE_TRANSPARENT_VELOCITY
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/VelocityVertexShaderCommon.hlsl"

PackedVaryingsType Vert(AttributesMesh inputMesh, AttributesPass inputPass)
{
    VaryingsType varyingsType;
    varyingsType.vmesh = VertMesh(inputMesh);
    return VelocityVS(varyingsType, inputMesh, inputPass);
}

#ifdef TESSELLATION_ON

PackedVaryingsToPS VertTesselation(VaryingsToDS input)
{
    VaryingsToPS output;
    output.vmesh = VertMeshTesselation(input.vmesh);
    VelocityPositionZBias(output);

    output.vpass.positionCS = input.vpass.positionCS;
    output.vpass.previousPositionCS = input.vpass.previousPositionCS;

    return PackVaryingsToPS(output);
}

#endif // TESSELLATION_ON

#else // _WRITE_TRANSPARENT_VELOCITY

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/VertMesh.hlsl"

PackedVaryingsType Vert(AttributesMesh inputMesh)
{
    VaryingsType varyingsType;
    varyingsType.vmesh = VertMesh(inputMesh);

    return PackVaryingsType(varyingsType);
}

#ifdef TESSELLATION_ON

PackedVaryingsToPS VertTesselation(VaryingsToDS input)
{
    VaryingsToPS output;
    output.vmesh = VertMeshTesselation(input.vmesh);

    return PackVaryingsToPS(output);
}


#endif // TESSELLATION_ON

#endif // _WRITE_TRANSPARENT_VELOCITY


#ifdef TESSELLATION_ON
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/ShaderPass/TessellationShare.hlsl"
#endif

void Frag(PackedVaryingsToPS packedInput,
        #ifdef OUTPUT_SPLIT_LIGHTING
            out float4 outColor : SV_Target0,  // outSpecularLighting
            out float4 outDiffuseLighting : SV_Target1,
            OUTPUT_SSSBUFFER(outSSSBuffer)
        #else
            out float4 outColor : SV_Target0
        #ifdef _WRITE_TRANSPARENT_VELOCITY
          , out float4 outVelocity : SV_Target1
        #endif // _WRITE_TRANSPARENT_VELOCITY
        #endif // OUTPUT_SPLIT_LIGHTING
        #ifdef _DEPTHOFFSET_ON
            , out float outputDepth : SV_Depth
        #endif
          )
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(packedInput);
    FragInputs input = UnpackVaryingsMeshToFragInputs(packedInput.vmesh);

    uint2 tileIndex = uint2(input.positionSS.xy) / GetTileSize();
#if defined(UNITY_SINGLE_PASS_STEREO)
    tileIndex.x -= unity_StereoEyeIndex * _NumTileClusteredX;
#endif

    // input.positionSS is SV_Position
    PositionInputs posInput = GetPositionInput_Stereo(input.positionSS.xy, _ScreenSize.zw, input.positionSS.z, input.positionSS.w, input.positionRWS.xyz, tileIndex, unity_StereoEyeIndex);

#ifdef VARYINGS_NEED_POSITION_WS
    float3 V = GetWorldSpaceNormalizeViewDir(input.positionRWS);
#else
    // Unused
    float3 V = float3(1.0, 1.0, 1.0); // Avoid the division by 0
#endif

    SurfaceData surfaceData;
    BuiltinData builtinData;
    GetSurfaceAndBuiltinData(input, V, posInput, surfaceData, builtinData);

    BSDFData bsdfData = ConvertSurfaceDataToBSDFData(input.positionSS.xy, surfaceData);

    PreLightData preLightData = GetPreLightData(V, posInput, bsdfData);

    outColor = float4(0.0, 0.0, 0.0, 0.0);

    // We need to skip lighting when doing debug pass because the debug pass is done before lighting so some buffers may not be properly initialized potentially causing crashes on PS4.
#ifdef DEBUG_DISPLAY
    // Init in debug display mode to quiet warning
    #ifdef OUTPUT_SPLIT_LIGHTING
    outDiffuseLighting = 0;
    ENCODE_INTO_SSSBUFFER(surfaceData, posInput.positionSS, outSSSBuffer);
    #endif

    // Same code in ShaderPassForwardUnlit.shader
    bool viewMaterial = false;
    for (int index = 1; index <= int(_DebugViewMaterialArray[0]); index++)
    {
        int indexMaterialProperty = int(_DebugViewMaterialArray[index]);
        if (indexMaterialProperty != 0)
        {
            viewMaterial = true;

            float3 result = float3(1.0, 0.0, 1.0);

            bool needLinearToSRGB = false;

            GetPropertiesDataDebug(indexMaterialProperty, result, needLinearToSRGB);
            GetVaryingsDataDebug(indexMaterialProperty, input, result, needLinearToSRGB);
            GetBuiltinDataDebug(indexMaterialProperty, builtinData, result, needLinearToSRGB);
            GetSurfaceDataDebug(indexMaterialProperty, surfaceData, result, needLinearToSRGB);
            GetBSDFDataDebug(indexMaterialProperty, bsdfData, result, needLinearToSRGB);

            // TEMP!
            // For now, the final blit in the backbuffer performs an sRGB write
            // So in the meantime we apply the inverse transform to linear data to compensate.
            if (!needLinearToSRGB)
                result = SRGBToLinear(max(0, result));

            outColor = float4(result, 1.0);
        }
    }

    if (!viewMaterial)
    {
        if (_DebugFullScreenMode == FULLSCREENDEBUGMODE_VALIDATE_DIFFUSE_COLOR || _DebugFullScreenMode == FULLSCREENDEBUGMODE_VALIDATE_SPECULAR_COLOR)
        {
            float3 result = float3(0.0, 0.0, 0.0);

            GetPBRValidatorDebug(surfaceData, result);

            outColor = float4(result, 1.0f);
        }
        else
#endif
        {
#ifdef _SURFACE_TYPE_TRANSPARENT
            uint featureFlags = LIGHT_FEATURE_MASK_FLAGS_TRANSPARENT;
#else
            uint featureFlags = LIGHT_FEATURE_MASK_FLAGS_OPAQUE;
#endif
            float3 diffuseLighting;
            float3 specularLighting;

            LightLoop(V, posInput, preLightData, bsdfData, builtinData, featureFlags, diffuseLighting, specularLighting);

            diffuseLighting *= GetCurrentExposureMultiplier();
            specularLighting *= GetCurrentExposureMultiplier();

#ifdef OUTPUT_SPLIT_LIGHTING
            if (_EnableSubsurfaceScattering != 0 && ShouldOutputSplitLighting(bsdfData))
            {
                outColor = float4(specularLighting, 1.0);
                outDiffuseLighting = float4(TagLightingForSSS(diffuseLighting), 1.0);
            }
            else
            {
                outColor = float4(diffuseLighting + specularLighting, 1.0);
                outDiffuseLighting = 0;
            }
            ENCODE_INTO_SSSBUFFER(surfaceData, posInput.positionSS, outSSSBuffer);
#else
            outColor = ApplyBlendMode(diffuseLighting, specularLighting, builtinData.opacity);
            outColor = EvaluateAtmosphericScattering(posInput, V, outColor);
#endif
#ifdef _WRITE_TRANSPARENT_VELOCITY
            VaryingsPassToPS inputPass = UnpackVaryingsPassToPS(packedInput.vpass);
            bool forceNoMotion = any(unity_MotionVectorsParams.yw == 0.0);
            if (forceNoMotion)
            {
                outVelocity = float4(2.0, 0.0, 0.0, 0.0);
            }
            else
            {
                float2 velocity = CalculateVelocity(inputPass.positionCS, inputPass.previousPositionCS);
                EncodeVelocity(velocity * 0.5, outVelocity);
                outVelocity.zw = 1.0;
            }
#endif
        }
#ifdef DEBUG_DISPLAY
    }
#endif

#ifdef _DEPTHOFFSET_ON
    outputDepth = posInput.deviceDepth;
#endif
}
