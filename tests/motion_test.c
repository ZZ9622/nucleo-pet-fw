#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include "motion.h"

int main(void)
{
    MotionState state = {0};
    for (uint32_t time = 0; time < 1000; time += 40) {
        motion_sample(&state, 250, -970, 320, time);
    }
    assert(state.connected && state.behavior == MOTION_IDLE);
    assert(state.active_ms == 0);
    motion_sample(&state, 500, -970, 320, 1000);
    assert(state.behavior == MOTION_ACTIVE && state.active_ms == 40);
    motion_sample(&state, -1500, 900, 300, 1040);
    assert(state.behavior == MOTION_SHAKE);
    for (uint32_t time = 1080; time < 7000; time += 40) {
        motion_sample(&state, -1500, 900, 300, time);
    }
    assert(state.behavior == MOTION_IDLE);
    assert(state.active_ms > 0 && state.active_ms < 7000);

    const uint32_t saved = state.active_ms;
    motion_disconnect(&state);
    assert(!state.connected);
    motion_sample(&state, 0, 0, 1000, 500000);
    assert(state.behavior == MOTION_IDLE && state.active_ms == saved);

    MotionState wrap = {0};
    motion_sample(&wrap, 0, 0, 1000, UINT32_MAX - 20U);
    motion_sample(&wrap, 300, 0, 1000, 19);
    assert(wrap.behavior == MOTION_ACTIVE && wrap.active_ms == 40U);
    wrap.active_ms = UINT32_MAX - 1U;
    motion_sample(&wrap, 600, 0, 1000, 59);
    assert(wrap.active_ms == UINT32_MAX);
    motion_sample(&wrap, -600, 0, 1000, 5000);
    assert(wrap.behavior == MOTION_IDLE); /* Sampling gaps do not create motion. */
    puts("motion classifier tests: passed");
    return 0;
}
