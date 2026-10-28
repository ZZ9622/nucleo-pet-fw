#include <stdint.h>

#include "board.h"
#include "button.h"
#include "display.h"
#include "led.h"
#include "pet.h"
#include "screen_idle.h"

enum {
    PET_TICK_MS = 1000U,
    DISPLAY_REFRESH_MS = 5U
};

static uint32_t elapsed_ms(uint32_t now_ms, uint32_t since_ms)
{
    return now_ms - since_ms;
}

static LedPattern led_pattern_for_snapshot(const PetSnapshot *snapshot)
{
    switch (snapshot->mood) {
    case PET_MOOD_HAPPY:
    case PET_MOOD_CONTENT:
        return LED_PATTERN_CONTENT;
    case PET_MOOD_NEEDY:
        return LED_PATTERN_NEEDY;
    case PET_MOOD_CRITICAL:
        return LED_PATTERN_CRITICAL;
    case PET_MOOD_SLEEPING:
        return LED_PATTERN_SLEEP;
    default:
        return LED_PATTERN_CONTENT;
    }
}

static void play_transition_feedback(const PetTransition *transition, Led *led,
                                     uint32_t now_ms)
{
    if (pet_transition_has(transition, PET_EVENT_RESET)) {
        led_play(led, LED_PATTERN_BOOT, now_ms);
    } else if (pet_transition_has(transition, PET_EVENT_FED) ||
               pet_transition_has(transition, PET_EVENT_PLAYED) ||
               pet_transition_has(transition, PET_EVENT_PETTED) ||
               pet_transition_has(transition, PET_EVENT_GAME_REWARD) ||
               pet_transition_has(transition, PET_EVENT_LEVEL_UP)) {
        led_play(led, LED_PATTERN_HAPPY, now_ms);
    }
}

static void apply_button_event(ButtonEvent event, PetState *pet, Led *led,
                               uint32_t now_ms)
{
    PetCommand command = {0};
    PetTransition transition;

    switch (event) {
    case BUTTON_EVENT_SHORT:
        command.type = PET_CMD_FEED;
        break;
    case BUTTON_EVENT_LONG:
        command.type = PET_CMD_SLEEP_TOGGLE;
        break;
    case BUTTON_EVENT_RESET:
        command.type = PET_CMD_RESET;
        break;
    case BUTTON_EVENT_NONE:
    default:
        return;
    }

    pet_apply(pet, &PET_RULES_DEFAULT, &command, &transition);
    play_transition_feedback(&transition, led, now_ms);
}

int main(void)
{
    board_init();

    const uint32_t started_ms = board_millis();
    uint32_t last_pet_tick_ms = started_ms;
    uint32_t last_display_refresh_ms = started_ms;

    ScreenIdle screen;
    screen_idle_init(&screen, started_ms);
    Button button;
    Button actions[BOARD_ACTION_COUNT];
    uint32_t last_action_ms = started_ms;
    bool has_feedback = false;
    Led led;
    PetState pet;
    PetSnapshot snapshot;

    button_init(&button, board_button_pressed(), started_ms);
    for (unsigned i = 0U; i < BOARD_ACTION_COUNT; ++i) {
        button_init(&actions[i], board_action_pressed((BoardAction)i), started_ms);
    }
    led_init(&led, started_ms);
    pet_init(&pet, 0x4010F00DU);
    display_init();

    while (1) {
        const uint32_t now_ms = board_millis();

        button_update(&button, board_button_pressed(), now_ms);
        bool any_pressed = button.stable_pressed;
        for (unsigned i = 0U; i < BOARD_ACTION_COUNT; ++i) {
            button_update(&actions[i], board_action_pressed((BoardAction)i), now_ms);
            any_pressed = any_pressed || actions[i].stable_pressed;
        }
        const bool allow_actions = screen_idle_update(&screen, any_pressed, now_ms);
        display_set_awake(screen.awake);
        const ButtonEvent b1 = button_take_event(&button);
        if (allow_actions && b1 != BUTTON_EVENT_NONE) {
            apply_button_event(b1, &pet, &led, now_ms);
            last_action_ms = now_ms;
            has_feedback = true;
        }
        static const PetCommandType commands[BOARD_ACTION_COUNT] = {
            PET_CMD_FEED, PET_CMD_PET, PET_CMD_SLEEP_TOGGLE, PET_CMD_PLAY
        };
        for (unsigned i = 0U; i < BOARD_ACTION_COUNT; ++i) {
            /* All qualified releases, including holds, perform exactly one action.
             * Only the onboard B1 can reset the pet. */
            const ButtonEvent event = button_take_event(&actions[i]);
            if (allow_actions && event != BUTTON_EVENT_NONE) {
                const PetCommand command = {.type = commands[i]};
                PetTransition transition;
                pet_apply(&pet, &PET_RULES_DEFAULT, &command, &transition);
                play_transition_feedback(&transition, &led, now_ms);
                last_action_ms = now_ms;
                has_feedback = true;
            }
        }
        if (has_feedback && elapsed_ms(now_ms, last_action_ms) >= 2500U) {
            pet.feedback = PET_EVENT_NONE;
            has_feedback = false;
        }

        while (elapsed_ms(now_ms, last_pet_tick_ms) >= PET_TICK_MS) {
            PetTransition transition;
            pet_advance(&pet, &PET_RULES_DEFAULT, 1U, &transition);
            last_pet_tick_ms += PET_TICK_MS;
        }

        pet_make_snapshot(&pet, &snapshot);
        snapshot.feedback_elapsed_ms = elapsed_ms(now_ms, last_action_ms);
        led_set_base(&led, led_pattern_for_snapshot(&snapshot), now_ms);

        if (elapsed_ms(now_ms, last_display_refresh_ms) >= DISPLAY_REFRESH_MS) {
            display_render(&snapshot);
            last_display_refresh_ms = now_ms;
        }

        led_update(&led, now_ms);
        board_idle();
    }
}
