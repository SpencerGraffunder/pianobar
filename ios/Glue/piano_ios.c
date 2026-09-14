#include "piano_ios.h"

#include <stdlib.h>
#include <string.h>

char *PianoIosUrlPathCopy (const PianoRequest_t *req) {
	return strdup (req->urlPath);
}

void PianoIosSetResponseData (PianoRequest_t *req, const char *data) {
	free (req->responseData);
	req->responseData = strdup (data);
}

void PianoIosFreeResponseData (PianoRequest_t *req) {
	free (req->responseData);
	req->responseData = NULL;
}

void PianoIosCreateStationFromSong (PianoRequestDataCreateStation_t *d) {
	d->type = PIANO_MUSICTYPE_SONG;
}

void PianoIosCreateStationFromArtist (PianoRequestDataCreateStation_t *d) {
	d->type = PIANO_MUSICTYPE_ARTIST;
}

/*
 * Search results carry a musicId (a *musicToken*), not a trackToken. The
 * original pianobar (BarUiActCreateStation) sends it with type INVALID so
 * request.c emits the "musicToken" JSON field. Using the SONG/ARTIST types
 * would emit "trackToken" and Pandora rejects the request with
 * {"stat":"fail","message":"An unexpected error occurred"}.
 */
void PianoIosCreateStationFromMusicToken (PianoRequestDataCreateStation_t *d) {
	d->type = PIANO_MUSICTYPE_INVALID;
}

/*
 * Toggle QuickMix selection across all non-QuickMix stations.
 *
 * This is the iOS replacement for the old Swift-side loop that wrote
 * `station.raw->useQuickMix` directly: that touched C-owned structs through
 * Swift-held pointers, which is a use-after-free the moment the core's
 * station list is rebuilt. Doing it here against the handle's own list is
 * safe and matches the C-core convention the rest of the glue follows.
 */
int PianoIosToggleQuickMix (PianoHandle_t *ph) {
	PianoStation_t *cur;
	int included = 0, nonMix = 0;

	if (ph == NULL)
		return 0;

	cur = ph->stations;
	while (cur != NULL) {
		if (!cur->isQuickMix) {
			nonMix++;
			if (cur->useQuickMix)
				included++;
		}
		cur = (PianoStation_t *) cur->head.next;
	}

	int include = included ? 0 : 1;

	cur = ph->stations;
	while (cur != NULL) {
		if (!cur->isQuickMix)
			cur->useQuickMix = include;
		cur = (PianoStation_t *) cur->head.next;
	}

	return include;
}
