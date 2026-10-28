#include "board.h"
#include "stm32f401xe_minimal.h"

enum {
    BOARD_HSI_HZ = 16000000UL,
    BOARD_TICK_HZ = 1000UL,
    LED_PIN = 5U,
    BUTTON_PIN = 13U
};

static volatile uint32_t g_millis;
static GPIO_TypeDef *const action_ports[BOARD_ACTION_COUNT] = {
    GPIOA, GPIOA, GPIOA, (GPIO_TypeDef *)0x40020400UL
};
static const uint8_t action_pins[BOARD_ACTION_COUNT] = {0U, 1U, 4U, 0U};

void board_init(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN | (1UL << 1) | RCC_AHB1ENR_GPIOCEN;
    (void)RCC->AHB1ENR;

    /* PA5: LD2, push-pull output, low speed, no pull resistor. */
    GPIOA->MODER &= ~(3UL << (LED_PIN * 2U));
    GPIOA->MODER |= 1UL << (LED_PIN * 2U);
    GPIOA->OTYPER &= ~(1UL << LED_PIN);
    GPIOA->OSPEEDR &= ~(3UL << (LED_PIN * 2U));
    GPIOA->PUPDR &= ~(3UL << (LED_PIN * 2U));
    board_led_write(false);

    /* PC13: B1 USER, active-low and already pulled up on the Nucleo board. */
    GPIOC->MODER &= ~(3UL << (BUTTON_PIN * 2U));
    GPIOC->PUPDR &= ~(3UL << (BUTTON_PIN * 2U));

    for (unsigned i = 0U; i < BOARD_ACTION_COUNT; ++i) {
        const unsigned shift = action_pins[i] * 2U;
        action_ports[i]->MODER &= ~(3UL << shift); /* input */
        action_ports[i]->PUPDR = (action_ports[i]->PUPDR & ~(3UL << shift)) |
                                 (1UL << shift); /* pull-up */
    }

    SysTick->LOAD = (BOARD_HSI_HZ / BOARD_TICK_HZ) - 1UL;
    SysTick->VAL = 0UL;
    SysTick->CTRL = SYSTICK_CTRL_CLKSOURCE | SYSTICK_CTRL_TICKINT |
                    SYSTICK_CTRL_ENABLE;
}

void SysTick_Handler(void)
{
    g_millis++;
}

uint32_t board_millis(void)
{
    return g_millis;
}

void board_led_write(bool on)
{
    if (on) {
        GPIOA->BSRR = 1UL << LED_PIN;
    } else {
        GPIOA->BSRR = 1UL << (LED_PIN + 16U);
    }
}

bool board_button_pressed(void)
{
    return (GPIOC->IDR & (1UL << BUTTON_PIN)) == 0UL;
}

void board_idle(void)
{
    __asm volatile("wfi");
}

bool board_action_pressed(BoardAction action)
{
    if ((unsigned)action >= BOARD_ACTION_COUNT) { return false; }
    return (action_ports[action]->IDR & (1UL << action_pins[action])) == 0U;
}
