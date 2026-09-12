/*
 * PianoTests.m — unit tests for the pianobar C core and the iOS shims.
 *
 * These tests run on the iOS simulator via XCTest (see ios/project.yml).
 * They exercise:
 *   - the gcrypt shim (CommonCrypto blowfish-ECB, incl. in-place calls
 *     and a known-answer vector generated with OpenSSL)
 *   - the json-c shim (JSONSerialization-based)
 *   - the unmodified pianobar core (PianoInit/PianoDestroy, linked list
 *     API, error strings, station lookup)
 *   - the iOS glue helpers (ios/Glue/piano_ios.c)
 *
 * Note: XCTest macros take ObjC objects, so C-pointer results are
 * asserted with explicit != NULL / == NULL comparisons (ARC-safe).
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#import <XCTest/XCTest.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "gcrypt.h"
#include "json.h"
#include "piano.h"
#include "piano_ios.h"

@interface PianoTests : XCTestCase
@end

@implementation PianoTests

#pragma mark - gcrypt shim (blowfish-ECB via CommonCrypto)

- (void)testBlowfishOpenSetkey
{
    gcry_cipher_hd_t h = NULL;
    XCTAssertFalse(gcry_cipher_open(&h, GCRY_CIPHER_BLOWFISH,
                                   GCRY_CIPHER_MODE_ECB, 0));
    XCTAssertTrue(h != NULL);
    unsigned char key[16] = { 0 };
    XCTAssertFalse(gcry_cipher_setkey(h, key, sizeof key));
    gcry_cipher_close(h);
}

/*
 * Known-answer test.
 * key     = 00112233445566778899aabbccddeeff
 * plain   = "0123456789abcdef" (16 ASCII bytes)
 * cipher  = 46efeaba4c1accafe41c1319150f9f79
 *
 * Vector generated with:
 *   printf '0123456789abcdef' | openssl enc -bf-ecb -K 00112233445566778899aabbccddeeff -nosalt
 */
- (void)testBlowfishKnownAnswerVector
{
    static const unsigned char key[16] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
    };
    static const unsigned char plain[16] = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    };
    /* generated programmatically (pycryptodome + CommonCrypto agree) */
    static const unsigned char expect[16] = {
        0x46, 0xef, 0xea, 0xba, 0x4c, 0x1a, 0xcc, 0xaf,
        0xe4, 0x1c, 0x13, 0x19, 0x15, 0x0f, 0x9f, 0x79
    };

    gcry_cipher_hd_t h = NULL;
    XCTAssertFalse(gcry_cipher_open(&h, GCRY_CIPHER_BLOWFISH,
                                   GCRY_CIPHER_MODE_ECB, 0));
    XCTAssertFalse(gcry_cipher_setkey(h, key, sizeof key));

    unsigned char cipher[16] = { 0 };
    XCTAssertFalse(gcry_cipher_encrypt(h, cipher, sizeof cipher, plain,
                                      sizeof plain));
    XCTAssertEqual(0, memcmp(cipher, expect, 16));

    unsigned char back[16] = { 0 };
    XCTAssertFalse(gcry_cipher_decrypt(h, back, sizeof back, cipher,
                                      sizeof cipher));
    XCTAssertEqual(0, memcmp(back, plain, 16));

    gcry_cipher_close(h);
}

/*
 * pianobar's crypt.c uses in-place calls: out == buffer, in == NULL,
 * insize == 0 (see the gcrypt.h shim contract).
 */
- (void)testBlowfishInPlace
{
    unsigned char key[16];
    memset(key, 0x42, sizeof key);

    unsigned char orig[16];
    for (int i = 0; i < 16; i++) orig[i] = (unsigned char)(i * 7 + 1);

    gcry_cipher_hd_t h = NULL;
    XCTAssertFalse(gcry_cipher_open(&h, GCRY_CIPHER_BLOWFISH,
                                   GCRY_CIPHER_MODE_ECB, 0));
    XCTAssertFalse(gcry_cipher_setkey(h, key, sizeof key));

    unsigned char buf[16];
    memcpy(buf, orig, sizeof buf);

    XCTAssertFalse(gcry_cipher_encrypt(h, buf, sizeof buf, NULL, 0));
    XCTAssertNotEqual(0, memcmp(buf, orig, 16));

    XCTAssertFalse(gcry_cipher_decrypt(h, buf, sizeof buf, NULL, 0));
    XCTAssertEqual(0, memcmp(buf, orig, 16));

    gcry_cipher_close(h);
}

