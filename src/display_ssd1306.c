#include <stddef.h>
#include <stdint.h>
#include "board.h"
#include "display.h"
#include "pet_view.h"
#include "stm32f401xe_minimal.h"

/* RM0368: I2C1 registers; board.c leaves APB1 at the reset HSI 16 MHz. */
typedef struct {
    volatile uint32_t CR1, CR2, OAR1, OAR2, DR, SR1, SR2, CCR, TRISE, FLTR;
} I2cRegisters;
#define I2C1 ((I2cRegisters *)0x40005400UL)
#define APB1RSTR (*(volatile uint32_t *)0x40023820UL)
#define APB1ENR  (*(volatile uint32_t *)0x40023840UL)
#define GPIOB ((GPIO_TypeDef *)0x40020400UL)
enum { PE = 1U, START = 1U << 8, STOP = 1U << 9,
       SB = 1U, ADDR = 1U << 1, BTF = 1U << 2, TXE = 1U << 7,
       BUSY = 1U << 1, ERRORS = 0x0F00U };
static uint8_t address;
static uint8_t page;
static uint8_t column;
static uint8_t frame[1024];
static bool frame_is_test;
static bool ready;
static uint32_t next_attempt_ms;
static uint32_t test_started_ms;
/* Inspect in a debugger: 0 waiting, 1 no ACK/bus error, 2 test, 3 pet view. */
volatile uint32_t oled_status;

static void bus_init(void)
{
    RCC->AHB1ENR |= 1U << 1;
    (void)RCC->AHB1ENR;
    /* PB8/PB9 AF4, open drain. External pull-ups to 3.3 V are required. */
    GPIOB->MODER = (GPIOB->MODER & ~((3UL << 16) | (3UL << 18))) |
                    (2UL << 16) | (2UL << 18);
    GPIOB->OTYPER |= (1UL << 8) | (1UL << 9);
    GPIOB->OSPEEDR |= (3UL << 16) | (3UL << 18);
    GPIOB->PUPDR &= ~((3UL << 16) | (3UL << 18));
    GPIOB->AFR[1] = (GPIOB->AFR[1] & ~0xFFUL) | 0x44UL;
    APB1ENR |= 1UL << 21;
    (void)APB1ENR;
    APB1RSTR |= 1UL << 21;
    APB1RSTR &= ~(1UL << 21);
    I2C1->CR2 = 16U;
    I2C1->CCR = 80U; /* Standard mode: 16 MHz / (2 * 80) = 100 kHz. */
    I2C1->TRISE = 17U;
    I2C1->CR1 = PE;
}

static bool wait_flag(uint32_t flag, uint32_t started)
{
    for (;;) {
        uint32_t status = I2C1->SR1;
        if ((status & ERRORS) != 0U) { return false; }
        if ((status & flag) != 0U) { return true; }
        if ((uint32_t)(board_millis() - started) >= 20U) { return false; }
    }
}

/* One deadline covers the entire transfer, including missing ACK or stuck SCL. */
static bool send_bytes(uint8_t control, const uint8_t *bytes, size_t count)
{
    uint32_t started = board_millis();
    while ((I2C1->SR2 & BUSY) != 0U) {
        if ((uint32_t)(board_millis() - started) >= 20U) { goto fail; }
    }
    I2C1->CR1 |= START;
    if (!wait_flag(SB, started)) { goto fail; }
    I2C1->DR = (uint32_t)address << 1;
    if (!wait_flag(ADDR, started)) { goto fail; }
    (void)I2C1->SR1;
    (void)I2C1->SR2; /* Clear ADDR in the documented order. */
    if (!wait_flag(TXE, started)) { goto fail; }
    I2C1->DR = control;
    for (size_t i = 0U; i < count; ++i) {
        if (!wait_flag(TXE, started)) { goto fail; }
        I2C1->DR = bytes[i];
    }
    if (!wait_flag(BTF, started)) { goto fail; }
    I2C1->CR1 |= STOP;
    return true;
fail:
    /* STOP only while master: avoid driving a bus owned by another master. */
    if ((I2C1->SR2 & 1U) != 0U) { I2C1->CR1 |= STOP; }
    bus_init();
    return false;
}

void display_init(void)
{
    bus_init();
    ready = false;
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
        0xDB, 0x40, 0xA4, 0xA6, 0x2E, 0xAF
    };
    address = 0x3CU;
    if (send_bytes(0x00, commands, sizeof commands)) { return true; }
    address = 0x3DU;
    return send_bytes(0x00, commands, sizeof commands);
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
        page = 0U;
        column = 0U;
        test_started_ms = board_millis();
        now = test_started_ms;
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
        ready = false;
        oled_status = 1U;
        next_attempt_ms = board_millis() + 1000U;
        return;
    }
    oled_status = frame_is_test ? 2U : 3U;
    column = (uint8_t)(column + 32U);
    if (column == 128U) {
        column = 0U;
        page = (uint8_t)((page + 1U) % 8U);
    }
}
