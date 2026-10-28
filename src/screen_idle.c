#include "screen_idle.h"

void screen_idle_init(ScreenIdle *screen, uint32_t now_ms)
{
    screen->last_input_ms = now_ms;
    screen->awake = true;
    screen->suppress_until_release = false;
}

bool screen_idle_update(ScreenIdle *screen, bool any_pressed, uint32_t now_ms)
{
    if (any_pressed) {
        screen->last_input_ms = now_ms;
        if (!screen->awake) {
            screen->awake = true;
            screen->suppress_until_release = true;
        }
    }
    if (screen->suppress_until_release) {
        if (!any_pressed) {
            screen->suppress_until_release = false;
            screen->last_input_ms = now_ms;
        }
        return false;
    }
    if (screen->awake && !any_pressed &&
        (uint32_t)(now_ms - screen->last_input_ms) >= SCREEN_IDLE_TIMEOUT_MS) {
        screen->awake = false;
    }
    return screen->awake;
}