/* Blowfish accepts key lengths 8..56 bytes; 32 must round-trip. */
- (void)testBlowfishLongKeyRoundTrip
{
    unsigned char key[32];
    for (int i = 0; i < 32; i++) key[i] = (unsigned char)(i + 1);

    unsigned char plain[16] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };

    gcry_cipher_hd_t h = NULL;
    XCTAssertFalse(gcry_cipher_open(&h, GCRY_CIPHER_BLOWFISH,
                                   GCRY_CIPHER_MODE_ECB, 0));
    XCTAssertFalse(gcry_cipher_setkey(h, key, sizeof key));

    unsigned char cipher[16] = { 0 };
    XCTAssertFalse(gcry_cipher_encrypt(h, cipher, sizeof cipher, plain,
                                      sizeof plain));
    unsigned char back[16] = { 0 };
    XCTAssertFalse(gcry_cipher_decrypt(h, back, sizeof back, cipher,
                                      sizeof cipher));
    XCTAssertEqual(0, memcmp(back, plain, 16));

    gcry_cipher_close(h);
}

#pragma mark - json-c shim (JSONSerialization-based)

- (void)testJsonBuildSerializeParse
{
    json_object *user = json_object_new_object();
    json_object_object_add(user, "authToken", json_object_new_string("tok123"));
    json_object_object_add(user, "listenerId", json_object_new_string("42"));

    json_object *resp = json_object_new_object();
    json_object_object_add(resp, "userLogin", user);
    json_object_object_add(resp, "step", json_object_new_int(2));

    const char *text = json_object_to_json_string(resp);
    XCTAssertTrue(text != NULL);

    json_object *parsed = json_tokener_parse(text);
    XCTAssertTrue(parsed != NULL);

    json_object *ul = NULL;
    XCTAssertTrue(json_object_object_get_ex(parsed, "userLogin", &ul));
    XCTAssertTrue(ul != NULL);

    json_object *auth = NULL;
    XCTAssertTrue(json_object_object_get_ex(ul, "authToken", &auth));
    XCTAssertEqualObjects([NSString stringWithUTF8String:json_object_get_string(auth)],
                          @"tok123");

    json_object *step = NULL;
    XCTAssertTrue(json_object_object_get_ex(parsed, "step", &step));
    XCTAssertEqual(json_object_get_int(step), 2);

    json_object_put(parsed);
}

- (void)testJsonTypes
{
    json_object *b = json_object_new_boolean(1);
    XCTAssertEqual(json_object_get_boolean(b), 1);
    XCTAssertTrue(json_object_is_type(b, json_type_boolean));

    json_object *i = json_object_new_int(-42);
    XCTAssertEqual(json_object_get_int(i), -42);
    XCTAssertTrue(json_object_is_type(i, json_type_int));

    json_object *d = json_object_new_double(3.5);
    XCTAssertTrue(fabs(json_object_get_double(d) - 3.5) < 0.0001);
    XCTAssertTrue(json_object_is_type(d, json_type_double));

    json_object *s = json_object_new_string("hello");
    XCTAssertEqualObjects([NSString stringWithUTF8String:json_object_get_string(s)],
                          @"hello");
    XCTAssertTrue(json_object_is_type(s, json_type_string));
}

/*
 * Real json-c semantics the pianobar core relies on (verified against
 * json-c 0.13+): numeric getters parse numeric STRINGS, and booleans
 * render as "true"/"false". Pandora returns numeric fields as strings
 * (e.g. "partnerId":"42"); the core does
 * `ph->partner.id = json_object_get_int(partnerId)` and the userLogin
 * URL embeds `partner_id=%i` — a 0 there makes Pandora answer
 * {"stat":"fail","code":0} → "Internal error". Regression tests for
 * the shim that broke these.
 */
