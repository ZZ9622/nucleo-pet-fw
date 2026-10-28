#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "pet_animation.h"
#include "pet_view.h"

int main(int argc, char **argv)
{
    PetSnapshot pet = {.energy=80U, .happiness=80U, .mood=PET_MOOD_CONTENT};
    const PetSnapshot original = pet;
    PetPose pose;
    bool seen[7] = {false};
    bool left = false, right = false;
    struct { uint8_t before[8], image[1024], after[8]; } guarded;
    memset(&guarded, 0xA5, sizeof guarded);
    for (uint32_t t = 0U; t < 240000U; t += 100U) {
        pet_animation_sample(&pet, t, &pose);
        seen[pose.kind] = true;
        left = left || pose.x_offset < 0;
        right = right || pose.x_offset > 0;
        assert(pose.x_offset >= -7 && pose.x_offset <= 7);
        assert(pose.y_offset >= -3 && pose.y_offset <= 1);
        pet_view_draw(guarded.image, &pet, t);
        for (unsigned i = 0U; i < 8U; ++i) {
            assert(guarded.before[i] == 0xA5 && guarded.after[i] == 0xA5);
        }
    }
    assert(seen[PET_ANIM_BLINK] && seen[PET_ANIM_WALK] && seen[PET_ANIM_JUMP]);
    assert(left && right && memcmp(&pet, &original, sizeof pet) == 0);
    pet.feedback = PET_EVENT_PLAYED;
    pet.feedback_elapsed_ms = 400U;
    pet_animation_sample(&pet, 100U, &pose);
    assert(pose.kind == PET_ANIM_JUMP && pose.y_offset == -3);
    pet.feedback_elapsed_ms = 1200U;
    pet_animation_sample(&pet, 100U, &pose);
    assert(pose.kind != PET_ANIM_JUMP); /* No repeated play jump. */
    pet.energy = 30U;
    pet_animation_sample(&pet, 2500U, &pose);
    assert(pose.kind == PET_ANIM_YAWN && pose.eyes_closed);
    pet.is_sleeping = true;
    pet_animation_sample(&pet, UINT32_MAX, &pose);
    assert(pose.kind == PET_ANIM_SLEEP);
    pet.is_collapsed = true;
    pet_animation_sample(&pet, UINT32_MAX, &pose);
    assert(pose.kind == PET_ANIM_COLLAPSED); /* Priority over sleep. */

    PetState state;
    PetTransition transition;
    pet_init(&state, 1U);
    state.energy = 10U;
    pet_advance(&state, &PET_RULES_DEFAULT, 2U, &transition);
    assert(!state.is_sleeping);
    pet_advance(&state, &PET_RULES_DEFAULT, 1U, &transition);
    assert(state.is_sleeping && pet_transition_has(&transition, PET_EVENT_SLEPT));
    const PetCommand wake = {.type = PET_CMD_SLEEP_TOGGLE};
    pet_apply(&state, &PET_RULES_DEFAULT, &wake, &transition);
    assert(!state.is_sleeping && state.low_energy_awake_s == 0U);
    const PetCommand feed = {.type = PET_CMD_FEED};
    pet_apply(&state, &PET_RULES_DEFAULT, &feed, &transition);
    pet_advance(&state, &PET_RULES_DEFAULT, 3U, &transition);
    assert(!state.is_sleeping && state.energy == 40U);
    /* Rescue deadline preempts auto-sleep, including during yawning. */
    state.seconds_since_feed = PET_FEED_DEADLINE_S - 1U;
    state.energy = 0U;
    pet_advance(&state, &PET_RULES_DEFAULT, 1U, &transition);
    pet_make_snapshot(&state, &pet);
    assert(pet.is_collapsed);

    if (argc == 2) {
        FILE *out = fopen(argv[1], "wb");
        assert(out != NULL);
        for (uint32_t t = 0U; t < 6000U; t += 100U) {
            for (unsigned kind = 0U; kind < 5U; ++kind) {
                pet = original;
                uint32_t sampled_time = t;
                if (kind == 1U) { sampled_time = 7000U + t % 3200U; }
                if (kind == 2U) {
                    pet.feedback = PET_EVENT_PLAYED;
                    pet.feedback_elapsed_ms = t % 2000U;
                    sampled_time = 100U;
                }
                if (kind == 3U) { pet.energy = 10U; }
                if (kind == 4U) { pet.is_sleeping = true; pet.mood = PET_MOOD_SLEEPING; }
                pet_view_draw(guarded.image, &pet, sampled_time);
                for (unsigned y = 0U; y < 64U; ++y) {
                    for (unsigned x = 0U; x < 128U; ++x) {
                        fputc((guarded.image[y / 8U * 128U + x] & (1U << (y % 8U))) != 0U ? 255 : 0, out);
                    }
                }
            }
        }
        fclose(out);
    }
    puts("animation tests: passed");
    return 0;
}
