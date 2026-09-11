/*
 * piano_ios_glue.h — small helpers for the iOS Swift client.
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#pragma once

#include <piano.h>

/* Return the request's URL path as a C string. (The char[1024] field
 * imports into Swift as a char tuple, which is awkward to read; this
 * gives the Swift side a plain `const char *`.) */
static inline const char *PianoIOSUrlPath (const PianoRequest_t *req)
{
    return req->urlPath;
}
