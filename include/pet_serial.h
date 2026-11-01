#ifndef PET_SERIAL_H
#define PET_SERIAL_H
#include "pet_handoff.h"
void pet_serial_init(void);
void pet_serial_poll(PetHandoff *handoff);
#endif
