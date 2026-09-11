/*
 * Minimal libcurl shim for iOS.
 *
 * libpiano only uses libcurl for URL-encoding the auth token
 * (curl_easy_escape / curl_free in src/libpiano/request.c). The actual
 * HTTP transfer is done by the iOS app (PianoHTTP.swift over
 * URLSession), so this shim only provides the encoding helpers.
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#ifndef PIANOSIM_CURL_H
#define PIANOSIM_CURL_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Curl_ CURL;

typedef enum {
	CURLE_OK = 0,
	CURLE_UNSUPPORTED_PROTOCOL = 1,
	CURLE_URL_MALFORMAT = 3,
	CURLE_COULDNT_RESOLVE_PROXY = 5,
	CURLE_COULDNT_RESOLVE_HOST = 6,
	CURLE_COULDNT_CONNECT = 7,
	CURLE_WEIRD_SERVER_REPLY = 8,
	CURLE_READ_ERROR = 26,
	CURLE_OPERATION_TIMEDOUT = 28,
	CURLE_SSL_CONNECT_ERROR = 35,
	CURLE_GOT_NOTHING = 52,
	CURLE_SEND_ERROR = 55,
	CURLE_RECV_ERROR = 56,
	CURLE_ABORTED_BY_CALLBACK = 42,
	CURLE_OUT_OF_MEMORY = 16,
	CURLE_FAILED_INIT = 44
} CURLcode;

#define CURL_GLOBAL_DEFAULT 3

void curl_global_init (int flags);
void curl_global_cleanup (void);

CURL *curl_easy_init (void);
CURLcode curl_easy_cleanup (CURL *curl);
CURLcode curl_easy_reset (CURL *curl);

/* percent-encode string (RFC 3986 unreserved characters pass through),
 * result must be freed with curl_free() */
char *curl_easy_escape (CURL *curl, const char *string, int length);
void curl_free (void *ptr);
const char *curl_easy_strerror (CURLcode code);

#ifdef __cplusplus
}
#endif

#endif /* PIANOSIM_CURL_H */