- (void)testJsonGetIntParsesNumericStrings
{
    json_object *s42 = json_object_new_string("42");
    XCTAssertEqual(json_object_get_int(s42), 42);

    json_object *sBig = json_object_new_string("1695024441000");
    XCTAssertEqual(json_object_get_int(sBig), (int) 1695024441000L);

    json_object *sFloat = json_object_new_string("42.7");
    XCTAssertEqual(json_object_get_int(sFloat), 42);

    json_object *sJunk = json_object_new_string("abc");
    XCTAssertEqual(json_object_get_int(sJunk), 0);

    /* NULL-ish / non-numeric still safe */
    json_object *nullObj = json_object_new_null();
    XCTAssertEqual(json_object_get_int(nullObj), 0);
}

- (void)testJsonGetDoubleParsesNumericStrings
{
    json_object *s = json_object_new_string("42.75");
    XCTAssertTrue(fabs(json_object_get_double(s) - 42.75) < 0.0001);

    json_object *sInt = json_object_new_string("7");
    XCTAssertTrue(fabs(json_object_get_double(sInt) - 7.0) < 0.0001);

    json_object *sJunk = json_object_new_string("nope");
    XCTAssertEqual(json_object_get_double(sJunk), 0.0);
}

- (void)testJsonGetStringOnBoolean
{
    json_object *t = json_object_new_boolean(1);
    XCTAssertEqualObjects([NSString stringWithUTF8String:json_object_get_string(t)],
                          @"true");
    json_object *f = json_object_new_boolean(0);
    XCTAssertEqualObjects([NSString stringWithUTF8String:json_object_get_string(f)],
                          @"false");
}

/* Shape of a real Pandora partnerLogin (step 0) response: numeric fields
 * arrive as strings. */
- (void)testJsonParsePandoraPartnerLoginResponse
{
    const char *json =
        "{\"stat\":\"ok\",\"result\":{\"stationSkipLimit\":6,"
        "\"partnerId\":\"42\",\"partnerAuthToken\":\"VAyOF96RBRvkcwB9/d3AQLfg==\","
        "\"urls\":{\"autoComplete\":\"http://autocomplete-sc.pandora.com/search\"},"
        "\"syncTime\":\"8062f143853f7f7237cf73d92ef72078\","
        "\"stationSkipUnit\":\"hour\"}}";

    json_object *j = json_tokener_parse(json);
    XCTAssertTrue(j != NULL);
    json_object *result = NULL;
    XCTAssertTrue(json_object_object_get_ex(j, "result", &result));
    json_object *pid = NULL;
    XCTAssertTrue(json_object_object_get_ex(result, "partnerId", &pid));
    /* This is the exact core call that used to yield 0. */
    XCTAssertEqual(json_object_get_int(pid), 42);

    json_object_put(j);
}

- (void)testJsonArray
{
    json_object *arr = json_object_new_array();
    XCTAssertEqual(json_object_array_length(arr), 0u);

    json_object_array_add(arr, json_object_new_string("x"));
    json_object_array_add(arr, json_object_new_string("y"));
    json_object_array_add(arr, json_object_new_int(7));

    XCTAssertEqual(json_object_array_length(arr), 3u);

    json_object *y = json_object_array_get_idx(arr, 1);
    XCTAssertEqualObjects([NSString stringWithUTF8String:json_object_get_string(y)],
                          @"y");

    json_object *seven = json_object_array_get_idx(arr, 2);
    XCTAssertEqual(json_object_get_int(seven), 7);

    XCTAssertTrue(json_object_array_get_idx(arr, 99) == NULL);
}

/* Shape of a real Pandora userLogin step-2 response. */
- (void)testJsonParsePandoraLoginResponse
{
    const char *json =
        "{\"userLogin\":{\"user\":{\"authToken\":\"tok123\","
        "\"listenerId\":\"42\"},\"step\":2,\"success\":true}}";

    json_object *parsed = json_tokener_parse(json);
    XCTAssertTrue(parsed != NULL);

    json_object *ul = NULL;
    XCTAssertTrue(json_object_object_get_ex(parsed, "userLogin", &ul));

    json_object *user = NULL;
    XCTAssertTrue(json_object_object_get_ex(ul, "user", &user));

    json_object *tok = NULL;
    XCTAssertTrue(json_object_object_get_ex(user, "authToken", &tok));
    XCTAssertEqualObjects([NSString stringWithUTF8String:json_object_get_string(tok)],
                          @"tok123");

    /* "success" lives inside userLogin in this response shape */
    json_object *ok = NULL;
    XCTAssertTrue(json_object_object_get_ex(ul, "success", &ok));
    XCTAssertEqual(json_object_get_boolean(ok), 1);
}

