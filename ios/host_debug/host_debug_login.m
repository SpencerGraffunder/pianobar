/*
 * host_debug_login.m — reproduce the full 2-step Pandora login on the macOS
 * host using EXACTLY the same code path as the iOS app:
 *
 *   - unmodified pianobar C core (src/libpiano)
 *   - our gcrypt shim (CommonCrypto blowfish)
 *   - our json shim (JSONSerialization)
 *   - our curl shim (URL escaping)
 *   - URLSession transport (identical to PianoClient.performHTTP)
 *
 * Purpose: separate a *protocol bug* in our request (reproduces here) from
 * an *account-specific* server rejection (a specific non-zero code, e.g.
 * 1002/1011/1012/1004). Run with dummy credentials by default; override with
 * PB_USER / PB_PASS env vars.
 *
 * Build (from ios/host_debug):
 *   clang -fobjc-arc \
 *     -I ../Shim -I ../Glue -I ../../src -I ../../src/libpiano \
 *     -o host_login host_debug_login.m \
 *     ../../src/libpiano/*.c \
 *     ../Shim/gcrypt_impl.c ../Shim/json_impl.m ../Shim/curl_impl.c \
 *     ../Glue/piano_ios.c \
 *     -lSecurity -framework Foundation -framework CoreFoundation
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "piano.h"

/* POST `body` (NUL-terminated C string) to host:port+path over URLSession —
 * the same transport the iOS app uses. Returns 1 if the server answered
 * (fills *outBody (caller frees) and *outStatus), 0 on transport failure. */
