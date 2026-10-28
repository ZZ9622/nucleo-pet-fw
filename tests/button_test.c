#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "button.h"

static ButtonEvent press(Button *button, uint32_t start, uint32_t duration)
{
    button_update(button, true, start);
    button_update(button, true, start + 25U);
    button_update(button, false, start + duration);
    button_update(button, false, start + duration + 25U);
    return button_take_event(button);
}

int main(void)
{
    Button button;
    button_init(&button, false, 0U);
    /* Neither a bouncing edge nor a stable tap under 40ms is an action. */
    button_update(&button, true, 1U);
    button_update(&button, false, 10U);
    button_update(&button, false, 40U);
    assert(button_take_event(&button) == BUTTON_EVENT_NONE);
    assert(press(&button, 100U, 30U) == BUTTON_EVENT_NONE);
    assert(press(&button, 200U, 100U) == BUTTON_EVENT_SHORT);
    assert(button_take_event(&button) == BUTTON_EVENT_NONE);
    assert(press(&button, 400U, 1200U) == BUTTON_EVENT_LONG);
    assert(press(&button, 2000U, 5000U) == BUTTON_EVENT_RESET);
    /* Held buttons never auto-repeat. */
    button_update(&button, true, 8000U);
    button_update(&button, true, 8025U);
    button_update(&button, true, 18000U);
    assert(button_take_event(&button) == BUTTON_EVENT_NONE);
    button_update(&button, false, 18001U);
    button_update(&button, false, 18026U);
    assert(button_take_event(&button) == BUTTON_EVENT_RESET);
    /* Unsigned subtraction remains valid over the millisecond rollover. */
    button_init(&button, false, UINT32_MAX - 200U);
    assert(press(&button, UINT32_MAX - 50U, 100U) == BUTTON_EVENT_SHORT);
    /* A button held at power-up must first be released, then pressed. */
    button_init(&button, true, 0U);
    button_update(&button, false, 6000U);
    button_update(&button, false, 6025U);
    assert(button_take_event(&button) == BUTTON_EVENT_NONE);
    assert(press(&button, 7000U, 100U) == BUTTON_EVENT_SHORT);
    puts("button tests: passed");
    return 0;
}
