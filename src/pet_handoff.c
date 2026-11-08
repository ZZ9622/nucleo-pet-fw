#include "pet_handoff.h"
#include "activity_reward.h"

uint32_t pet_crc32(const void *data, size_t size)
{
    const uint8_t *bytes = data;
    uint32_t crc = 0xFFFFFFFFU;
    for (size_t i=0; i<size; ++i) {
        crc ^= bytes[i];
        for (unsigned b=0; b<8; ++b) { crc=(crc>>1)^((crc&1U)?0xEDB88320U:0U); }
    }
    return crc^0xFFFFFFFFU;
}
void pet_state_encode(const PetState *p, uint32_t w[PET_STATE_WORDS])
{
    w[0]=p->energy; w[1]=p->happiness; w[2]=p->experience; w[3]=p->coins;
    w[4]=p->level; w[5]=(uint32_t)p->stage; w[6]=p->is_sleeping?1U:0U;
    w[7]=p->low_energy_awake_s; w[8]=p->seconds_since_feed;
    w[9]=p->awake_decay_elapsed_s; w[10]=p->sleep_recovery_elapsed_s;
    w[11]=p->game_time_s; w[12]=p->rng_state; w[13]=(uint32_t)p->feedback;
}
bool pet_state_decode(PetState *p, const uint32_t w[PET_STATE_WORDS])
{
    if (w[0]>100 || w[1]>100 || w[2]>65535 || w[3]>65535 || w[4]<1 || w[4]>99 ||
        w[5]>2 || w[6]>1 || w[7]>3 || w[8]>86400 || w[9]>=3600 || w[10]>=60 ||
        w[13]>10 || (w[8]==86400 && w[0]!=0)) { return false; }
    p->energy=(uint8_t)w[0]; p->happiness=(uint8_t)w[1]; p->experience=(uint16_t)w[2];
    p->coins=(uint16_t)w[3]; p->level=(uint8_t)w[4]; p->stage=(PetLifeStage)w[5];
    p->is_sleeping=w[6]!=0; p->low_energy_awake_s=(uint8_t)w[7];
    p->seconds_since_feed=w[8]; p->awake_decay_elapsed_s=w[9];
    p->sleep_recovery_elapsed_s=w[10]; p->game_time_s=w[11]; p->rng_state=w[12];
    p->feedback=(PetEvent)w[13]; return true;
}
uint32_t pet_state_hash(const PetState *pet)
{
    uint32_t words[PET_STATE_WORDS];
    uint8_t bytes[PET_STATE_WORDS*4];
    pet_state_encode(pet,words);
    for (unsigned i=0;i<PET_STATE_WORDS;++i) {
        for (unsigned j=0;j<4;++j) { bytes[i*4+j]=(uint8_t)(words[i]>>(j*8)); }
    }
    return pet_crc32(bytes,sizeof bytes);
}
static bool equal_id(const uint32_t a[4], const uint32_t b[4])
{
    for (unsigned i=0;i<4;++i) { if(a[i]!=b[i]) { return false; } }
    return true;
}
static bool command_is(const char *a,const char *b)
{
    while (*a && *a==*b) { ++a; ++b; }
    return *a==*b;
}
void pet_handoff_init(PetHandoff *h)
{
    pet_activity_reset_runtime();
    *h=(PetHandoff){0};
    const int result=pet_storage_load(h);
    if (result==1) { return; }
    pet_init(&h->pet,0x4010F00DU);
    if (result<0) { h->fault=true; h->phase=PET_LOCKED; return; }
    if (!pet_storage_save(h)) { h->fault=true; }
}
bool pet_handoff_active(const PetHandoff *h) { return h->phase==PET_BOARD && !h->fault; }
bool pet_handoff_checkpoint(PetHandoff *h)
{
    if(h->fault) { return false; }
    if(!pet_storage_save(h)) { h->fault=true; return false; }
    return true;
}
const char *pet_handoff_command(PetHandoff *h,const char *command,
    const uint32_t id[4],uint32_t revision,const PetState *incoming)
{
    if(h->fault || h->phase==PET_LOCKED) { return "storage_locked"; }
    if(!(id[0]|id[1]|id[2]|id[3]) || revision==0xFFFFFFFFU) { return "invalid_request"; }
    if(h->item_status==1) { return "item_pending"; }
    const bool same=equal_id(h->transaction,id);
    PetHandoff next=*h;
    if(command_is(command,"TAKE_PREPARE")) {
        if(same && ((h->phase==PET_OFFER_PHONE && h->revision==revision) ||
                    (h->phase==PET_PHONE && h->revision==revision+1))) { return 0; }
        if(same || h->phase!=PET_BOARD || h->revision!=revision) { return "conflict"; }
        next.phase=PET_OFFER_PHONE;
        for(unsigned i=0;i<4;++i) { next.transaction[i]=id[i]; }
        next.payload_hash=pet_state_hash(&next.pet);
    } else if(command_is(command,"TAKE_COMMIT")) {
        if(same && h->phase==PET_PHONE && h->revision==revision+1) { return 0; }
        if(!same || h->phase!=PET_OFFER_PHONE || h->revision!=revision) { return "conflict"; }
        next.phase=PET_PHONE; next.revision++;
    } else if(command_is(command,"RETURN_STAGE")) {
        if(!incoming) { return "invalid_state"; }
        uint32_t words[PET_STATE_WORDS]; PetState check;
        pet_state_encode(incoming,words);
        if(!pet_state_decode(&check,words)) { return "invalid_state"; }
        const uint32_t hash=pet_state_hash(incoming);
        if(same && h->payload_hash==hash &&
           ((h->phase==PET_RETURN_STAGED && h->revision==revision) ||
            (h->phase==PET_BOARD && h->revision==revision+1))) { return 0; }
        if(h->phase!=PET_PHONE || h->revision!=revision || same) { return "conflict"; }
        next.phase=PET_RETURN_STAGED; next.pet=*incoming; next.payload_hash=hash;
        for(unsigned i=0;i<4;++i) { next.transaction[i]=id[i]; }
    } else if(command_is(command,"RETURN_COMMIT")) {
        if(same && h->phase==PET_BOARD && h->revision==revision+1) { return 0; }
        if(!same || h->phase!=PET_RETURN_STAGED || h->revision!=revision) { return "conflict"; }
        next.phase=PET_BOARD; next.revision++;
    } else { return "unknown_command"; }
    if(!pet_storage_save(&next)) { h->fault=true; return "storage_failed"; }
    *h=next; return 0;
}

