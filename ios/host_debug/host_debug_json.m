/* host_debug_json.m — check the json shim's boolean handling on host. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include "json.h"

int main (void) {
	NSObject *b = @YES;
	printf ("@YES class:          %s\n", object_getClassName (b));
	const char *ct = [(NSNumber *) b objCType];
	printf ("@YES objCType:       %s\n", ct ? ct : "(null)");

	json_object *jb = json_object_new_boolean (1);
	printf ("shim get_type:       %d (boolean=%d)\n",
		json_object_get_type (jb), json_type_boolean);
	printf ("shim is_type bool:   %d\n", json_object_is_type (jb, json_type_boolean));

	/* parsed JSON boolean */
	json_object *p = json_tokener_parse ("{\"success\":true}");
	json_object *ok = NULL;
	int ex = json_object_object_get_ex (p, "success", &ok);
	printf ("parsed get_ex:       %d\n", ex);
	if (ok) {
		printf ("parsed get_type:   %d\n", json_object_get_type (ok));
		printf ("parsed get_bool:   %d\n", json_object_get_boolean (ok));
	}
	return 0;
}
