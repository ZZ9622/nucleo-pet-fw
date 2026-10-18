#ifndef DISPLAY_H
#define DISPLAY_H

#include "pet.h"

/* Replace display_null.c with an OLED or TFT backend when hardware is selected. */
void display_init(void);
void display_render(const PetSnapshot *snapshot);

#endif
