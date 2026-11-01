#ifndef PET_SERIAL_H
#define PET_SERIAL_H
#include "pet.h"
/* Read-only bring-up: '?' requests a versioned state response. */
void pet_serial_init(void);
void pet_serial_poll(const PetState *pet);
#endif
