#ifndef BOARD_H
#define BOARD_H

#include <stdbool.h>
#include <stdint.h>

/* NUCLEO-F401RE: LD2 is PA5 (active high), B1 is PC13 (active low). */
void board_init(void);
uint32_t board_millis(void);
void board_led_write(bool on);
bool board_button_pressed(void);
void board_idle(void);

#endif
