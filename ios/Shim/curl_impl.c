/*
 * libcurl shim implementation (URL-encoding helpers only).
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#include "curl/curl.h"

#include <stdlib.h>
#include <string.h>

struct Curl_ {
	int dummy;
};

void curl_global_init (int flags) {
	(void) flags;
}

void curl_global_cleanup (void) {
}

CURL *curl_easy_init (void) {
	return calloc (1, sizeof (struct Curl_));
}

CURLcode curl_easy_cleanup (CURL *curl) {
	free (curl);
	return CURLE_OK;
}

CURLcode curl_easy_reset (CURL *curl) {
	(void) curl;
	return CURLE_OK;
}

static int is_unreserved (unsigned char c) {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
	       (c >= '0' && c <= '9') ||
	       c == '-' || c == '.' || c == '_' || c == '~';
}

char *curl_easy_escape (CURL *curl, const char *string, int length) {
	(void) curl;

	if (string == NULL)
		return NULL;
	/* length 0 means "compute strlen" in libcurl semantics */
	if (length <= 0)
		length = (int) strlen (string);

	char *out = malloc ((size_t) length * 3 + 1);
	if (out == NULL)
		return NULL;

	char *p = out;
	const char *hexdigits = "0123456789ABCDEF";

	for (int i = 0; i < length; i++) {
		unsigned char c = (unsigned char) string[i];
		if (is_unreserved (c)) {
			*p++ = (char) c;
		} else {
			*p++ = '%';
			*p++ = hexdigits[c >> 4];
			*p++ = hexdigits[c & 0xF];
		}
	}
	*p = '\0';
	return out;
}

void curl_free (void *ptr) {
	free (ptr);
}

const char *curl_easy_strerror (CURLcode code) {
	switch (code) {
		case CURLE_OK:
			return "No error";
		case CURLE_UNSUPPORTED_PROTOCOL:
			return "Unsupported protocol";
		case CURLE_URL_MALFORMAT:
			return "URL malformed";
		case CURLE_COULDNT_RESOLVE_PROXY:
			return "Could not resolve proxy";
		case CURLE_COULDNT_RESOLVE_HOST:
			return "Could not resolve host";
		case CURLE_COULDNT_CONNECT:
			return "Could not connect to server";
		case CURLE_WEIRD_SERVER_REPLY:
			return "Weird server reply";
		case CURLE_READ_ERROR:
			return "Read error";
		case CURLE_OPERATION_TIMEDOUT:
			return "Operation timed out";
		case CURLE_SSL_CONNECT_ERROR:
			return "SSL connect error";
		case CURLE_GOT_NOTHING:
			return "Empty reply from server";
		case CURLE_SEND_ERROR:
			return "Send error";
		case CURLE_RECV_ERROR:
			return "Receive error";
		case CURLE_ABORTED_BY_CALLBACK:
			return "Aborted by callback";
		case CURLE_OUT_OF_MEMORY:
			return "Out of memory";
		case CURLE_FAILED_INIT:
			return "Failed initialization";
		default:
			return "Unknown curl error";
	}
}