- (void)testJsonParseInvalidReturnsNull
{
    XCTAssertTrue(json_tokener_parse("{not json") == NULL);
    XCTAssertTrue(json_tokener_parse("") == NULL);
    XCTAssertTrue(json_tokener_parse(NULL) == NULL);
}

- (void)testJsonObjectGetExMissingKey
{
    json_object *o = json_object_new_object();
    json_object *missing = (json_object *)0x1; /* sentinel: must not be written */
    XCTAssertFalse(json_object_object_get_ex(o, "nope", &missing));
    json_object_put(o);
}

#pragma mark - pianobar core (unmodified C code)

- (void)testPianoInitDestroy
{
    PianoHandle_t h;
    PianoReturn_t r = PianoInit(&h, "user", "pass", "ios-sim-device",
                                "inkey123", "outkey123");
    XCTAssertEqual(r, PIANO_RET_OK);
    /* PianoInit must set up the partner cipher handles */
    XCTAssertTrue(h.partner.in != NULL);
    XCTAssertTrue(h.partner.out != NULL);
    PianoDestroy(&h);
}

- (void)testPianoErrorToStr
{
    const char *ok = PianoErrorToStr(PIANO_RET_OK);
    const char *badLogin = PianoErrorToStr(PIANO_RET_INVALID_LOGIN);
    XCTAssertTrue(ok != NULL);
    XCTAssertTrue(badLogin != NULL);
    XCTAssertNotEqual(0, strcmp(ok, badLogin));
}

- (void)testListAppendPrependCount
{
    PianoSong_t a = { 0 }, b = { 0 }, c = { 0 };
    a.title = (char *)"A";
    b.title = (char *)"B";
    c.title = (char *)"C";

    /* Append links in place and returns the (unchanged) head */
    void *head = PianoListAppendP(&a, &b);   /* a -> b */
    XCTAssertEqual(head, &a);
    XCTAssertEqual(PianoListCountP(&a), 2u);

    /* Prepend returns the NEW head; the caller must reassign it */
    head = PianoListPrependP(&a, &c);        /* c -> a -> b */
    XCTAssertEqual(head, &c);
    XCTAssertEqual(PianoListCountP((PianoSong_t *)head), 3u);

    PianoSong_t *first = (PianoSong_t *)PianoListGetP((PianoSong_t *)head, 0);
    XCTAssertTrue(first != NULL);
    XCTAssertEqual(0, strcmp(first->title, "C"));

    PianoSong_t *second = (PianoSong_t *)PianoListGetP((PianoSong_t *)head, 1);
    XCTAssertEqual(0, strcmp(second->title, "A"));

    PianoSong_t *last = (PianoSong_t *)PianoListGetP((PianoSong_t *)head, 2);
    XCTAssertEqual(0, strcmp(last->title, "B"));

    XCTAssertTrue(PianoListGetP((PianoSong_t *)head, 3) == NULL);
}

- (void)testListDelete
{
    PianoSong_t a = { 0 }, b = { 0 }, c = { 0 };
    a.title = (char *)"A";
    b.title = (char *)"B";
    c.title = (char *)"C";

    PianoListAppendP(&a, &b);   /* a -> b */
    PianoListAppendP(&a, &c);   /* a -> b -> c */
    XCTAssertEqual(PianoListCountP(&a), 3u);

    /* Delete returns the (possibly new) HEAD of the list, not the
     * deleted element — the caller reassigns the head */
    void *newhead = PianoListDeleteP(&a, &b);
    XCTAssertTrue(newhead == (void *)&a);
    XCTAssertEqual(PianoListCountP(&a), 2u);

    PianoSong_t *first = (PianoSong_t *)PianoListGetP(&a, 0);
    XCTAssertEqual(0, strcmp(first->title, "A"));
    PianoSong_t *second = (PianoSong_t *)PianoListGetP(&a, 1);
    XCTAssertEqual(0, strcmp(second->title, "C"));
}

