#include "pet_flash.h"
typedef struct { volatile uint32_t ACR, KEYR, OPTKEYR, SR, CR, OPTCR; } Flash;
#define F ((Flash *)0x40023C00UL)
#define ERRORS 0xF2U
static bool unlock(void)
{
    while(F->SR&(1UL<<16)) { }
    if(F->CR&(1UL<<31)) { F->KEYR=0x45670123U; F->KEYR=0xCDEF89ABU; }
    F->SR=ERRORS|1U;
    return !(F->CR&(1UL<<31));
}
uint32_t pet_flash_read(uint32_t address) { return *(volatile const uint32_t *)(uintptr_t)address; }
bool pet_flash_write(uint32_t address,uint32_t word)
{
    if(address<0x08040000UL || address>=0x08080000UL || (address&3U) || !unlock()) { return false; }
    F->CR=(2U<<8)|1U;
    *(volatile uint32_t *)(uintptr_t)address=word;
    while(F->SR&(1UL<<16)) { }
    const bool ok=!(F->SR&ERRORS);
    F->CR=1UL<<31;
    __asm volatile("dsb; isb" ::: "memory");
    return ok && pet_flash_read(address)==word;
}
bool pet_flash_erase(unsigned sector)
{
    if((sector!=6U && sector!=7U) || !unlock()) { return false; }
    F->CR=(2U<<8)|(sector<<3)|(1U<<1);
    F->CR|=1UL<<16;
    while(F->SR&(1UL<<16)) { }
    const bool ok=!(F->SR&ERRORS);
    F->CR=1UL<<31; return ok;
}
