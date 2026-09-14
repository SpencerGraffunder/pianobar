/*
 * Glue functions for the iOS app.
 *
 * These are the only additions to the pianobar C core; they exist because
 * Swift cannot conveniently read the fixed-size `char urlPath[1024]`
 * member of PianoRequest_t. Everything else the app does by calling the
 * original, unmodified pianobar API directly.
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed, like the rest of pianobar.
 */

#pragma once

#include "piano.h"

#ifdef __cplusplus
extern "C" {
#endif

/* NUL-terminated copy of the request URL path; caller must free() */
char *PianoIosUrlPathCopy (const PianoRequest_t *req);

/* Set req->responseData to a copy of data (frees previous value).
 * data must be a NUL-terminated C string. */
void PianoIosSetResponseData (PianoRequest_t *req, const char *data);

/* Free req->responseData and set it to NULL. */
void PianoIosFreeResponseData (PianoRequest_t *req);

/* Create-station data type helpers (avoid exposing the anonymous enum to
 * Swift). */
void PianoIosCreateStationFromSong (PianoRequestDataCreateStation_t *d);
void PianoIosCreateStationFromArtist (PianoRequestDataCreateStation_t *d);
void PianoIosCreateStationFromMusicToken (PianoRequestDataCreateStation_t *d);

/* Toggle the QuickMix selection across all non-QuickMix stations: include
 * all if none were included, include none if any were. Operates on the
 * handle's authoritative station list, so it is safe regardless of any
 * Swift-side station snapshot. Call this before PIANO_REQUEST_SET_QUICKMIX
 * (whose request builder reads each station's useQuickMix flag).
 * Returns 1 if all non-QuickMix stations are now included, 0 otherwise. */
int PianoIosToggleQuickMix (PianoHandle_t *ph);

#ifdef __cplusplus
}
#endif
