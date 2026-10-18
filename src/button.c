#include "button.h"

enum {
    BUTTON_DEBOUNCE_MS = 25U,
    BUTTON_SHORT_MIN_MS = 40U,
    BUTTON_LONG_MS = 1200U,
    BUTTON_RESET_MS = 5000U
};

static uint32_t elapsed_ms(uint32_t now_ms, uint32_t since_ms)
{
    return now_ms - since_ms;
}

void button_init(Button *button, bool raw_pressed, uint32_t now_ms)
{
    button->stable_pressed = raw_pressed;
    button->candidate_pressed = raw_pressed;
    button->candidate_since_ms = now_ms;
    button->press_started_ms = now_ms;
    button->pending_event = BUTTON_EVENT_NONE;
}

void button_update(Button *button, bool raw_pressed, uint32_t now_ms)
{
    if (raw_pressed != button->candidate_pressed) {
        button->candidate_pressed = raw_pressed;
        button->candidate_since_ms = now_ms;
    }

    if ((button->candidate_pressed == button->stable_pressed) ||
        (elapsed_ms(now_ms, button->candidate_since_ms) < BUTTON_DEBOUNCE_MS)) {
        return;
    }

    button->stable_pressed = button->candidate_pressed;
    if (button->stable_pressed) {
        button->press_started_ms = now_ms;
        return;
    }

    const uint32_t duration_ms = elapsed_ms(now_ms, button->press_started_ms);
    if (duration_ms >= BUTTON_RESET_MS) {
        button->pending_event = BUTTON_EVENT_RESET;
    } else if (duration_ms >= BUTTON_LONG_MS) {
        button->pending_event = BUTTON_EVENT_LONG;
    } else if (duration_ms >= BUTTON_SHORT_MIN_MS) {
        button->pending_event = BUTTON_EVENT_SHORT;
    }
}

ButtonEvent button_take_event(Button *button)
{
    const ButtonEvent event = button->pending_event;
    button->pending_event = BUTTON_EVENT_NONE;
    return event;
}
