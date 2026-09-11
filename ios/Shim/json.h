/*
 * Minimal json-c compatibility shim for iOS.
 *
 * pianobar's libpiano uses json-c for building and parsing the Pandora
 * RPC JSON. This header declares the subset of the json-c API that
 * pianobar uses; json_impl.m implements it on top of Apple's
 * JSONSerialization, so the original pianobar code compiles unmodified
 * on iOS.
 *
 * json_object is an opaque pointer (really an Objective-C object).
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#ifndef PIANOSIM_JSON_H
#define PIANOSIM_JSON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct json_object json_object; /* opaque */

typedef enum {
	json_type_null = 0,
	json_type_boolean,
	json_type_int,
	json_type_double,
	json_type_object,
	json_type_array,
	json_type_string
} json_type;

/* constructors */
json_object *json_object_new_object (void);
json_object *json_object_new_array (void);
json_object *json_object_new_string (const char *s);
json_object *json_object_new_boolean (int b);
json_object *json_object_new_int (int i);
json_object *json_object_new_null (void);
json_object *json_object_new_double (double d);

/* mutators (return 0 on success, -1 on error) */
int json_object_object_add (json_object *obj, const char *key,
                            json_object *val);
int json_object_array_add (json_object *arr, json_object *val);

/* serialization: pointer valid until json_object_put() of the object
 * (matches json-c semantics; caller must not free it) */
const char *json_object_to_json_string (json_object *j);

/* refcount (no-op here: ARC manages the underlying objects) */
void json_object_put (json_object *j);

/* parsing (NULL on failure) */
json_object *json_tokener_parse (const char *str);

/* accessors */
bool json_object_object_get_ex (json_object *obj, const char *key,
                                json_object **val);
const char *json_object_get_string (json_object *j);
int json_object_get_boolean (json_object *j);
int json_object_get_int (json_object *j);
double json_object_get_double (json_object *j);
json_type json_object_get_type (json_object *j);
bool json_object_is_type (json_object *j, json_type t);

size_t json_object_array_length (json_object *arr);
json_object *json_object_array_get_idx (json_object *arr, size_t idx);

#ifdef __cplusplus
}
#endif

#endif /* PIANOSIM_JSON_H */
