#ifndef PET_VIEW_H
#define PET_VIEW_H
#include <stdint.h>
#include "pet.h"
/* Monochrome SSD1306 page layout; caller provides 1024 bytes. */
void pet_view_draw(uint8_t *frame, const PetSnapshot *pet, uint32_t time_ms);
#endif
