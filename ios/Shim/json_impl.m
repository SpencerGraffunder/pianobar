/*
 * json-c shim implementation backed by Apple's JSONSerialization.
 *
 * Copyright (c) 2025 Spencer Graffunder
 * MIT licensed.
 */

#import <Foundation/Foundation.h>
#include <string.h>

#include "json.h"

/* json_object is an opaque pointer that actually holds an Objective-C
 * object pointer.
 *
 * Ownership (json-c semantics):
 *  - "creating" calls (json_object_new_*, json_tokener_parse) return a
 *    +1 reference owned by the C caller; json_object_put releases it.
 *  - "peeking" calls (json_object_object_get_ex, json_object_array_get_idx,
 *    json_object_object_get) return a reference owned by the CONTAINER;
 *    the caller must NOT put it.
 *
 * A plain __bridge cast would NOT retain: the Objective-C temporary is
 * released when the function returns and the json_object* dangles. That
 * is only harmless if the memory happens not to be reused — in practice
 * it crashes the process non-deterministically (seen on CI). */
static inline id jobj (json_object *j) {
	return (__bridge id) (void *) j;
}

/* +1: transfer ownership of a reference to the C world. */
static inline json_object *jptr (id o) {
	CFTypeRef cf = (__bridge_retained CFTypeRef) o;
	return (json_object *) (void *) cf;
}

/* no ownership transfer: valid only while the container keeps the object
 * alive. */
static inline json_object *jpeek (id o) {
	return (__bridge json_object *) o;
}

json_object *json_object_new_object (void) {
	return jptr ([NSMutableDictionary dictionary]);
}

json_object *json_object_new_array (void) {
	return jptr ([NSMutableArray array]);
}

json_object *json_object_new_string (const char *s) {
	if (s == NULL)
		return jptr ([NSNull null]);
	return jptr ([NSString stringWithUTF8String: s]);
}

json_object *json_object_new_boolean (int b) {
	/* NSNumber numberWithBool: produces a real CFBoolean (char type);
	 * @(int) would be a plain integer number and break json_type checks */
	return jptr ([NSNumber numberWithBool: b != 0]);
}

json_object *json_object_new_int (int i) {
	return jptr (@(i));
}

json_object *json_object_new_double (double d) {
	return jptr (@(d));
}

int json_object_object_add (json_object *obj, const char *key,
                            json_object *val) {
	NSMutableDictionary *m = jobj (obj);
	if (key == NULL || ![m isKindOfClass: [NSMutableDictionary class]])
		return -1;
	/* the dictionary takes its own reference; the caller keeps its own
	 * (json-c's object_add does not take ownership) */
	m [[NSString stringWithUTF8String: key]] = jobj (val) ?: (id) [NSNull null];
	return 0;
}

int json_object_array_add (json_object *arr, json_object *val) {
	NSMutableArray *a = jobj (arr);
	if (![a isKindOfClass: [NSMutableArray class]])
		return -1;
	[a addObject: jobj (val) ?: (id) [NSNull null]];
	return 0;
}

const char *json_object_to_json_string (json_object *j) {
	/* thread-local output buffer, valid until the object is freed
	 * (matches json-c semantics for pianobar's usage) */
	static __thread char buffer [65536];

	id obj = jobj (j);
	NSError *err = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject: obj
	                                                   options: 0
	                                                     error: &err];
	if (data == nil) {
		buffer[0] = '\0';
		return buffer;
	}

	size_t n = data.length;
	if (n > sizeof (buffer) - 1)
		n = sizeof (buffer) - 1;
	memcpy (buffer, data.bytes, n);
	buffer[n] = '\0';
	return buffer;
}

void json_object_put (json_object *j) {
	if (j == NULL)
		return;
	/* jptr() did a +1; undo it. (plain cast: CFRelease takes CFTypeRef,
	 * which is just const void *) */
	CFRelease ((CFTypeRef) (void *) j);
}

json_object *json_tokener_parse (const char *str) {
	if (str == NULL)
		return NULL;

	NSData *data = [NSData dataWithBytes: str length: strlen (str)];
	NSError *err = nil;
	id obj = [NSJSONSerialization JSONObjectWithData: data
	                                           options: NSJSONReadingMutableContainers
	                                             error: &err];
	if (obj == nil)
		return NULL;
	return jptr (obj);
}

bool json_object_object_get_ex (json_object *obj, const char *key,
                                json_object **val) {
	NSDictionary *d = jobj (obj);
	if (key == NULL || ![d isKindOfClass: [NSDictionary class]])
		return false;

	id v = d [[NSString stringWithUTF8String: key]];
	if (v == nil)
		return false;
	if (val != NULL)
		*val = jpeek (v); /* container owns it — do NOT put() */
	return true;
}

const char *json_object_get_string (json_object *j) {
	id o = jobj (j);
	if ([o isKindOfClass: [NSString class]])
		return [(NSString *) o UTF8String];
	if ([o isKindOfClass: [NSNumber class]]) {
		/* stringValue creates a temporary NSString whose internal buffer
		 * we must not hand out; copy to stable thread-local storage */
		static __thread char buf [256];
		const char *s = [(NSNumber *) o stringValue].UTF8String;
		if (s == NULL)
			return NULL;
		strncpy (buf, s, sizeof (buf) - 1);
		buf [sizeof (buf) - 1] = '\0';
		return buf;
	}
	return NULL;
}

int json_object_get_boolean (json_object *j) {
	id o = jobj (j);
	if ([o isKindOfClass: [NSNumber class]])
		return [(NSNumber *) o boolValue];
	return 0;
}

int json_object_get_int (json_object *j) {
	id o = jobj (j);
	if ([o isKindOfClass: [NSNumber class]])
		return [(NSNumber *) o intValue];
	return 0;
}

double json_object_get_double (json_object *j) {
	id o = jobj (j);
	if ([o isKindOfClass: [NSNumber class]])
		return [(NSNumber *) o doubleValue];
	return 0.0;
}

json_type json_object_get_type (json_object *j) {
	id o = jobj (j);
	if ([o isKindOfClass: [NSString class]])
		return json_type_string;
	if ([o isKindOfClass: [NSDictionary class]])
		return json_type_object;
	if ([o isKindOfClass: [NSArray class]])
		return json_type_array;
	if ([o isKindOfClass: [NSNumber class]]) {
		const char *c = [(NSNumber *)o objCType]; /* returns C string */
		if (c != NULL && (c[0] == 'c' || c[0] == 'C'))
			return json_type_boolean;
		if (c != NULL &&
		    (c[0] == 'i' || c[0] == 's' || c[0] == 'l' || c[0] == 'q'))
			return json_type_int;
		return json_type_double;
	}
	return json_type_null;
}

bool json_object_is_type (json_object *j, json_type t) {
	return json_object_get_type (j) == t;
}

size_t json_object_array_length (json_object *arr) {
	id a = jobj (arr);
	if ([a isKindOfClass: [NSArray class]])
		return (size_t) [(NSArray *) a count];
	return 0;
}

json_object *json_object_array_get_idx (json_object *arr, size_t idx) {
	id a = jobj (arr);
	if (![a isKindOfClass: [NSArray class]])
		return NULL;
	NSArray *na = (NSArray *) a;
	if (idx >= (size_t) na.count)
		return NULL;
	return jpeek (na[idx]); /* container owns it — do NOT put() */
}
