#include "motion.h"
#include <limits.h>

void motion_disconnect(MotionState *state)
{
    state->connected = false;
    state->filtered = false;
    state->had_activity = false;
    state->had_shake = false;
    state->behavior = MOTION_IDLE;
}

void motion_sample(MotionState *state, int32_t x, int32_t y, int32_t z, uint32_t now)
{
    const int32_t axes[] = {x, y, z};
    const uint32_t elapsed = now - state->last_sample_ms;
    const bool continuous = state->filtered && elapsed <= 150U;
    uint32_t movement = 0;
    for (unsigned i = 0; i < 3; ++i) {
        if (!continuous) { state->gravity[i] = axes[i]; }
        int32_t dynamic = axes[i] - state->gravity[i];
        movement += (uint32_t)(dynamic < 0 ? -dynamic : dynamic);
        state->gravity[i] += dynamic / 8;
    }
    if (!continuous) {
        state->had_activity = false;
        state->had_shake = false;
    }
    /* Prototype thresholds in mg, to be calibrated with the mounted bag. */
    if (movement >= 150U) { state->activity_ms = now; state->had_activity = true; }
    if (movement >= 1200U) { state->shake_ms = now; state->had_shake = true; }
    const bool active = state->had_activity && (uint32_t)(now - state->activity_ms) < 1500U;
    const bool shake = state->had_shake && (uint32_t)(now - state->shake_ms) < 3000U;
    state->behavior = shake ? MOTION_SHAKE : active ? MOTION_ACTIVE : MOTION_IDLE;
    if (continuous && active) {
        state->active_ms = UINT32_MAX - state->active_ms < elapsed ? UINT32_MAX : state->active_ms + elapsed;
    }
    state->x_mg = x;
    state->y_mg = y;
    state->z_mg = z;
    state->last_sample_ms = now;
    state->samples++;
    state->connected = true;
    state->filtered = true;
}
