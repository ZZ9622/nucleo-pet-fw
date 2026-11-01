#ifndef PET_FLASH_H
#define PET_FLASH_H
#include <stdint.h>
#include <stdbool.h>
uint32_t pet_flash_read(uint32_t address);
bool pet_flash_write(uint32_t address,uint32_t word);
bool pet_flash_erase(unsigned sector);
#endif
