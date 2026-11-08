#include "activity_reward.h"
static uint32_t remainder_ms;
void pet_activity_reset_runtime(void) { remainder_ms=0; }
uint32_t pet_activity_limit(uint32_t profile) { return profile==3U?6U:3U; }
uint32_t pet_activity_target(uint32_t profile,uint32_t earned)
{
    static const uint32_t steps[6]={60U,180U,300U,480U,720U,900U};
    if(profile==3U) { return steps[earned<6U?earned:5U]; }
    if(profile==1U || (profile==0U && POMI_ACTIVITY_SECONDS==30U)) { return 30U; }
    return 600U;
}
static void normalize(PetHandoff *h)
{
    const uint32_t limit=pet_activity_limit(h->activity_profile);
    while(h->activity_earned<limit) {
        const uint32_t target=pet_activity_target(h->activity_profile,h->activity_earned);
        if(h->activity_progress<target) { return; }
        h->activity_progress-=target;h->activity_earned++;
    }
    h->activity_progress=0; /* Activity after reaching the cap is not banked. */
}
void pet_activity_add(PetHandoff *h,uint32_t elapsed_ms)
{
    if(!pet_handoff_active(h) || !h->activity_day ||
       h->activity_earned>=pet_activity_limit(h->activity_profile)) {
        remainder_ms=0;return;
    }
    if(elapsed_ms>150U) { return; }
    remainder_ms+=elapsed_ms;
    if(remainder_ms<1000U) { return; }
    remainder_ms-=1000U;
    PetHandoff next=*h;next.activity_progress++;normalize(&next);
    if(!pet_storage_save(&next)) { h->fault=true;return; }
    *h=next;
}
const char *pet_activity_sync_profile(PetHandoff *h,uint32_t day,uint32_t ack_day,
    uint32_t ack_earned,uint32_t target_profile,uint32_t ack_profile,uint32_t carry_earned)
{
    if(h->fault) { return "storage_locked"; }
    if(!day || day>3652059U || target_profile<1U || target_profile>3U || target_profile!=POMI_ACTIVITY_PROFILE_ID || ack_profile>3U || ack_earned>6U || carry_earned>pet_activity_limit(target_profile)) {
        return "invalid_request";
    }
    const bool changing=target_profile!=h->activity_profile;
    if(!changing && day<h->activity_day) { return "invalid_request"; }
    if(!changing && day==h->activity_day) { return 0; }
    if(h->activity_day && (ack_day!=h->activity_day || ack_profile!=h->activity_profile || ack_earned<h->activity_earned)) {
        return "activity_unsettled";
    }
    PetHandoff next=*h;next.activity_day=day;next.activity_profile=target_profile;
    next.activity_earned=changing?carry_earned:0U;
    if(changing && carry_earned<(h->activity_earned<pet_activity_limit(target_profile)?h->activity_earned:pet_activity_limit(target_profile))) { return "activity_unsettled"; }
    const uint32_t limit=pet_activity_limit(target_profile);
    if(next.activity_earned>limit) { next.activity_earned=limit; }
    /* Unspent real activity seconds carry into the new schedule. Atomic
     * normalization may immediately earn boxes, but never reuses spent time. */
    normalize(&next);
    if(!pet_storage_save(&next)) { h->fault=true;return "storage_failed"; }
    *h=next;return 0;
}
const char *pet_activity_sync(PetHandoff *h,uint32_t day,uint32_t ack_day,uint32_t ack_earned)
{
    const uint32_t profile=h->activity_profile?h->activity_profile:(POMI_ACTIVITY_SECONDS==30U?1U:2U);
    return pet_activity_sync_profile(h,day,ack_day,ack_earned,profile,h->activity_profile,h->activity_earned<pet_activity_limit(profile)?h->activity_earned:pet_activity_limit(profile));
}
