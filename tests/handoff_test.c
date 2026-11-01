#include "pet_handoff.h"
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
int main(void) {
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
    memset(flash,255,sizeof flash);flash[0]=0;pet_handoff_init(&h);
    assert(h.fault && h.phase==PET_LOCKED && !pet_handoff_active(&h));
    puts("handoff + journal: roundtrip, retries, stale IDs, 28 torn writes, reboot, sector rotation passed");
    return 0;
}
