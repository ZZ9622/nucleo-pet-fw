#include "pet_animation.h"

static uint32_t mix(uint32_t value)
{
    value ^= value >> 16;
    value *= 0x7FEB352DU;
    value ^= value >> 15;
    value *= 0x846CA68BU;
    return value ^ (value >> 16);
}

void pet_animation_sample(const PetSnapshot *pet, uint32_t time_ms, PetPose *pose)
{
    *pose = (PetPose){.kind = PET_ANIM_IDLE};
    if (pet->is_collapsed) {
        pose->kind = PET_ANIM_COLLAPSED;
        return;
    }
    if (pet->is_sleeping || pet->mood == PET_MOOD_SLEEPING) {
        pose->kind = PET_ANIM_SLEEP;
        pose->eyes_closed = true;
        pose->y_offset = (int)(time_ms / 800U % 2U);
        return;
    }
    const uint32_t cycle = time_ms / 12000U;
    const uint32_t phase = time_ms % 12000U;
    const uint32_t choice = mix(cycle + 0x401U);
    const bool play_jump = pet->feedback == PET_EVENT_PLAYED &&
                           pet->feedback_elapsed_ms < 1200U;
    /* Low energy first yawns for 3s before the simulation enters sleep. */
    if (pet->energy <= PET_AUTO_SLEEP_ENERGY ||
        (pet->energy <= 35U && phase >= 2000U && phase < 4000U)) {
        pose->kind = PET_ANIM_YAWN;
        pose->eyes_closed = true;
        pose->phase = (uint8_t)(time_ms / 300U % 4U);
    } else if (play_jump || (pet->happiness >= 75U && pet->energy >= 60U &&
                           choice % 3U != 0U && phase >= 5000U && phase < 6200U)) {
        static const int heights[] = {0, -1, -3, -3, -1, 0};
        const uint32_t jump_ms = play_jump ? pet->feedback_elapsed_ms : phase - 5000U;
        pose->kind = PET_ANIM_JUMP;
        pose->y_offset = heights[jump_ms / 200U % 6U];
    } else if (pet->energy > 35U && phase >= 7000U && phase < 10200U) {
        const uint32_t step = (phase - 7000U) / 200U;
        const int distance = (int)(step < 8U ? step : 15U - step);
        pose->kind = PET_ANIM_WALK;
        pose->x_offset = (choice & 1U) != 0U ? distance : -distance;
        pose->phase = (uint8_t)(step % 2U);
    }
    /* One pseudo-randomly timed blink per 6s window, also while walking. */
    const uint32_t blink_at = 600U + mix(time_ms / 6000U + 77U) % 4000U;
    if (!pose->eyes_closed && time_ms % 6000U >= blink_at &&
        time_ms % 6000U < blink_at + 220U) {
        pose->eyes_closed = true;
        if (pose->kind == PET_ANIM_IDLE) { pose->kind = PET_ANIM_BLINK; }
    }
}