- (void)testFindStationById
{
    PianoStation_t s1 = { 0 }, s2 = { 0 };
    s1.name = (char *)"Rock";
    s1.id = (char *)"100";
    s1.isCreator = 1;
    s2.name = (char *)"Jazz";
    s2.id = (char *)"200";
    s2.isCreator = 1;

    PianoListAppendP(&s1, &s2);

    PianoStation_t *found = PianoFindStationById(&s1, "200");
    XCTAssertTrue(found == &s2);

    XCTAssertTrue(PianoFindStationById(&s1, "999") == NULL);
}

#pragma mark - iOS glue helpers

- (void)testUrlPathCopy
{
    PianoRequest_t req;
    memset(&req, 0, sizeof req);
    const char *path = "userLogin?method=userLogin";
    strncpy(req.urlPath, path, sizeof req.urlPath - 1);

    char *copy = PianoIosUrlPathCopy(&req);
    XCTAssertTrue(copy != NULL);
    XCTAssertEqualObjects([NSString stringWithUTF8String:copy],
                          [NSString stringWithUTF8String:path]);
    free(copy);
}

- (void)testResponseDataSetFree
{
    PianoRequest_t req;
    memset(&req, 0, sizeof req);

    PianoIosSetResponseData(&req, "{\"hello\":1}");
    XCTAssertEqualObjects([NSString stringWithUTF8String:req.responseData],
                          @"{\"hello\":1}");

    PianoIosSetResponseData(&req, "replaced");
    XCTAssertEqualObjects([NSString stringWithUTF8String:req.responseData],
                          @"replaced");

    PianoIosFreeResponseData(&req);
    XCTAssertTrue(req.responseData == NULL);
}

- (void)testCreateStationTypeHelpers
{
    PianoRequestDataCreateStation_t d = { 0 };
    PianoIosCreateStationFromSong(&d);
    XCTAssertEqual(d.type, PIANO_MUSICTYPE_SONG);

    PianoIosCreateStationFromArtist(&d);
    XCTAssertEqual(d.type, PIANO_MUSICTYPE_ARTIST);

    // Search results carry a musicToken, so the create-station request must
    // use the INVALID type (which emits the "musicToken" JSON field).
    // Regression guard: using SONG/ARTIST here emits "trackToken" and Pandora
    // rejects the request with "An unexpected error occurred".
    PianoIosCreateStationFromMusicToken(&d);
    XCTAssertEqual(d.type, PIANO_MUSICTYPE_INVALID);
}

#pragma mark - Ownership stress

/* Hammer the create/serialize/put cycle. This is the exact pattern the
 * C core uses (request.c builds a login object, adds values, serializes,
 * puts it). With a plain __bridge (no retain) the returned json_object*
 * dangles and this crashes non-deterministically; with correct +1/-1
 * ownership it is safe. Run under MallocScribble to make any freed-
 * memory use explode. */
- (void)testJsonOwnershipStress
{
    for (int i = 0; i < 5000; i++) {
        json_object *j = json_object_new_object ();
        json_object_object_add (j, "userAuthToken",
                                json_object_new_string ("tok123"));
        json_object_object_add (j, "syncTime",
                                json_object_new_int (i));

        const char *s = json_object_to_json_string (j);
        XCTAssertTrue (s != NULL);
        XCTAssertTrue (strstr (s, "tok123") != NULL);

        json_object *v = NULL;
        XCTAssertTrue (json_object_object_get_ex (j, "syncTime", &v));
        XCTAssertEqual (json_object_get_int (v), i);

        /* values added are owned by the container; put() only j */
        json_object_put (j);
    }

    /* tokener_parse returns +1 (caller owns); values peeked must NOT be
     * put. */
    for (int i = 0; i < 2000; i++) {
        json_object *p = json_tokener_parse ("{\"a\":1,\"b\":[1,2,3]}");
        XCTAssertTrue (p != NULL);

        json_object *a = NULL;
        XCTAssertTrue (json_object_object_get_ex (p, "a", &a));
        XCTAssertEqual (json_object_get_int (a), 1);

        json_object *b = NULL;
        XCTAssertTrue (json_object_object_get_ex (p, "b", &b));
        json_object *two = json_object_array_get_idx (b, 1);
        XCTAssertEqual (json_object_get_int (two), 2);

        json_object_put (p); /* single put — balanced with the single +1 */
    }
}

@end
