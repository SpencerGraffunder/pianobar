//
// PianoBridging.h — exposes the pianobar C core to Swift.
//
// The C core is the unmodified pianobar backend (src/libpiano/*.c).
// The iOS-specific shims (ios/Shim) replace gcrypt, json-c and curl so
// the code links against Apple frameworks instead.
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

#ifndef PIANO_BRIDGING_H
#define PIANO_BRIDGING_H

#include <string.h>

/* pianobar core */
#include "piano.h"
#include "crypt.h"

/* shim public headers */
#include "gcrypt.h"
#include "json.h"
#include "curl/curl.h"
#include "libavfilter/version.h"
#include "libavformat/version.h"

/* glue helpers for the Swift client (ios/Glue/piano_ios.c) */
#include "piano_ios.h"

#endif /* PIANO_BRIDGING_H */
