#include "board_i2c.h"
#include "board.h"
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
void board_i2c_init(void)
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
bool board_i2c_write(uint8_t address, uint8_t control, const uint8_t *bytes, size_t count)
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
    board_i2c_init();
    return false;
}


bool board_i2c_read_register(uint8_t address, uint8_t reg, uint8_t *value)
{
    const uint32_t started = board_millis();
    while ((I2C1->SR2 & BUSY) != 0U) {
        if ((uint32_t)(board_millis() - started) >= 20U) { goto fail; }
    }
    I2C1->CR1 |= START;
    if (!wait_flag(SB, started)) { goto fail; }
    I2C1->DR = (uint32_t)address << 1;
    if (!wait_flag(ADDR, started)) { goto fail; }
    (void)I2C1->SR1;
    (void)I2C1->SR2;
    if (!wait_flag(TXE, started)) { goto fail; }
    I2C1->DR = reg;
    if (!wait_flag(BTF, started)) { goto fail; }

    I2C1->CR1 |= START;
    if (!wait_flag(SB, started)) { goto fail; }
    I2C1->DR = ((uint32_t)address << 1) | 1U;
    if (!wait_flag(ADDR, started)) { goto fail; }
    /* RM0368 single-byte receive: clear ACK before ADDR, then issue STOP.
     * Keep this short sequence atomic against UART/SysTick interrupts. */
    uint32_t interrupts;
    __asm volatile("mrs %0, primask\n cpsid i" : "=r"(interrupts) :: "memory");
    I2C1->CR1 &= ~(1UL << 10);
    (void)I2C1->SR1;
    (void)I2C1->SR2;
    I2C1->CR1 |= STOP;
    __asm volatile("msr primask, %0" :: "r"(interrupts) : "memory");
    if (!wait_flag(1U << 6, started)) { goto fail; }
    *value = (uint8_t)I2C1->DR;
    return true;
fail:
    if ((I2C1->SR2 & 1U) != 0U) { I2C1->CR1 |= STOP; }
    board_i2c_init();
    return false;
}