/* The service permits one outstanding inventory operation per identity.
 * Durable receipts let the app settle a lost BLE reply without charging twice. */
const char *pet_item_command(PetHandoff *h,const char *command,const uint32_t id[4],uint32_t revision)
{
    if(!pet_handoff_active(h)) { return "conflict"; }
    if(!(id[0]|id[1]|id[2]|id[3])) { return "invalid_request"; }
    const uint32_t kind=command_is(command,"ITEM_OPEN")?1U:2U;
    const uint32_t level=command_is(command,"ITEM_FOOD2")?2U:1U;
    if(h->item_status && equal_id(h->item_id,id)) {
        return h->item_kind==kind && h->item_level==level ? 0 : "conflict";
    }
    if(h->revision!=revision || h->item_status==1) { return "conflict"; }
    if(h->pet.is_sleeping && (kind==1 || h->pet.seconds_since_feed<PET_FEED_DEADLINE_S)) { return "pet_sleeping"; }
    if(kind==1 && h->pet.energy<10) { return "low_energy"; }
    PetHandoff next=*h;
    for(unsigned i=0;i<4;++i) { next.item_id[i]=id[i]; }
    next.item_kind=kind;next.item_level=level;next.item_status=1U;
    if(kind==1) { next.pet.energy-=10; }
    if(!pet_storage_save(&next)) { h->fault=true;return "storage_failed"; }
    *h=next;return 0;
}
bool pet_item_confirm(PetHandoff *h)
{
    if(!pet_handoff_active(h) || h->item_status!=1 || h->item_kind!=2 || (h->pet.is_sleeping && h->pet.seconds_since_feed<PET_FEED_DEADLINE_S)) { return false; }
    PetHandoff next=*h;PetTransition transition;
    const PetCommand feed={.type=PET_CMD_FEED};
    pet_apply(&next.pet,&PET_RULES_DEFAULT,&feed,&transition);
    if(h->item_level==2) { unsigned e=next.pet.energy+20U;next.pet.energy=(uint8_t)(e>100U?100U:e); }
    next.item_status=2;
    if(!pet_storage_save(&next)) { h->fault=true;return false; }
    *h=next;return true;
}

bool pet_item_finish_box(PetHandoff *h)
{
    if(!pet_handoff_active(h) || h->item_status!=1 || h->item_kind!=1) { return false; }
    PetHandoff next=*h;next.item_status=2;
    if(!pet_storage_save(&next)) { h->fault=true;return false; }
    *h=next;return true;
}
