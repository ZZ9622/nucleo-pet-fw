#ifndef ACTIVITY_REWARD_H
#define ACTIVITY_REWARD_H
#include "pet_handoff.h"
#ifndef POMI_ACTIVITY_SECONDS
#define POMI_ACTIVITY_SECONDS 600U
#endif
#ifndef POMI_ACTIVITY_PROFILE_ID
#if POMI_ACTIVITY_SECONDS == 30
#define POMI_ACTIVITY_PROFILE_ID 1U
#else
#define POMI_ACTIVITY_PROFILE_ID 3U
#endif
#endif
#if POMI_ACTIVITY_PROFILE_ID < 1 || POMI_ACTIVITY_PROFILE_ID > 3
#error Invalid activity profile
#endif
/* Profiles: 0=migrated v4 (unknown old interval), 1=unchanged 30s test,
 * 2=legacy 600s/3, 3=08:00 incremental six-box cycle. */
uint32_t pet_activity_limit(uint32_t profile);
uint32_t pet_activity_target(uint32_t profile, uint32_t earned);
enum { ACTIVITY_CLOCK_EXCEPTIONS=24 };
typedef struct {
    uint32_t epoch, day, next_epoch, valid_until;
    uint32_t ack_day, ack_earned, ack_profile, baseline;
    uint32_t exception_count, days[ACTIVITY_CLOCK_EXCEPTIONS], durations[ACTIVITY_CLOCK_EXCEPTIONS];
} ActivityClockPlan;
void pet_activity_clock_tick(PetHandoff *h, uint32_t now_ms);
bool pet_activity_clock_ready(void);
uint32_t pet_activity_clock_next(void);
const char *pet_activity_set_clock(PetHandoff *h,const ActivityClockPlan *plan,uint32_t now_ms);
void pet_activity_reset_runtime(void);
void pet_activity_add(PetHandoff *h, uint32_t elapsed_ms);
const char *pet_activity_sync(PetHandoff *h, uint32_t day, uint32_t ack_day, uint32_t ack_earned);
const char *pet_activity_sync_profile(PetHandoff *h, uint32_t day, uint32_t ack_day,
    uint32_t ack_earned, uint32_t target_profile, uint32_t ack_profile, uint32_t carry_earned);
#endif
