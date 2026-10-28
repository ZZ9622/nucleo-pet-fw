#ifndef BOARD_H
#define BOARD_H

#include <stdbool.h>
#include <stdint.h>

/* NUCLEO-F401RE: LD2 is PA5 (active high), B1 is PC13 (active low). */
typedef enum { BOARD_FEED, BOARD_PET, BOARD_SLEEP, BOARD_PLAY,
               BOARD_ACTION_COUNT } BoardAction;
void board_init(void);
bool board_action_pressed(BoardAction action);
uint32_t board_millis(void);
void board_led_write(bool on);
bool board_button_pressed(void);
void board_idle(void);

#endif