static int doPost (const char *host, const char *path, int secure,
		const char *body, char **outBody, long *outStatus) {
	@autoreleasepool {
		NSString *scheme = secure ? @"https" : @"http";
		NSString *port = secure ? @"443" : @"80";
		NSString *pathNS = [NSString stringWithUTF8String:path];
		NSString *urlStr = [NSString stringWithFormat:
				@"%@://%@:%@%@", scheme, [NSString stringWithUTF8String:host], port, pathNS];
		NSURL *url = [NSURL URLWithString:urlStr];
		if (url == nil) { fprintf (stderr, "bad url: %s\n", urlStr.UTF8String); return 0; }

	 NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:url];
		rq.HTTPMethod = @"POST";
		[rq setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
		[rq setValue:@"pianobar-ios/1.0" forHTTPHeaderField:@"User-Agent"];
		rq.HTTPBody = [NSData dataWithBytes:body
				length:(body ? (unsigned int)strlen (body) : 0)];

		__block NSData *respData = nil;
		__block long status = 0;
		__block NSError *err = nil;
		dispatch_semaphore_t sem = dispatch_semaphore_create (0);
		NSURLSessionDataTask *t = [[NSURLSession sharedSession]
				dataTaskWithRequest:rq
				 completionHandler:^(NSData *d, NSURLResponse *r, NSError *e){
			respData = d;
			if ([r isKindOfClass:[NSHTTPURLResponse class]])
				status = ((NSHTTPURLResponse *) r).statusCode;
			err = e;
			dispatch_semaphore_signal (sem);
		}];
		[t resume];
		if (dispatch_semaphore_wait (sem,
				dispatch_time (DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) != 0) {
			fprintf (stderr, "POST timed out\n");
			return 0;
		}
		if (err != nil) {
			fprintf (stderr, "transport error: %s\n", err.localizedDescription.UTF8String);
			return 0;
		}
		*outStatus = status;
		if (respData != nil) {
			*outBody = malloc (respData.length + 1);
			memcpy (*outBody, respData.bytes, respData.length);
			(*outBody)[respData.length] = '\0';
		} else {
			*outBody = strdup ("");
		}
		return 1;
	}
}

/* PianoErrorToStr asserts on PIANO_RET_CONTINUE_REQUEST (a control value,
 * not an error) — never pass it. */
static const char *retStr (PianoReturn_t rc) {
	if (rc == PIANO_RET_CONTINUE_REQUEST) return "CONTINUE_REQUEST";
	if (rc == PIANO_RET_OK) return "OK";
	return PianoErrorToStr (rc);
}

static void hexdump (const char *s, size_t max) {
	size_t len = strlen (s);
	size_t n = len < max ? len : max;
	for (size_t i = 0; i < n; i++) printf ("%02x", (unsigned char) s[i]);
	if (len > max) printf ("...(%zu bytes total)", len);
	printf ("\n");
}

int main (void) {
	const char *user = getenv ("PB_USER");
	if (user == NULL || *user == '\0') user = "pb_host_test";
	const char *pass = getenv ("PB_PASS");
	if (pass == NULL || *pass == '\0') pass = "pb_host_test";

	PianoHandle_t ph;
	PianoReturn_t rc = PianoInit (&ph,
			"android",
			"AC7IBG09A3DTSYM4R41UJWL07VLN8JI7",
			"android-generic",
			"R=U!LH$O2B#",
			"6#26FRL$ZWD");
	if (rc != PIANO_RET_OK) {
		fprintf (stderr, "PianoInit failed: %s\n", PianoErrorToStr (rc));
		return 2;
	}

	char *u = strdup (user);
	char *p = strdup (pass);
	PianoRequestDataLogin_t login;
	memset (&login, 0, sizeof (login));
	login.user = u;
	login.password = p;
	login.step = 0;

	/* ---- STEP 0: partnerLogin ---- */
	printf ("=== STEP 0: auth.partnerLogin ===\n");
	PianoRequest_t req;
	memset (&req, 0, sizeof (req));
	req.data = &login;
	rc = PianoRequest (&ph, &req, PIANO_REQUEST_LOGIN);
	if (rc != PIANO_RET_OK) {
		fprintf (stderr, "PianoRequest(step0): %s\n", PianoErrorToStr (rc));
		return 2;
	}
	printf ("URL : https://tuner.pandora.com%s\n", req.urlPath);
	printf ("body: %s\n", req.postData ? req.postData : "(null)");

	char *resp = NULL;
	long status = 0;
	if (!doPost ("tuner.pandora.com", req.urlPath, req.secure,
			req.postData, &resp, &status))
		return 3;
	printf ("resp: HTTP %ld\n%s\n", status, resp);

	req.responseData = resp;
	rc = PianoResponse (&ph, &req);
	printf ("PianoResponse(step0): %s (code %d)\n",
			retStr (rc), (int) rc);
	if (rc != PIANO_RET_CONTINUE_REQUEST) {
		fprintf (stderr, "step 0 failed — cannot proceed\n");
		return 4;
	}
	PianoDestroyRequest (&req);
	free (resp);
	printf ("partnerAuthToken: %s\n", ph.partner.authToken ? ph.partner.authToken : "(null)");
	printf ("partnerId       : %u\n", ph.partner.id);
	printf ("\n");

	/* ---- STEP 1: userLogin ---- */
	printf ("=== STEP 1: auth.userLogin (account: %s) ===\n", user);
	memset (&req, 0, sizeof (req));
	req.data = &login;
	rc = PianoRequest (&ph, &req, PIANO_REQUEST_LOGIN);
	if (rc != PIANO_RET_OK) {
		fprintf (stderr, "PianoRequest(step1): %s\n", PianoErrorToStr (rc));
		return 2;
	}
	printf ("URL : https://tuner.pandora.com%s\n", req.urlPath);
	printf ("body(encrypted hex, first 96): ");
	hexdump (req.postData ? req.postData : "", 96);

	resp = NULL;
	status = 0;
	if (!doPost ("tuner.pandora.com", req.urlPath, req.secure,
			req.postData, &resp, &status))
		return 3;
	printf ("resp: HTTP %ld\n%s\n", status, resp);

	req.responseData = resp;
	rc = PianoResponse (&ph, &req);
	printf ("PianoResponse(step1): %s (code %d)\n",
			retStr (rc), (int) rc);

	PianoDestroyRequest (&req);
	free (resp);
	free (u);
	free (p);
	PianoDestroy (&ph);
	return 0;
}
