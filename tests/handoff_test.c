#include "pet_handoff.h"
#include "activity_reward.h"
#include "pet_flash.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t flash[65536];
static int fail_after=-1;
uint32_t pet_flash_read(uint32_t address) { assert(address>=0x08040000U && address<0x08080000U);return flash[(address-0x08040000U)/4]; }
bool pet_flash_write(uint32_t address,uint32_t value) {
    if(fail_after==0){return false;}if(fail_after>0){--fail_after;}
    uint32_t *word=&flash[(address-0x08040000U)/4];
    assert((*word & value)==value);*word=value;return true;
}
bool pet_flash_erase(unsigned sector) {assert(sector==6||sector==7);memset(&flash[(sector-6)*32768],255,131072);return true;}
static void reboot(PetHandoff *h) { fail_after=-1;pet_handoff_init(h);assert(!h->fault); }
static void add_seconds(PetHandoff *h,unsigned seconds) {
    for(unsigned i=0;i<seconds*10U;++i) { pet_activity_add(h,100U); }
}
static const char *sync_activity(PetHandoff *h,uint32_t day,uint32_t ack_day,uint32_t ack_earned) {
    const uint32_t cap=pet_activity_limit(POMI_ACTIVITY_PROFILE_ID);
    const uint32_t carry=h->activity_earned<cap?h->activity_earned:cap;
    return pet_activity_sync_profile(h,day,ack_day,ack_earned,POMI_ACTIVITY_PROFILE_ID,h->activity_profile,carry);
}
static ActivityClockPlan plan_for(const PetHandoff *h,uint32_t day) {
    ActivityClockPlan p={.epoch=1800000000U,.day=day,.next_epoch=1800000001U,
        .valid_until=1800000000U+86400U*20U,.ack_day=h->activity_day,
        .ack_earned=h->activity_earned,.ack_profile=h->activity_profile};return p;
}
static void test_offline_clock(void) {
    if(POMI_ACTIVITY_PROFILE_ID!=3U) { return; }
    memset(flash,255,sizeof flash);PetHandoff h;reboot(&h);assert(!sync_activity(&h,739928U,0,0));
    h.activity_earned=2;h.activity_progress=299;assert(pet_handoff_checkpoint(&h));
    ActivityClockPlan p=plan_for(&h,h.activity_day);p.exception_count=1;p.days[0]=739929U;p.durations[0]=82800U;
    p.ack_earned=1;assert(pet_activity_set_clock(&h,&p,0));assert(!h.activity_lifetime_enabled);
    p.ack_earned=2;assert(!pet_activity_set_clock(&h,&p,0));assert(h.activity_lifetime_enabled && pet_activity_clock_ready());
    pet_activity_clock_tick(&h,999);assert(h.activity_day==739928U);
    pet_activity_clock_tick(&h,1000);assert(h.activity_day==739929U && h.activity_earned==2 && h.activity_progress==59 && h.activity_total==2);
    pet_activity_clock_tick(&h,1000);assert(h.activity_total==2);
    pet_activity_clock_tick(&h,82800999U);assert(h.activity_day==739929U);
    pet_activity_clock_tick(&h,82801000U);assert(h.activity_day==739930U && h.activity_total==2);
    reboot(&h);assert(!pet_activity_clock_ready() && h.activity_total==2);
    add_seconds(&h,10);assert(h.activity_progress==59); /* Power loss invalidates time, never the save. */
    p=plan_for(&h,h.activity_day+4U);assert(!pet_activity_set_clock(&h,&p,0));
    assert(h.activity_total==2 && h.activity_progress==59); /* No fake activity during four days without power. */
    add_seconds(&h,1);assert(h.activity_total==3 && h.activity_earned==1);
    p=plan_for(&h,h.activity_day-1U);assert(pet_activity_set_clock(&h,&p,0));
    p=plan_for(&h,h.activity_day);assert(!pet_activity_set_clock(&h,&p,0xfffffff0U));
    const uint32_t before=h.activity_day;pet_activity_clock_tick(&h,984U);assert(h.activity_day==before+1U);
    /* A service-driven rollover must invalidate the old boundary so the
     * hardware timer cannot apply the same local day twice. */
    const uint32_t oldday=h.activity_day;
    assert(!sync_activity(&h,oldday+1U,oldday,h.activity_earned));
    assert(!pet_activity_clock_ready());pet_activity_clock_tick(&h,1984U);
    assert(h.activity_day==oldday+1U);
    for(int cut=0;cut<46;++cut) {
        memset(flash,255,sizeof flash);reboot(&h);assert(!sync_activity(&h,739928U,0,0));
        h.activity_earned=1;h.activity_progress=60;assert(pet_handoff_checkpoint(&h));
        p=plan_for(&h,h.activity_day);assert(!pet_activity_set_clock(&h,&p,0));
        fail_after=cut;pet_activity_clock_tick(&h,1000);reboot(&h);
        assert(h.activity_total==0 || h.activity_total==1);
        p=plan_for(&h,739929U);assert(!pet_activity_set_clock(&h,&p,0));
        assert(h.activity_total==1 && h.activity_day==739929U && h.activity_progress==0);
        assert(!pet_activity_set_clock(&h,&p,0));assert(h.activity_total==1);
    }
    for(int cut=0;cut<46;++cut) {
        memset(flash,255,sizeof flash);reboot(&h);assert(!sync_activity(&h,739928U,0,0));
        add_seconds(&h,7);p=plan_for(&h,h.activity_day);fail_after=cut;
        (void)pet_activity_set_clock(&h,&p,0);reboot(&h);
        assert(h.activity_progress==7 && h.activity_total==0 && !pet_activity_clock_ready());
        p=plan_for(&h,h.activity_day);assert(!pet_activity_set_clock(&h,&p,0));
        assert(h.activity_lifetime_enabled && h.activity_progress==7 && h.activity_total==0);
    }
    puts("offline clock: exact boundary, 23h DST, timer wrap, cold-boot re-time, cumulative total and 46 torn rollovers passed");
}
static void test_activity(void) {
    memset(flash,255,sizeof flash);PetHandoff h;reboot(&h);
    add_seconds(&h,2);assert(h.activity_day==0 && h.activity_progress==0);
    assert(!sync_activity(&h,739928U,0,0));
    const uint32_t interval=pet_activity_target(h.activity_profile,0);
    const uint32_t cap=pet_activity_limit(h.activity_profile);
    add_seconds(&h,7);reboot(&h);assert(h.activity_progress==7);
    pet_activity_add(&h,9999);assert(h.activity_progress==7);
    add_seconds(&h,interval-7U);assert(h.activity_earned==1 && h.activity_progress==0);
    reboot(&h);assert(h.activity_earned==1);
    for(uint32_t i=1;i<cap;++i) {
        const uint32_t step=pet_activity_target(h.activity_profile,i);
        add_seconds(&h,step-1U);assert(h.activity_earned==i);
        add_seconds(&h,1);assert(h.activity_earned==i+1U && h.activity_progress==0);
    }
    add_seconds(&h,interval*3U);assert(h.activity_earned==cap && h.activity_progress==0);
    assert(sync_activity(&h,739929U,739928U,cap-1U));
    assert(!sync_activity(&h,739929U,739928U,cap));
    assert(h.activity_earned==0);add_seconds(&h,8);reboot(&h);assert(h.activity_progress==8);
    assert(sync_activity(&h,739928U,739928U,cap));
    assert(!sync_activity(&h,739929U,0,0));assert(h.activity_progress==8);
    const uint32_t travel[4]={101,102,103,104};
    assert(!pet_handoff_command(&h,"TAKE_PREPARE",travel,h.revision,0));
    add_seconds(&h,5);assert(h.activity_progress==8);
    for(int cut=0;cut<44;++cut) {
        memset(flash,255,sizeof flash);reboot(&h);assert(!sync_activity(&h,739928U,0,0));
        h.activity_progress=interval-1;assert(pet_handoff_checkpoint(&h));
        fail_after=cut;add_seconds(&h,1);reboot(&h);
        assert((h.activity_earned==0 && h.activity_progress==interval-1) ||
               (h.activity_earned==1 && h.activity_progress==0));
        if(h.activity_earned==0) { add_seconds(&h,1); }
        assert(h.activity_earned==1 && h.activity_progress==0);
    }
    if(POMI_ACTIVITY_PROFILE_ID==3U) {
        memset(flash,255,sizeof flash);reboot(&h);assert(!sync_activity(&h,739928U,0,0));
        add_seconds(&h,60+179);assert(h.activity_earned==1 && h.activity_progress==179);
        assert(!sync_activity(&h,739929U,739928U,1));
        assert(h.activity_earned==1 && h.activity_progress==119); /* 60 carried seconds -> one new-day box. */
        reboot(&h);assert(h.activity_progress==119);
        assert(!sync_activity(&h,739929U,739928U,1));assert(h.activity_progress==119);
        /* Legacy upgrade keeps already received boxes; even a backwards ordinal
         * at 07:00 is legitimate only during acknowledged profile migration. */
        h.activity_profile=1;h.activity_earned=3;h.activity_progress=0;assert(pet_handoff_checkpoint(&h));
        assert(pet_activity_sync_profile(&h,739928U,739929U,2,3,1,3));
        assert(!pet_activity_sync_profile(&h,739928U,739929U,3,3,1,3));
        assert(h.activity_earned==3 && h.activity_progress==0);
        add_seconds(&h,480);assert(h.activity_earned==4);
        h.activity_profile=2;h.activity_earned=2;h.activity_progress=123;
        assert(pet_handoff_checkpoint(&h));
        unsigned newest=0;uint32_t seq=0;
        for(unsigned i=0;i<65536;i+=64) { if(flash[i+63]==0x434f4d32U && flash[i+2]>seq) { seq=flash[i+2];newest=i; } }
        flash[newest+1]=4;flash[newest+34]=0xffffffffU;flash[newest+62]=pet_crc32(&flash[newest],62U*4U);
        reboot(&h);assert(h.activity_profile==0 && h.activity_progress==123 && h.activity_earned==2);
        assert(!pet_activity_sync_profile(&h,h.activity_day,h.activity_day,2,3,0,2));
        reboot(&h);assert(h.activity_profile==3 && h.activity_earned==2 && h.activity_progress==123);
    }
    puts("activity rewards: all stage boundaries, cap, persistent seconds, rollover carry, ACK migration, 44 torn writes passed");
}
int main(void) {
    test_activity();
    test_offline_clock();
    assert(pet_crc32("123456789",9)==0xcbf43926);
    memset(flash,255,sizeof flash);PetHandoff h;reboot(&h);
    assert(pet_handoff_active(&h));
    uint32_t take[4]={1,2,3,4},back[4]={5,6,7,8};
    assert(!pet_handoff_command(&h,"TAKE_PREPARE",take,0,0));
    uint32_t hash=pet_state_hash(&h.pet);assert(hash==h.payload_hash);
    assert(!pet_handoff_active(&h));reboot(&h);assert(h.phase==PET_OFFER_PHONE);
    assert(!pet_handoff_command(&h,"TAKE_PREPARE",take,0,0));
    assert(pet_handoff_command(&h,"TAKE_COMMIT",back,0,0));
    fail_after=5;assert(pet_handoff_command(&h,"TAKE_COMMIT",take,0,0));assert(h.fault);
    reboot(&h);assert(h.phase==PET_OFFER_PHONE);
    assert(!pet_handoff_command(&h,"TAKE_COMMIT",take,0,0));
    reboot(&h);assert(h.phase==PET_PHONE && h.revision==1);
    assert(!pet_handoff_command(&h,"TAKE_COMMIT",take,0,0));
    PetState updated=h.pet;updated.energy=68;updated.happiness=100;updated.game_time_s=123;
    assert(!pet_handoff_command(&h,"RETURN_STAGE",back,1,&updated));
    assert(!pet_handoff_active(&h));reboot(&h);assert(h.phase==PET_RETURN_STAGED);
    PetState wrong=updated;wrong.energy=67;
    assert(pet_handoff_command(&h,"RETURN_STAGE",back,1,&wrong));
    assert(!pet_handoff_command(&h,"RETURN_STAGE",back,1,&updated));
    assert(!pet_handoff_command(&h,"RETURN_COMMIT",back,1,0));
    assert(h.pet.energy==68 && h.pet.happiness==100 && h.pet.game_time_s==123);
    reboot(&h);assert(pet_handoff_active(&h) && h.revision==2);
    h.pet.game_time_s++;
    assert(!pet_handoff_command(&h,"RETURN_STAGE",back,1,&updated));
    assert(h.pet.game_time_s==124); // Receipt retry must not restore stale snapshot.
    assert(!pet_handoff_command(&h,"RETURN_COMMIT",back,1,0));
    assert(pet_handoff_command(&h,"TAKE_PREPARE",back,2,0));
    assert(pet_handoff_command(&h,"TAKE_COMMIT",take,0,0));
    for(unsigned i=0;i<1100;++i){h.pet.game_time_s=i;assert(pet_handoff_checkpoint(&h));}
    reboot(&h);assert(h.pet.game_time_s==1099 && h.revision==2);
    // All partial-write positions preserve a valid, frozen ownership record.
    for(int cut=0;cut<28;++cut){
        memset(flash,255,sizeof flash);reboot(&h);
        assert(!pet_handoff_command(&h,"TAKE_PREPARE",take,0,0));
        fail_after=cut;(void)pet_handoff_command(&h,"TAKE_COMMIT",take,0,0);
        reboot(&h);assert(h.phase==PET_OFFER_PHONE || h.phase==PET_PHONE);
        assert(!pet_handoff_active(&h));
    }
    memset(flash,255,sizeof flash);reboot(&h);
    /* v2 journal records migrate without inventing an item operation. */
    flash[1]=2;for(unsigned i=24;i<62;++i) { flash[i]=0xFFFFFFFFU; }
    flash[62]=pet_crc32(flash,62U*4U);reboot(&h);
    assert(h.item_status==0 && h.item_kind==0);
    const uint32_t box[4]={11,12,13,14},food[4]={15,16,17,18};
    assert(!pet_item_command(&h,"ITEM_OPEN",box,0));assert(h.pet.energy==70);
    reboot(&h);assert(h.item_status==1 && h.pet.energy==70);
    assert(pet_item_finish_box(&h));reboot(&h);assert(h.item_status==2);
    assert(!pet_item_command(&h,"ITEM_OPEN",box,0));assert(h.pet.energy==70);
    assert(pet_item_command(&h,"ITEM_FOOD1",box,0));
    assert(!pet_item_command(&h,"ITEM_FOOD2",food,0));assert(h.pet.energy==70);
    reboot(&h);assert(h.item_status==1);
    assert(pet_handoff_command(&h,"TAKE_PREPARE",take,0,0));
    assert(pet_item_confirm(&h));assert(h.pet.energy==100);
    reboot(&h);assert(h.item_status==2 && !pet_item_confirm(&h));
    h.pet.energy=9;assert(pet_item_command(&h,"ITEM_OPEN",take,0));assert(h.pet.energy==9);
    h.pet.energy=10;h.pet.is_sleeping=true;assert(pet_item_command(&h,"ITEM_OPEN",take,0));
    h.pet.is_sleeping=false;assert(!pet_item_command(&h,"ITEM_OPEN",take,0));assert(h.pet.energy==0);
    for(int cut=0;cut<36;++cut) {
        memset(flash,255,sizeof flash);reboot(&h);fail_after=cut;
        (void)pet_item_command(&h,"ITEM_OPEN",box,0);reboot(&h);
        assert(h.pet.energy==80 || (h.pet.energy==70 && h.item_status==1));
        assert(!pet_item_command(&h,"ITEM_OPEN",box,0));assert(h.pet.energy==70);
    }
    memset(flash,255,sizeof flash);reboot(&h);
    h.pet.energy=0;h.pet.is_sleeping=true;h.pet.seconds_since_feed=PET_FEED_DEADLINE_S;
    assert(!pet_item_command(&h,"ITEM_FOOD1",food,0));assert(pet_item_confirm(&h));
    assert(h.pet.energy==30 && !h.pet.is_sleeping && h.pet.seconds_since_feed==0);
    for(int cut=0;cut<36;++cut) {
        memset(flash,255,sizeof flash);reboot(&h);
        assert(!pet_item_command(&h,"ITEM_FOOD1",food,0));fail_after=cut;
        (void)pet_item_confirm(&h);reboot(&h);
        if(h.item_status==1) { assert(h.pet.energy==80);assert(pet_item_confirm(&h)); }
        assert(h.item_status==2 && h.pet.energy==100 && !pet_item_confirm(&h));
    }
    puts("item operations: durable charge, duplicate receipt, button confirmation, low energy and torn writes passed");
    memset(flash,255,sizeof flash);flash[0]=0;pet_handoff_init(&h);
    assert(h.fault && h.phase==PET_LOCKED && !pet_handoff_active(&h));
    puts("handoff + journal: roundtrip, retries, stale IDs, 28 torn writes, reboot, sector rotation passed");
    return 0;
}
