#include "activity_reward.h"
static uint32_t remainder_ms;
static bool clock_ready;
static uint32_t clock_epoch,clock_next,clock_until,clock_last_ms,clock_fraction;
static ActivityClockPlan clock_plan;
void pet_activity_reset_runtime(void) { remainder_ms=0;clock_ready=false;clock_fraction=0; }
bool pet_activity_clock_ready(void) { return clock_ready; }
uint32_t pet_activity_clock_next(void) { return clock_ready?clock_next:0; }
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
        if(h->activity_lifetime_enabled) {
            if(h->activity_total==0xffffffffU) { h->fault=true;return; }
            h->activity_total++;
        }
    }
    h->activity_progress=0; /* Activity after reaching the cap is not banked. */
}
void pet_activity_add(PetHandoff *h,uint32_t elapsed_ms)
{
    if(!pet_handoff_active(h) || !h->activity_day ||
       (h->activity_profile==3U && h->activity_lifetime_enabled && !clock_ready) ||
       h->activity_earned>=pet_activity_limit(h->activity_profile)) {
        remainder_ms=0;return;
    }
    if(elapsed_ms>150U) { return; }
    remainder_ms+=elapsed_ms;
    if(remainder_ms<1000U) { return; }
    remainder_ms-=1000U;
    PetHandoff next=*h;next.activity_progress++;normalize(&next);
    if(next.fault || !pet_storage_save(&next)) { h->fault=true;return; }
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
    if(next.fault || !pet_storage_save(&next)) { h->fault=true;return "storage_failed"; }
    *h=next;clock_ready=false;return 0;
}
const char *pet_activity_sync(PetHandoff *h,uint32_t day,uint32_t ack_day,uint32_t ack_earned)
{
    const uint32_t profile=h->activity_profile?h->activity_profile:(POMI_ACTIVITY_SECONDS==30U?1U:2U);
    return pet_activity_sync_profile(h,day,ack_day,ack_earned,profile,h->activity_profile,h->activity_earned<pet_activity_limit(profile)?h->activity_earned:pet_activity_limit(profile));
}

const char *pet_activity_set_clock(PetHandoff *h,const ActivityClockPlan *p,uint32_t now_ms)
{
    if(h->fault) { return "storage_locked"; }
    if(POMI_ACTIVITY_PROFILE_ID!=3U || h->activity_profile!=3U) { return "activity_profile_conflict"; }
    if(!p->epoch || !p->day || p->day<h->activity_day || p->day>3652059U || p->next_epoch<=p->epoch ||
       p->next_epoch-p->epoch>100800U || p->valid_until<=p->next_epoch || p->exception_count>ACTIVITY_CLOCK_EXCEPTIONS || p->baseline!=0U) {
        return "invalid_clock";
    }
    for(unsigned i=0;i<p->exception_count;++i) {
        if(p->days[i]<p->day || p->days[i]>3652059U || (i && p->days[i]<=p->days[i-1]) ||
           p->durations[i]<72000U || p->durations[i]>100800U || p->durations[i]%60U) { return "invalid_clock"; }
    }
    if(!h->activity_lifetime_enabled && (p->ack_day!=h->activity_day || p->ack_profile!=h->activity_profile ||
       p->ack_earned!=h->activity_earned)) { return "activity_unsettled"; }
    PetHandoff next=*h;
    if(!next.activity_lifetime_enabled) { next.activity_lifetime_enabled=1;next.activity_total=0; }
    if(p->day>next.activity_day) {
        next.activity_day=p->day;next.activity_earned=0;normalize(&next);
    }
    const bool changed=next.activity_day!=h->activity_day || next.activity_earned!=h->activity_earned ||
        next.activity_lifetime_enabled!=h->activity_lifetime_enabled || next.activity_total!=h->activity_total;
    if(next.fault || (changed && !pet_storage_save(&next))) { h->fault=true;return "storage_failed"; }
    *h=next;clock_plan=*p;clock_epoch=p->epoch;clock_next=p->next_epoch;clock_until=p->valid_until;
    clock_last_ms=now_ms;clock_fraction=0;clock_ready=true;return 0;
}
void pet_activity_clock_tick(PetHandoff *h,uint32_t now_ms)
{
    if(!clock_ready || h->fault || h->activity_profile!=3U) { return; }
    const uint32_t elapsed=now_ms-clock_last_ms;clock_last_ms=now_ms;
    const uint64_t ticks=(uint64_t)clock_fraction+elapsed;
    const uint32_t seconds=(uint32_t)(ticks/1000U);clock_fraction=(uint32_t)(ticks%1000U);
    if(seconds>0xffffffffU-clock_epoch) { clock_ready=false;return; }
    clock_epoch+=seconds;
    while(clock_epoch>=clock_next && clock_next<=clock_until) {
        if(h->activity_day>=3652059U) { clock_ready=false;return; }
        PetHandoff next=*h;next.activity_day++;next.activity_earned=0;normalize(&next);
        if(next.fault || !pet_storage_save(&next)) { h->fault=true;clock_ready=false;return; }
        *h=next;
        uint32_t duration=86400U;
        for(unsigned i=0;i<clock_plan.exception_count;++i) {
            if(clock_plan.days[i]==h->activity_day) { duration=clock_plan.durations[i];break; }
        }
        if(duration>0xffffffffU-clock_next) { clock_ready=false;return; }
        clock_next+=duration;
    }
    if(clock_epoch>=clock_until) { clock_ready=false; }
}
