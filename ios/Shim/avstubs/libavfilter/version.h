/*
 * Stub for <libavfilter/version.h> used by pianobar's src/config.h.
 *
 * config.h only uses the version macros to feature-detect ffmpeg
 * capabilities (which the iOS build never uses — playback is handled
 * by AVPlayer). Providing plausible version numbers lets the original
 * config.h compile unmodified on iOS.
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#ifndef PIANOSIM_LIBAVFILTER_VERSION_H
#define PIANOSIM_LIBAVFILTER_VERSION_H

#ifndef AV_VERSION_INT
#define AV_VERSION_INT(a, b, c) ((a) << 16 | (b) << 8 | (c))
#endif

#define LIBAVFILTER_VERSION_MAJOR 10
#define LIBAVFILTER_VERSION_MINOR 0
#define LIBAVFILTER_VERSION_MICRO 100
#define LIBAVFILTER_VERSION_INT AV_VERSION_INT(10, 0, 100)

#endif /* PIANOSIM_LIBAVFILTER_VERSION_H */
