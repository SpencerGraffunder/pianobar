/*
 * Minimal libgcrypt compatibility shim for iOS.
 *
 * pianobar's libpiano uses libgcrypt only for Blowfish in ECB mode
 * (see src/libpiano/piano.c and src/libpiano/crypt.c). This header
 * declares exactly that subset and gcrypt_impl.c implements it on top
 * of Apple's CommonCrypto, so the original pianobar code can be
 * compiled unmodified on iOS.
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed, like the rest of pianobar.
 */

#ifndef PIANOSIM_GCRYPT_H
#define PIANOSIM_GCRYPT_H

#include <stdbool.h>
#include <stddef.h>
#include <time.h> /* pianobar uses time_t in request.c without including <time.h> */

#ifdef __cplusplus
extern "C" {
#endif

/* like real gcrypt: the handle is a pointer to an opaque struct */
typedef struct _gcry_cipher *gcry_cipher_hd_t;

typedef int gcry_error_t;

#define GPG_ERR_NO_ERROR        0
#define GPG_ERR_NOT_SUPPORTED   1
#define GPG_ERR_CIPHER_ALGO     2

/* value copied from <gcrypt.h> */
#define GCRY_CIPHER_BLOWFISH    7

/* cipher modes (only ECB is supported) */
#define GCRY_CIPHER_MODE_ECB    0
#define GCRY_CIPHER_MODE_CBC    1

gcry_error_t gcry_cipher_open (gcry_cipher_hd_t *hd, int algo, int mode,
                               unsigned int flags);
gcry_error_t gcry_cipher_setkey (gcry_cipher_hd_t hd,
                                 const unsigned char *key, size_t keylen);

/* in == NULL means in-place operation (out holds the input), which is
 * how pianobar calls it */
gcry_error_t gcry_cipher_encrypt (gcry_cipher_hd_t hd,
                                  unsigned char *out, size_t outsize,
                                  const unsigned char *in, size_t insize);
gcry_error_t gcry_cipher_decrypt (gcry_cipher_hd_t hd,
                                  unsigned char *out, size_t outsize,
                                  const unsigned char *in, size_t insize);

void gcry_cipher_close (gcry_cipher_hd_t hd);

#ifdef __cplusplus
}
#endif

#endif /* PIANOSIM_GCRYPT_H */
