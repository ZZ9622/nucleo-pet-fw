#include "pet_handoff.h"
#include "pet_flash.h"
/* Two 128 KiB sectors, 256-byte append records. Commit marker is written LAST. */
#define BASE 0x08040000UL
#define SECTOR_BYTES 0x20000UL
#define RECORD_BYTES 256UL
#define MAGIC 0x50455432UL
#define COMMIT 0x434F4D32UL
static uint32_t newest_address, newest_sequence;
static bool record_read(uint32_t address, PetHandoff *h,uint32_t *sequence)
{
    uint32_t w[64];
    for(unsigned i=0;i<64;++i) { w[i]=pet_flash_read(address+i*4U); }
    if(w[0]!=MAGIC || w[1]!=2 || w[63]!=COMMIT || w[62]!=pet_crc32(w,62U*4U) ||
       w[2]==0 || w[3]>PET_RETURN_STAGED || w[4]==0xFFFFFFFFU) { return false; }
    PetState p;
    if(!pet_state_decode(&p,&w[10])) { return false; }
    *h=(PetHandoff){.phase=w[3],.revision=w[4],.payload_hash=w[9],.pet=p};
    for(unsigned i=0;i<4;++i) { h->transaction[i]=w[5+i]; }
    *sequence=w[2]; return true;
}
static bool blank(uint32_t address)
{
    for(unsigned i=0;i<64;++i) { if(pet_flash_read(address+i*4U)!=0xFFFFFFFFU) { return false; } }
    return true;
}
int pet_storage_load(PetHandoff *h)
{
    newest_address=0; newest_sequence=0; bool dirty=false;
    for(uint32_t a=BASE;a<BASE+SECTOR_BYTES*2;a+=RECORD_BYTES) {
        PetHandoff candidate; uint32_t seq;
        if(!blank(a)) { dirty=true; }
        if(record_read(a,&candidate,&seq) && seq>newest_sequence) {
            *h=candidate; newest_address=a; newest_sequence=seq;
        }
    }
    return newest_address?1:(dirty?-1:0);
}
bool pet_storage_save(const PetHandoff *h)
{
    if(newest_sequence==0xFFFFFFFFU || h->phase>PET_RETURN_STAGED) { return false; }
    uint32_t sector=newest_address?((newest_address-BASE)/SECTOR_BYTES):0;
    uint32_t address=newest_address?newest_address+RECORD_BYTES:BASE;
    const uint32_t end=BASE+(sector+1U)*SECTOR_BYTES;
    while(address<end && !blank(address)) { address+=RECORD_BYTES; }
    if(address>=end) {
        sector^=1U;
        if(!pet_flash_erase(6U+sector)) { return false; }
        address=BASE+sector*SECTOR_BYTES;
    }
    uint32_t w[64]; for(unsigned i=0;i<64;++i) { w[i]=0xFFFFFFFFU; }
    w[0]=MAGIC; w[1]=2; w[2]=newest_sequence+1; w[3]=h->phase; w[4]=h->revision;
    for(unsigned i=0;i<4;++i) { w[5+i]=h->transaction[i]; }
    w[9]=h->payload_hash; pet_state_encode(&h->pet,&w[10]);
    w[62]=pet_crc32(w,62U*4U); w[63]=COMMIT;
    for(unsigned i=0;i<64;++i) {
        if(w[i]!=0xFFFFFFFFU && !pet_flash_write(address+i*4U,w[i])) { return false; }
    }
    PetHandoff verified; uint32_t seq;
    if(!record_read(address,&verified,&seq)) { return false; }
    newest_address=address; newest_sequence=seq; return true;
}
