#include "lcms2.h"
#include <stdint.h>
#include <string.h>

#ifdef _WIN32
#define PV_EXPORT __declspec(dllexport)
#else
#define PV_EXPORT __attribute__((visibility("default")))
#endif

static cmsHPROFILE pv_open(cmsContext ctx, const uint8_t *data, uint32_t length) {
    if (length == 0) return cmsCreate_sRGBProfileTHR(ctx);
    if (data == NULL || length < 132 || length > 8 * 1024 * 1024) return NULL;
    return cmsOpenProfileFromMemTHR(ctx, data, length);
}

PV_EXPORT int32_t pv_farbe_profil(const uint8_t *data, uint32_t length) {
    cmsContext ctx = cmsCreateContext(NULL, NULL);
    if (!ctx) return 0;
    cmsHPROFILE profile = pv_open(ctx, data, length);
    int result = 0;
    if (profile) {
        const cmsColorSpaceSignature space = cmsGetColorSpace(profile);
        if (space == cmsSigRgbData) result = 1;
        if (space == cmsSigCmykData) result = 2;
        if (space == cmsSigGrayData) result = 3;
        if (cmsGetDeviceClass(profile) == cmsSigLinkClass) result = 0;
        cmsCloseProfile(profile);
    }
    cmsDeleteContext(ctx);
    return result;
}

PV_EXPORT int32_t pv_farbe_transform(const uint8_t *input, uint8_t *output, uint32_t pixels,
    const uint8_t *input_profile, uint32_t input_length,
    const uint8_t *output_profile, uint32_t output_length,
    const uint8_t *proof_profile, uint32_t proof_length, uint32_t flags, uint32_t intent) {
    if (!input || !output || pixels > 32000000 || intent > 3 || flags > 7) return 1;
    cmsContext ctx = cmsCreateContext(NULL, NULL);
    if (!ctx) return 2;
    cmsHPROFILE in = pv_open(ctx, input_profile, input_length);
    cmsHPROFILE out = pv_open(ctx, output_profile, output_length);
    cmsHPROFILE proof = NULL;
    cmsHTRANSFORM transform = NULL;
    int result = 2;
    if (!in || !out || cmsGetColorSpace(in) != cmsSigRgbData || cmsGetColorSpace(out) != cmsSigRgbData) goto cleanup;
    if (flags & 3) {
        if (proof_length == 0) goto cleanup;
        proof = pv_open(ctx, proof_profile, proof_length);
        if (!proof) goto cleanup;
        cmsUInt16Number alarm[cmsMAXCHANNELS] = { 0 };
        alarm[0] = 65535; alarm[2] = 65535;
        cmsSetAlarmCodesTHR(ctx, alarm);
        cmsUInt32Number cms_flags = cmsFLAGS_SOFTPROOFING | cmsFLAGS_BLACKPOINTCOMPENSATION;
        if (flags & 2) cms_flags |= cmsFLAGS_GAMUTCHECK;
        transform = cmsCreateProofingTransformTHR(ctx, in, TYPE_RGB_8, out, TYPE_RGB_8, proof, intent,
            flags & 4 ? INTENT_ABSOLUTE_COLORIMETRIC : INTENT_RELATIVE_COLORIMETRIC, cms_flags);
    } else {
        transform = cmsCreateTransformTHR(ctx, in, TYPE_RGB_8, out, TYPE_RGB_8, intent, cmsFLAGS_BLACKPOINTCOMPENSATION);
    }
    if (!transform) goto cleanup;
    cmsDoTransform(transform, input, output, pixels);
    result = 0;
cleanup:
    if (transform) cmsDeleteTransform(transform);
    if (proof) cmsCloseProfile(proof);
    if (out) cmsCloseProfile(out);
    if (in) cmsCloseProfile(in);
    cmsDeleteContext(ctx);
    return result;
}

PV_EXPORT uint32_t pv_farbe_standardprofil(uint32_t typ, uint8_t *output, uint32_t capacity) {
    cmsContext ctx = cmsCreateContext(NULL, NULL);
    if (!ctx) return 0;
    cmsHPROFILE profile = NULL;
    if (typ == 0) profile = cmsCreate_sRGBProfileTHR(ctx);
    if (typ == 1) {
        cmsCIExyY white = { 0.3127, 0.3290, 1.0 };
        cmsCIExyYTRIPLE primaries = { { 0.68, 0.32, 1.0 }, { 0.265, 0.69, 1.0 }, { 0.15, 0.06, 1.0 } };
        const double parameters[5] = { 2.4, 1.0 / 1.055, 0.055 / 1.055, 1.0 / 12.92, 0.04045 };
        cmsToneCurve *curve = cmsBuildParametricToneCurve(ctx, 4, parameters);
        if (curve) {
            cmsToneCurve *curves[3] = { curve, curve, curve };
            profile = cmsCreateRGBProfileTHR(ctx, &white, &primaries, curves);
            cmsFreeToneCurve(curve);
        }
    }
    uint32_t required = 0;
    if (profile) {
        cmsSaveProfileToMem(profile, NULL, &required);
        if (output && capacity >= required) cmsSaveProfileToMem(profile, output, &capacity);
        cmsCloseProfile(profile);
    }
    cmsDeleteContext(ctx);
    return required;
}
