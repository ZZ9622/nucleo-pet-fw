#ifndef DISPLAY_H
#define DISPLAY_H

#include "pet.h"

/* SBC-OLED01: SSD1306 128x64, I2C1 on PB8/PB9. */
void display_init(void);
/* Requests OLED power state; display_render services the I2C command. */
void display_set_awake(bool awake);
void display_render(const PetSnapshot *snapshot);

#endif
