#include <stdint.h>

#include "board.h"
#include "button.h"
#include "display.h"
#include "led.h"
#include "pet.h"
#include "pet_serial.h"
#include "motion.h"
#include "activity_reward.h"
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
    uint32_t item_animation_ms=started_ms;
    bool item_animation=false;
    uint8_t previous_merchant=0;
    uint32_t merchant_notice_ms=0;
    Led led;
    PetHandoff handoff;
    PetState *pet = &handoff.pet;
    uint32_t last_checkpoint_ms = started_ms;
    PetSnapshot snapshot;
#if defined(POMI_ADVENTURE_MOTION_TEST)
    uint32_t test_activity_ms=0;
#elif !defined(POMI_ADVENTURE_PREVIEW)
    uint32_t adventure_ms=0, energy_day=0, energy_ms=0;
    unsigned sleep_start_energy=0;
    uint32_t moving_ms=0, wake_ms=0;
    bool adventure_motion=false, tracking_sleep=false, woke_this_outing=false, wake_animation=false;
#endif

    button_init(&button, board_button_pressed(), started_ms);
    for (unsigned i = 0U; i < BOARD_ACTION_COUNT; ++i) {
        button_init(&actions[i], board_action_pressed((BoardAction)i), started_ms);
    }
    led_init(&led, started_ms);
    pet_handoff_init(&handoff);
    display_init();
    pet_serial_init();
    lis3dh_init();

    while (1) {
        const uint32_t now_ms = board_millis();
        const uint32_t previous_phase = handoff.phase;
        const uint32_t previous_item_status=handoff.item_status;
        pet_activity_clock_tick(&handoff,board_clock_millis());
        const MotionState *motion=lis3dh_state();
        const uint32_t previous_sample=motion->last_sample_ms, previous_samples=motion->samples;
        lis3dh_poll(now_ms);
#ifdef POMI_ADVENTURE_PREVIEW
        (void)motion; (void)previous_sample; (void)previous_samples;
        const uint32_t scene=elapsed_ms(now_ms,started_ms)/5000U%14U;
        pet_adventure_stage=(uint8_t)(scene%7U+1U);
        if(pet_adventure_stage==7U) { pet_adventure_stage=0; }
        pet_adventure_riding=scene>=7U;
        pet_adventure_paused=false;
#else
        const bool moving=motion->connected && motion->had_activity &&
                          elapsed_ms(now_ms,motion->activity_ms)<1500U;
        const bool sample=moving && motion->samples!=previous_samples && previous_samples;
        const uint32_t interval=motion->last_sample_ms-previous_sample;
#ifdef POMI_ADVENTURE_MOTION_TEST
        if(sample && interval<=150U && test_activity_ms<30000U) {
            test_activity_ms+=interval;
            if(test_activity_ms>30000U) { test_activity_ms=30000U; }
        }
        const bool recent=motion->had_activity && elapsed_ms(now_ms,motion->activity_ms)<120000U;
        pet_adventure_stage=recent?(uint8_t)(test_activity_ms/5000U):0;
        pet_adventure_paused=!moving;
        pet_adventure_riding=pet->energy<=25U;
#else
        if(sample) { pet_activity_add(&handoff,interval); }
        if(energy_day!=handoff.activity_day) {
            energy_day=handoff.activity_day;energy_ms=0;
        }
        const bool eligible=pet_handoff_active(&handoff) && handoff.activity_profile==3U &&
                            pet->seconds_since_feed<PET_FEED_DEADLINE_S;
        if(pet->is_sleeping && !tracking_sleep) { sleep_start_energy=pet->energy; }
        tracking_sleep=pet->is_sleeping;
        if(!moving) { moving_ms=0; }
        if(sample && interval<=150U && moving_ms<3000U) { moving_ms+=interval; }
        if(moving && eligible) { adventure_ms=motion->activity_ms;adventure_motion=true; }
        if(eligible && moving_ms>=3000U && pet->is_sleeping && !woke_this_outing) {
            const unsigned recovered=pet->energy>sleep_start_energy?pet->energy-sleep_start_energy:0;
            const unsigned missing=100U-sleep_start_energy;
            const unsigned cost=recovered*10U>=missing*9U?2U:recovered*2U>=missing?5U:10U;
            const unsigned available=pet->energy>11U?pet->energy-11U:0;
            pet->energy-=(uint8_t)(cost<available?cost:available);
            const PetCommand wake={.type=PET_CMD_SLEEP_TOGGLE};
            PetTransition transition;
            pet_apply(pet,&PET_RULES_DEFAULT,&wake,&transition);
            woke_this_outing=true;wake_animation=true;wake_ms=now_ms;
            (void)pet_handoff_checkpoint(&handoff);
        }
        if(wake_animation && elapsed_ms(now_ms,wake_ms)>=2500U) { wake_animation=false; }
        if(!eligible || elapsed_ms(now_ms,adventure_ms)>=120000U) {
            adventure_motion=false;pet_adventure_riding=false;woke_this_outing=false;wake_animation=false;
        }
        pet_adventure_stage=adventure_motion?(uint8_t)handoff.activity_earned:0;
        pet_adventure_paused=!moving;
        pet_adventure_waking=wake_animation;
        if(pet_adventure_stage && pet->energy<=25U) { pet_adventure_riding=true; }
        if(sample && interval<=150U && pet_adventure_stage && !pet_adventure_riding &&
           !pet->is_sleeping && handoff.adventure_energy_spent<6U) {
            energy_ms+=interval;
            if(energy_ms>=600000U) {
                energy_ms-=600000U;handoff.adventure_energy_spent++;pet->energy--;
                (void)pet_handoff_checkpoint(&handoff);
            }
        }
#endif
#endif
        pet_serial_poll(&handoff);
        if(handoff.item_kind==1 && handoff.item_status==1 && !item_animation) {
            item_animation=true;item_animation_ms=now_ms;screen_idle_init(&screen,now_ms);
        }
        if(item_animation && elapsed_ms(now_ms,item_animation_ms)>=2400U) {
            (void)pet_item_finish_box(&handoff);item_animation=false;
        }
        if(handoff.item_status==1 && previous_item_status!=1 && handoff.item_kind==2) { screen_idle_init(&screen,now_ms); }
        if (previous_phase != handoff.phase) {
            screen_idle_init(&screen, now_ms);
            last_pet_tick_ms = now_ms;
            has_feedback = false;
        }
        const bool active = pet_handoff_active(&handoff);

        button_update(&button, board_button_pressed(), now_ms);
        bool any_pressed = button.stable_pressed;
        for (unsigned i = 0U; i < BOARD_ACTION_COUNT; ++i) {
            button_update(&actions[i], board_action_pressed((BoardAction)i), now_ms);
            any_pressed = any_pressed || actions[i].stable_pressed;
        }
        if(pet_adventure_stage
           || pet_adventure_waking
        ) { screen.last_input_ms=now_ms;screen.awake=true; }
        const bool allow_actions = screen_idle_update(&screen, any_pressed, now_ms);
        display_set_awake(screen.awake);
        const bool food_confirmation=handoff.item_status==1;
        const ButtonEvent b1 = button_take_event(&button);
        if (allow_actions && active && b1 != BUTTON_EVENT_NONE) {
            if(handoff.item_status==1) {
                /* Consume this event, including long holds, so confirmation cannot
                 * also feed, toggle sleep or reset. Wake-only presses stay wake-only. */
                if(handoff.item_kind==2 && pet->is_sleeping && b1==BUTTON_EVENT_LONG) {
                    const PetCommand wake={.type=PET_CMD_SLEEP_TOGGLE};PetTransition t;
                    pet_apply(pet,&PET_RULES_DEFAULT,&wake,&t);(void)pet_handoff_checkpoint(&handoff);
                } else { (void)pet_item_confirm(&handoff); }
            } else { apply_button_event(b1, pet, &led, now_ms); }
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
            if (allow_actions && active && !food_confirmation && event != BUTTON_EVENT_NONE) {
                const PetCommand command = {.type = commands[i]};
                PetTransition transition;
                pet_apply(pet, &PET_RULES_DEFAULT, &command, &transition);
                play_transition_feedback(&transition, &led, now_ms);
                last_action_ms = now_ms;
                has_feedback = true;
            }
        }
        if (has_feedback && elapsed_ms(now_ms, last_action_ms) >= 2500U) {
            pet->feedback = PET_EVENT_NONE;
            has_feedback = false;
        }

        if (!active) { last_pet_tick_ms = now_ms; }
        while (active && elapsed_ms(now_ms, last_pet_tick_ms) >= PET_TICK_MS) {
            PetTransition transition;
            pet_advance(pet, &PET_RULES_DEFAULT, 1U, &transition);
            last_pet_tick_ms += PET_TICK_MS;
        }

        pet_make_snapshot(pet, &snapshot);
        if (active && ((has_feedback && last_action_ms == now_ms) || elapsed_ms(now_ms, last_checkpoint_ms) >= 300000U)) {
            pet_handoff_checkpoint(&handoff);
            last_checkpoint_ms = now_ms;
        }
        snapshot.adventure_stage=pet_adventure_stage;
        snapshot.adventure_riding=pet_adventure_riding;
        snapshot.adventure_paused=pet_adventure_paused;
#if defined(POMI_ADVENTURE_PREVIEW) || defined(POMI_ADVENTURE_MOTION_TEST)
        snapshot.adventure_preview=true;
#else
        snapshot.adventure_waking=pet_adventure_waking;
#endif
        const uint8_t merchant = pet_activity_merchant();
        if (merchant != previous_merchant) {
            previous_merchant = merchant;
            if (merchant) { merchant_notice_ms=now_ms;screen_idle_init(&screen,now_ms); }
        }
        /* Alternate a brief notice with the usual pet view during the visit. */
        if (merchant && elapsed_ms(now_ms,merchant_notice_ms) % 20000U < 3000U) {
            snapshot.merchant_visit=merchant;
        }
        snapshot.item_food_pending=handoff.item_status==1 && handoff.item_kind==2;
        snapshot.item_box_animation=item_animation;
        snapshot.feedback_elapsed_ms=elapsed_ms(now_ms,item_animation_ms);
        snapshot.is_away = handoff.phase == PET_PHONE;
        snapshot.is_transferring = !pet_handoff_active(&handoff) && !snapshot.is_away;
        if(!item_animation) { snapshot.feedback_elapsed_ms = elapsed_ms(now_ms, last_action_ms); }
        led_set_base(&led, led_pattern_for_snapshot(&snapshot), now_ms);

        if (elapsed_ms(now_ms, last_display_refresh_ms) >= DISPLAY_REFRESH_MS) {
            display_render(&snapshot);
            last_display_refresh_ms = now_ms;
        }

        led_update(&led, now_ms);
        board_idle();
    }
}
