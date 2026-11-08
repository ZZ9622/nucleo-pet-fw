#ifndef ACTIVITY_REWARD_H
#define ACTIVITY_REWARD_H
#include "pet_handoff.h"
#ifndef POMI_ACTIVITY_SECONDS
#define POMI_ACTIVITY_SECONDS 600U
#endif
#if POMI_ACTIVITY_SECONDS != 600 && POMI_ACTIVITY_SECONDS != 30
#error Activity interval must be 600 seconds (release) or 30 seconds (test)
#endif
/* Fractional milliseconds are intentionally uncredited until a whole second
 * is committed. Phone UI exposes committed progress only. */
void pet_activity_reset_runtime(void);
void pet_activity_add(PetHandoff *h, uint32_t elapsed_ms);
const char *pet_activity_sync(PetHandoff *h, uint32_t day, uint32_t ack_day, uint32_t ack_earned);
#endif
