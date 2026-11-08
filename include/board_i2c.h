#ifndef BOARD_I2C_H
#define BOARD_I2C_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
void board_i2c_init(void);
bool board_i2c_write(uint8_t address, uint8_t prefix, const uint8_t *data, size_t count);
bool board_i2c_read_register(uint8_t address, uint8_t reg, uint8_t *value);
#endif
