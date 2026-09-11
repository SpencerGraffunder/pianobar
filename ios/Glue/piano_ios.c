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
