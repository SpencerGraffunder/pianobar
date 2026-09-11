/* host_debug_bf3.c — map CommonCrypto blowfish vs reference for several
 * key lengths. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "gcrypt.h"

int main (void) {
	unsigned char plain[16] = "0123456789abcdef";
	int lens[] = { 8, 16, 24, 32, 44, 56 };
	for (int k = 0; k < 6; k++) {
		int len = lens[k];
		unsigned char *key = malloc (len);
		for (int i = 0; i < len; i++) key[i] = (unsigned char) (0x11 * (i + 1));

		gcry_cipher_hd_t h = NULL;
		gcry_cipher_open (&h, GCRY_CIPHER_BLOWFISH, GCRY_CIPHER_MODE_ECB, 0);
		gcry_cipher_setkey (h, key, len);
		unsigned char cipher[16];
		gcry_cipher_encrypt (h, cipher, 16, plain, 16);

		printf ("keylen=%2d key=", len);
		for (int i = 0; i < len; i++) printf ("%02x", key[i]);
		printf ("\n  cc: ");
		for (int i = 0; i < 16; i++) printf ("%02x", cipher[i]);
		printf ("\n");

		gcry_cipher_close (h);
		free (key);
	}
	return 0;
}
