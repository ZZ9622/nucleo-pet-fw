#include "led.h"

#include <stdbool.h>

#include "board.h"

static uint32_t elapsed_ms(uint32_t now_ms, uint32_t since_ms)
{
    return now_ms - since_ms;
}

static uint32_t pattern_duration_ms(LedPattern pattern)
{
    switch (pattern) {
    case LED_PATTERN_BOOT:
        return 500U;
    case LED_PATTERN_HAPPY:
        return 640U;
    case LED_PATTERN_RESET:
        return 800U;
    case LED_PATTERN_CONTENT:
    case LED_PATTERN_NEEDY:
    case LED_PATTERN_CRITICAL:
    case LED_PATTERN_SLEEP:
    default:
        return 0U;
    }
}

static bool pattern_output(LedPattern pattern, uint32_t elapsed)
{
    uint32_t phase;

    switch (pattern) {
    case LED_PATTERN_BOOT:
        return (elapsed < 100U) || ((elapsed >= 200U) && (elapsed < 300U));
    case LED_PATTERN_CONTENT:
        phase = elapsed % 2000U;
        return (phase < 80U) || ((phase >= 180U) && (phase < 260U));
    case LED_PATTERN_HAPPY:
        phase = elapsed % 160U;
        return phase < 80U;
    case LED_PATTERN_NEEDY:
        return (elapsed % 1000U) < 250U;
    case LED_PATTERN_CRITICAL:
        return (elapsed % 200U) < 100U;
    case LED_PATTERN_SLEEP:
        return (elapsed % 2000U) < 80U;
    case LED_PATTERN_RESET:
        return (elapsed % 200U) < 100U;
    default:
        return false;
    }
}

void led_init(Led *led, uint32_t now_ms)
{
    led->base_pattern = LED_PATTERN_CONTENT;
    led->base_started_ms = now_ms;
    led->transient_pattern = LED_PATTERN_BOOT;
    led->transient_started_ms = now_ms;
    led->transient_active = 1U;
    led->output_is_on = 0U;
}

void led_set_base(Led *led, LedPattern pattern, uint32_t now_ms)
{
    if (led->base_pattern != pattern) {
        led->base_pattern = pattern;
        led->base_started_ms = now_ms;
    }
}

void led_play(Led *led, LedPattern pattern, uint32_t now_ms)
{
    led->transient_pattern = pattern;
    led->transient_started_ms = now_ms;
    led->transient_active = 1U;
}

void led_update(Led *led, uint32_t now_ms)
{
    LedPattern active_pattern = led->base_pattern;
    uint32_t started_ms = led->base_started_ms;

    if (led->transient_active != 0U) {
        const uint32_t duration = pattern_duration_ms(led->transient_pattern);
        if ((duration != 0U) &&
            (elapsed_ms(now_ms, led->transient_started_ms) >= duration)) {
            led->transient_active = 0U;
        } else {
            active_pattern = led->transient_pattern;
            started_ms = led->transient_started_ms;
        }
    }

    const bool should_be_on = pattern_output(active_pattern,
                                             elapsed_ms(now_ms, started_ms));
    if (should_be_on != (led->output_is_on != 0U)) {
        board_led_write(should_be_on);
        led->output_is_on = should_be_on ? 1U : 0U;
    }
}
