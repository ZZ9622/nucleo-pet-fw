#include "activity_reward.h"
static uint32_t remainder_ms;
void pet_activity_reset_runtime(void) { remainder_ms=0; }
void pet_activity_add(PetHandoff *h,uint32_t elapsed_ms)
{
    if(!pet_handoff_active(h) || !h->activity_day || h->activity_earned>=3U) {
        remainder_ms=0;return;
    }
    if(elapsed_ms>150U) { return; } /* Never credit sensor gaps or disconnection. */
    remainder_ms+=elapsed_ms;
    if(remainder_ms<1000U) { return; }
    remainder_ms-=1000U;
    PetHandoff next=*h;
    next.activity_progress++;
    if(next.activity_progress>=POMI_ACTIVITY_SECONDS) {
        next.activity_progress=0;next.activity_earned++;
    }
    if(!pet_storage_save(&next)) { h->fault=true;return; }
    *h=next;
}
const char *pet_activity_sync(PetHandoff *h,uint32_t day,uint32_t ack_day,uint32_t ack_earned)
{
    if(h->fault) { return "storage_locked"; }
    if(!day || day>3652059U || day<h->activity_day || ack_earned>3U) { return "invalid_request"; }
    if(day==h->activity_day) { return 0; }
    /* The previous day's entitlements must reach the server before rollover.
     * A lost HTTP/BLE reply can always be retried with the same cumulative count. */
    if(h->activity_earned && (ack_day!=h->activity_day || ack_earned<h->activity_earned)) { return "activity_unsettled"; }
    PetHandoff next=*h;next.activity_day=day;next.activity_earned=0;
    if(next.activity_progress>=POMI_ACTIVITY_SECONDS) { return "activity_profile_conflict"; }
    if(!pet_storage_save(&next)) { h->fault=true;return "storage_failed"; }
    *h=next;return 0;
}
