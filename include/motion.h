#ifndef MOTION_H
#define MOTION_H
#include <stdbool.h>
#include <stdint.h>
typedef enum { MOTION_IDLE = 0, MOTION_ACTIVE = 1, MOTION_SHAKE = 2 } MotionBehavior;
typedef struct {
    int32_t x_mg, y_mg, z_mg;
    uint32_t samples, last_sample_ms, active_ms;
    MotionBehavior behavior;
    bool connected;
    /* Gravity filter and hold times are transient, never pet save data. */
    int32_t gravity[3];
    uint32_t activity_ms, shake_ms;
    bool filtered, had_activity, had_shake;
} MotionState;
void motion_sample(MotionState *state, int32_t x, int32_t y, int32_t z, uint32_t now);
void motion_disconnect(MotionState *state);
void lis3dh_init(void);
void lis3dh_poll(uint32_t now);
const MotionState *lis3dh_state(void);
#endif
