/* host_debug.c — quick host-side debug of the shims (macOS build). */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "gcrypt.h"

int main (void) {
	unsigned char key[16] = {
		0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
		0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
	};
	unsigned char plain[16] = "0123456789abcdef";
	gcry_cipher_hd_t h = NULL;
	gcry_cipher_open (&h, GCRY_CIPHER_BLOWFISH, GCRY_CIPHER_MODE_ECB, 0);
	gcry_cipher_setkey (h, key, 16);
	unsigned char cipher[16];
	gcry_cipher_encrypt (h, cipher, 16, plain, 16);
	printf ("shim:   ");
	for (int i = 0; i < 16; i++) printf ("%02x", cipher[i]);
	printf ("\nexpect: 46efeaba4c1accafe41c1319150f9f79\n");
	return 0;
}
