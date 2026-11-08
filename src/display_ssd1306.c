#include <stddef.h>
#include <stdint.h>
#include "board.h"
#include "board_i2c.h"
#include "display.h"
#include "pet_view.h"
#include "stm32f401xe_minimal.h"

static uint8_t address;
static uint8_t page;
static uint8_t column;
static uint8_t frame[1024];
static bool frame_is_test;
static bool ready;
static bool desired_awake;
static bool panel_awake;
static uint32_t next_attempt_ms;
static uint32_t test_started_ms;
/* Inspect in a debugger: 0 waiting, 1 no ACK/bus error, 2 test, 3 pet view, 4 idle off. */
volatile uint32_t oled_status;

static bool send_bytes(uint8_t control, const uint8_t *bytes, size_t count)
{
    return board_i2c_write(address, control, bytes, count);
}

void display_init(void)
{
    board_i2c_init();
    ready = false;
    desired_awake = true;
    panel_awake = false;
    page = 0U;
    column = 0U;
    oled_status = 0U;
    next_attempt_ms = board_millis() + 100U; /* OLED power stabilization. */
}

static bool initialize_panel(void)
{
    static const uint8_t commands[] = {
        0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40,
        0x8D, 0x14, 0x20, 0x02, /* charge pump on, page addressing */
        0xA1, 0xC8, 0xDA, 0x12, 0x81, 0x7F, 0xD9, 0xF1,
        0xDB, 0x40, 0xA4, 0xA6, 0x2E /* Leave off until a full frame is loaded. */
    };
    address = 0x3CU;
    if (send_bytes(0x00, commands, sizeof commands)) { return true; }
    address = 0x3DU;
    return send_bytes(0x00, commands, sizeof commands);
}

void display_set_awake(bool awake)
{
    if (desired_awake != awake) {
        desired_awake = awake;
        page = 0U;
        column = 0U;
    }
}

static void display_transfer_failed(void)
{
    ready = false;
    oled_status = 1U;
    next_attempt_ms = board_millis() + 1000U;
}

void display_render(const PetSnapshot *snapshot)
{
    uint32_t now = board_millis();
    if (!ready) {
        if ((int32_t)(now - next_attempt_ms) < 0) { return; }
        ready = initialize_panel();
        if (!ready) {
            oled_status = 1U;
            next_attempt_ms = board_millis() + 1000U;
            return;
        }
        panel_awake = false;
        page = 0U;
        column = 0U;
        test_started_ms = board_millis();
        now = test_started_ms;
    }
    if (!desired_awake) {
        if (panel_awake) {
            const uint8_t off = 0xAEU;
            if (!send_bytes(0x00, &off, 1U)) {
                display_transfer_failed();
                return;
            }
            panel_awake = false;
        }
        oled_status = 4U;
        return; /* No framebuffer rendering or refresh while dark. */
    }
    /* Latch one complete image; all pages use the same animation time/state. */
    if (page == 0U && column == 0U) {
        frame_is_test = (uint32_t)(now - test_started_ms) < 2500U;
        if (frame_is_test) {
            for (unsigned y = 0U; y < 8U; ++y) {
                for (unsigned x = 0U; x < 128U; ++x) {
                    frame[y * 128U + x] = ((x / 8U + y) % 2U == 0U) ? 0xFFU : 0U;
                }
            }
        } else {
            pet_view_draw(frame, snapshot, now - test_started_ms - 2500U);
        }
    }
    /* 32 bytes (~3 ms at 100 kHz) per call, allowing input between chunks. */
    const uint8_t position[] = {(uint8_t)(0xB0U + page),
                               (uint8_t)(column & 0x0FU),
                               (uint8_t)(0x10U | (column >> 4))};
    if (!send_bytes(0x00, position, sizeof position) ||
        !send_bytes(0x40, &frame[(unsigned)page * 128U + column], 32U)) {
        display_transfer_failed();
        return;
    }
    oled_status = frame_is_test ? 2U : 3U;
    column = (uint8_t)(column + 32U);
    if (column == 128U) {
        column = 0U;
        page = (uint8_t)((page + 1U) % 8U);
        if (page == 0U && !panel_awake) {
            const uint8_t on = 0xAFU;
            if (!send_bytes(0x00, &on, 1U)) {
                display_transfer_failed();
                return;
            }
            panel_awake = true;
        }
    }
}
