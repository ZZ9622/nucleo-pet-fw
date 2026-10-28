#ifndef SCREEN_IDLE_H
#define SCREEN_IDLE_H
#include <stdbool.h>
#include <stdint.h>
#define SCREEN_IDLE_TIMEOUT_MS 30000U

typedef struct {
    uint32_t last_input_ms;
    bool awake;
    bool suppress_until_release;
} ScreenIdle;

void screen_idle_init(ScreenIdle *screen, uint32_t now_ms);
/* Takes debounced any-button level. Returns whether actions may run this tick.
 * Wake consumes all buttons until every button has been released. */
bool screen_idle_update(ScreenIdle *screen, bool any_pressed, uint32_t now_ms);
#endif
