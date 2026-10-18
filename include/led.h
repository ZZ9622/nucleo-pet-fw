#ifndef LED_H
#define LED_H

#include <stdint.h>

typedef enum {
    LED_PATTERN_BOOT = 0,
    LED_PATTERN_CONTENT,
    LED_PATTERN_HAPPY,
    LED_PATTERN_NEEDY,
    LED_PATTERN_CRITICAL,
    LED_PATTERN_SLEEP,
    LED_PATTERN_RESET
} LedPattern;

typedef struct {
    LedPattern base_pattern;
    uint32_t base_started_ms;
    LedPattern transient_pattern;
    uint32_t transient_started_ms;
    uint8_t transient_active;
    uint8_t output_is_on;
} Led;

void led_init(Led *led, uint32_t now_ms);
void led_set_base(Led *led, LedPattern pattern, uint32_t now_ms);
void led_play(Led *led, LedPattern pattern, uint32_t now_ms);
void led_update(Led *led, uint32_t now_ms);

#endif
