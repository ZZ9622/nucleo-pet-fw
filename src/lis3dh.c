#include "motion.h"
#include "board_i2c.h"

static MotionState state;
static uint8_t address;
static bool configured;
static uint32_t last_poll_ms, retry_ms;

void lis3dh_init(void)
{
    state = (MotionState){0};
    configured = false;
    retry_ms = 100U;
    last_poll_ms = 0;
}

const MotionState *lis3dh_state(void) { return &state; }

static bool configure(void)
{
    uint8_t identity;
    for (unsigned candidate = 0x19U; candidate >= 0x18U; --candidate) {
        if (board_i2c_read_register((uint8_t)candidate, 0x0f, &identity) && identity == 0x33U) {
            address = (uint8_t)candidate;
            /* ±2g, high resolution (1 mg/LSB), block data update. */
            const uint8_t ctrl4 = 0x88U;
            const uint8_t ctrl1 = 0x47U; /* 50 Hz, all three axes enabled. */
            return board_i2c_write(address, 0x23U, &ctrl4, 1U) &&
                   board_i2c_write(address, 0x20U, &ctrl1, 1U);
        }
    }
    return false;
}

void lis3dh_poll(uint32_t now)
{
    if (!configured) {
        if ((int32_t)(now - retry_ms) < 0) { return; }
        configured = configure();
        retry_ms = now + 1000U;
        if (!configured) { motion_disconnect(&state); return; }
        last_poll_ms = now;
        state.last_sample_ms = now;
        return;
    }
    if ((uint32_t)(now - last_poll_ms) < 40U) { return; }
    last_poll_ms = now;
    uint8_t status;
    if (!board_i2c_read_register(address, 0x27U, &status)) { goto disconnected; }
    if ((status & 8U) == 0U) {
        if ((uint32_t)(now - state.last_sample_ms) > 250U) { goto disconnected; }
        return;
    }
    uint8_t data[6];
    for (unsigned i = 0; i < sizeof data; ++i) {
        if (!board_i2c_read_register(address, (uint8_t)(0x28U + i), &data[i])) { goto disconnected; }
    }
    int32_t axes[3];
    for (unsigned i = 0; i < 3; ++i) {
        int32_t word = (int32_t)((uint32_t)data[2U*i] | ((uint32_t)data[2U*i+1U] << 8));
        if (word >= 32768) { word -= 65536; }
        axes[i] = word / 16;
    }
    motion_sample(&state, axes[0], axes[1], axes[2], now);
    return;
disconnected:
    motion_disconnect(&state);
    configured = false;
    retry_ms = now + 1000U;
}
