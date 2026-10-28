#ifndef BUTTON_H
#define BUTTON_H

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    BUTTON_EVENT_NONE = 0,
    BUTTON_EVENT_SHORT,
    BUTTON_EVENT_LONG,
    BUTTON_EVENT_RESET
} ButtonEvent;

typedef struct {
    bool stable_pressed;
    bool press_armed;
    bool candidate_pressed;
    uint32_t candidate_since_ms;
    uint32_t press_started_ms;
    ButtonEvent pending_event;
} Button;

void button_init(Button *button, bool raw_pressed, uint32_t now_ms);
void button_update(Button *button, bool raw_pressed, uint32_t now_ms);
ButtonEvent button_take_event(Button *button);

#endif
