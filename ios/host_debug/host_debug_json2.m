/* host_debug_json2.m — demonstrate the json shim's ownership bug.
 *
 * Run WITHOUT MallocScribble: usually "works" by luck.
 * Run WITH    MallocScribble=1: freed memory is scribbled, so any
 * dangling-pointer use shows garbage or a crash:
 *
 *   MallocScribble=1 ./json2
 */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include "json.h"

int main (void) {
	/* 1. new_int then read it back — with a plain __bridge the NSNumber
	 * temporary is already released when we get here. */
	json_object *i = json_object_new_int (42);
	int got = json_object_get_int (i);
	printf ("new_int(42) -> %d  (want 42)\n", got);

	/* 2. object_add + put, mirroring request.c's login flow */
	json_object *j = json_object_new_object ();
	json_object_object_add (j, "userAuthToken",
			    json_object_new_string ("tok123"));
	json_object_object_add (j, "syncTime", json_object_new_int (1700000000));
	const char *s = json_object_to_json_string (j);
	printf ("serialized: %s\n", s);
	json_object_put (j);

	/* 3. get_ex after put of a DIFFERENT container still holding it */
	json_object *arr = json_object_new_array ();
	json_object_array_add (arr, json_object_new_string ("x"));
	json_object *x = json_object_array_get_idx (arr, 0);
	printf ("array[0]: %s\n", json_object_get_string (x));
	json_object_put (arr);

	return 0;
}
