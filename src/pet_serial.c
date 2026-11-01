#include "pet_serial.h"
#include "stm32f401xe_minimal.h"
#include <stddef.h>

typedef struct { volatile uint32_t SR, DR, BRR, CR1, CR2, CR3, GTPR; } Uart;
#define UART2 ((Uart *)0x40004400UL)
#define APB1ENR (*(volatile uint32_t *)0x40023840UL)
static char tx[128];
static size_t count, sent;
static uint32_t sequence;
static void append(const char *s) { while (*s) { tx[count++] = *s++; } }
static void number(uint32_t n)
{
    char digits[10]; unsigned used = 0;
    do { digits[used++] = (char)('0' + n % 10U); n /= 10U; } while (n);
    while (used) { tx[count++] = digits[--used]; }
}
void pet_serial_init(void)
{
    GPIOA->MODER = (GPIOA->MODER & ~0xF0UL) | 0xA0UL;
    GPIOA->AFR[0] = (GPIOA->AFR[0] & ~0xFF00UL) | 0x7700UL;
    GPIOA->PUPDR = (GPIOA->PUPDR & ~0xF0UL) | 0x40UL;
    APB1ENR |= 1UL << 17;
    (void)APB1ENR;
    /* Reset clock: APB1 = 16 MHz. 9600 baud, 8N1. */
    UART2->CR1 = 0;
    UART2->BRR = 1667U;
    UART2->CR2 = 0;
    UART2->CR3 = 0;
    UART2->CR1 = (1U << 13) | (1U << 3) | (1U << 2);
}
void pet_serial_poll(const PetState *pet)
{
    const uint32_t status = UART2->SR;
    if (status & ((1U << 5) | (1U << 3))) {
        const uint32_t byte = UART2->DR; /* SR then DR clears RXNE/ORE. */
        if (!(status & 0xFU) && byte == '?' && sent == count) {
            sent = count = 0;
            if (++sequence == 0U) { sequence = 1U; }
            append("{\"v\":1,\"seq\":"); number(sequence);
            append(",\"energy\":"); number(pet->energy);
            append(",\"happiness\":"); number(pet->happiness);
            append(",\"sleeping\":"); append(pet->is_sleeping ? "true" : "false");
            append("}\n");
        }
    }
    if (sent < count && (UART2->SR & (1U << 7))) {
        UART2->DR = (uint8_t)tx[sent++];
    }
}
