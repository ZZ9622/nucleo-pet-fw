#ifndef PET_HANDOFF_H
#define PET_HANDOFF_H
#include "pet.h"
#include <stddef.h>
enum { PET_BOARD=0, PET_OFFER_PHONE=1, PET_PHONE=2, PET_RETURN_STAGED=3, PET_LOCKED=4 };
enum { PET_STATE_WORDS=14 };
typedef struct {
    uint32_t phase, revision, transaction[4], payload_hash;
    PetState pet;
    bool fault;
} PetHandoff;
uint32_t pet_crc32(const void *data, size_t size);
void pet_state_encode(const PetState *pet, uint32_t words[PET_STATE_WORDS]);
bool pet_state_decode(PetState *pet, const uint32_t words[PET_STATE_WORDS]);
uint32_t pet_state_hash(const PetState *pet);
void pet_handoff_init(PetHandoff *handoff);
bool pet_handoff_active(const PetHandoff *handoff);
bool pet_handoff_checkpoint(PetHandoff *handoff);
const char *pet_handoff_command(PetHandoff *handoff, const char *command,
    const uint32_t transaction[4], uint32_t revision, const PetState *incoming);
/* Journal backend returns 1=valid, 0=blank, -1=corrupt. */
int pet_storage_load(PetHandoff *handoff);
bool pet_storage_save(const PetHandoff *handoff);
#endif
