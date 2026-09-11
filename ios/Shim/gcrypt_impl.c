/*
 * Blowfish-ECB implementation of the gcrypt shim, using Apple's
 * CommonCrypto (available on iOS without extra libraries).
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#include "gcrypt.h"

#include <stdlib.h>
#include <string.h>

#include <CommonCrypto/CommonCryptor.h>

struct _gcry_cipher {
	unsigned char key[56];
	size_t keylen;
};

gcry_error_t gcry_cipher_open (gcry_cipher_hd_t *hd, int algo, int mode,
                               unsigned int flags) {
	(void) flags;

	if (hd == NULL)
		return GPG_ERR_NOT_SUPPORTED;
	if (algo != GCRY_CIPHER_BLOWFISH)
		return GPG_ERR_NOT_SUPPORTED;
	if (mode != GCRY_CIPHER_MODE_ECB)
		return GPG_ERR_NOT_SUPPORTED;

	*hd = calloc (1, sizeof (**hd));
	return (*hd != NULL) ? GPG_ERR_NO_ERROR : GPG_ERR_NOT_SUPPORTED;
}

gcry_error_t gcry_cipher_setkey (gcry_cipher_hd_t hd,
                                 const unsigned char *key, size_t keylen) {
	if (hd == NULL || key == NULL)
		return GPG_ERR_NOT_SUPPORTED;
	/* blowfish accepts 32..448 bit keys in 8 bit steps; CommonCrypto
	 * requires 40..448 bits, so enforce at least 5 bytes to be safe */
	if (keylen < 5 || keylen > 56)
		return GPG_ERR_NOT_SUPPORTED;

	memcpy (hd->key, key, keylen);
	hd->keylen = keylen;
	return GPG_ERR_NO_ERROR;
}

static gcry_error_t blowfish_ecb (CCOperation op, gcry_cipher_hd_t hd,
                                  unsigned char *out, size_t outsize,
                                  const unsigned char *in, size_t insize) {
	if (hd == NULL || out == NULL)
		return GPG_ERR_NOT_SUPPORTED;

	/* pianobar always operates in-place (in == NULL) */
	if (in == NULL) {
		in = out;
		insize = outsize;
	}

	if (insize == 0 || insize % 8 != 0)
		return GPG_ERR_NOT_SUPPORTED;
	if (insize > outsize)
		return GPG_ERR_NOT_SUPPORTED;

	CCCryptorStatus st = CCCrypt (op, kCCAlgorithmBlowfish, kCCOptionECBMode,
	                              hd->key, hd->keylen, NULL,
	                              in, insize, out, outsize, NULL);
	return (st == kCCSuccess) ? GPG_ERR_NO_ERROR : GPG_ERR_CIPHER_ALGO;
}

gcry_error_t gcry_cipher_encrypt (gcry_cipher_hd_t hd,
                                  unsigned char *out, size_t outsize,
                                  const unsigned char *in, size_t insize) {
	return blowfish_ecb (kCCEncrypt, hd, out, outsize, in, insize);
}

gcry_error_t gcry_cipher_decrypt (gcry_cipher_hd_t hd,
                                  unsigned char *out, size_t outsize,
                                  const unsigned char *in, size_t insize) {
	return blowfish_ecb (kCCDecrypt, hd, out, outsize, in, insize);
}

void gcry_cipher_close (gcry_cipher_hd_t hd) {
	if (hd == NULL)
		return;
	memset (hd, 0, sizeof (*hd));
	free (hd);
}
