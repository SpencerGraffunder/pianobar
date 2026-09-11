/* host_debug_bf2.c — check if CommonCrypto blowfish key schedule is
 * sensitive to the bytes adjacent to the key buffer (OOB read test). */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "gcrypt.h"

static const unsigned char realkey[16] = {
	0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
	0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
};
static const unsigned char plain[16] = "0123456789abcdef";
static const unsigned char expect[16] = {
	0x46, 0xef, 0xea, 0xba, 0x4c, 0x1a, 0xca, 0xcf,
	0xe4, 0x1c, 0x13, 0x19, 0x15, 0x0f, 0x9f, 0x79
};

static void run (const char *label, const unsigned char *key) {
	gcry_cipher_hd_t h = NULL;
	gcry_cipher_open (&h, GCRY_CIPHER_BLOWFISH, GCRY_CIPHER_MODE_ECB, 0);
	gcry_cipher_setkey (h, key, 16);
	unsigned char cipher[16];
	gcry_cipher_encrypt (h, cipher, 16, plain, 16);
	printf ("%s: ", label);
	for (int i = 0; i < 16; i++) printf ("%02x", cipher[i]);
	printf ("  %s\n", memcmp (cipher, expect, 16) == 0 ? "OK" : "MISMATCH");
	gcry_cipher_close (h);
}

int main (void) {
	/* 1. static const (as in the XCTest) */
	run ("static  ", realkey);

	/* 2. heap, exactly 16 bytes */
	unsigned char *hk = malloc (16);
	memcpy (hk, realkey, 16);
	run ("heap    ", hk);
	free (hk);

	/* 3. heap with 8 extra zero bytes before the key */
	unsigned char *pz = malloc (24);
	memset (pz, 0, 24);
	memcpy (pz + 8, realkey, 16);
	run ("zeroL   ", pz + 8);
	free (pz);

	/* 4. heap with 8 extra 0xAA bytes before the key */
	unsigned char *pa = malloc (24);
	memset (pa, 0xaa, 24);
	memcpy (pa + 8, realkey, 16);
	run ("aaL     ", pa + 8);
	free (pa);

	/* 5. stack buffer with adjacent 'X' bytes */
	char stackbuf[40];
	memset (stackbuf, 'X', sizeof stackbuf);
	unsigned char *ks = (unsigned char *) (stackbuf + 12);
	memcpy (ks, realkey, 16);
	run ("stackX  ", ks);

	/* 6. heap with 8 extra 0x7E bytes AFTER the key */
	unsigned char *pt = malloc (24);
	memset (pt, 0x7e, 24);
	memcpy (pt, realkey, 16);
	run ("7eR     ", pt);
	free (pt);

	return 0;
}
