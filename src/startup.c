#include <stdint.h>

typedef void (*IsrHandler)(void);

extern uint32_t _estack;
extern uint32_t _sidata;
extern uint32_t _sdata;
extern uint32_t _edata;
extern uint32_t _sbss;
extern uint32_t _ebss;

int main(void);
void Reset_Handler(void);
void Default_Handler(void);

#define WEAK_DEFAULT(handler) \
    void handler(void) __attribute__((weak, alias("Default_Handler")))

WEAK_DEFAULT(NMI_Handler);
WEAK_DEFAULT(HardFault_Handler);
WEAK_DEFAULT(MemManage_Handler);
WEAK_DEFAULT(BusFault_Handler);
WEAK_DEFAULT(UsageFault_Handler);
WEAK_DEFAULT(SVC_Handler);
WEAK_DEFAULT(DebugMon_Handler);
WEAK_DEFAULT(PendSV_Handler);
WEAK_DEFAULT(SysTick_Handler);

/* STM32F401xE external IRQ names and order from ST's GCC startup template. */
WEAK_DEFAULT(WWDG_IRQHandler);
WEAK_DEFAULT(PVD_IRQHandler);
WEAK_DEFAULT(TAMP_STAMP_IRQHandler);
WEAK_DEFAULT(RTC_WKUP_IRQHandler);
WEAK_DEFAULT(FLASH_IRQHandler);
WEAK_DEFAULT(RCC_IRQHandler);
WEAK_DEFAULT(EXTI0_IRQHandler);
WEAK_DEFAULT(EXTI1_IRQHandler);
WEAK_DEFAULT(EXTI2_IRQHandler);
WEAK_DEFAULT(EXTI3_IRQHandler);
WEAK_DEFAULT(EXTI4_IRQHandler);
WEAK_DEFAULT(DMA1_Stream0_IRQHandler);
WEAK_DEFAULT(DMA1_Stream1_IRQHandler);
WEAK_DEFAULT(DMA1_Stream2_IRQHandler);
WEAK_DEFAULT(DMA1_Stream3_IRQHandler);
WEAK_DEFAULT(DMA1_Stream4_IRQHandler);
WEAK_DEFAULT(DMA1_Stream5_IRQHandler);
WEAK_DEFAULT(DMA1_Stream6_IRQHandler);
WEAK_DEFAULT(ADC_IRQHandler);
WEAK_DEFAULT(EXTI9_5_IRQHandler);
WEAK_DEFAULT(TIM1_BRK_TIM9_IRQHandler);
WEAK_DEFAULT(TIM1_UP_TIM10_IRQHandler);
WEAK_DEFAULT(TIM1_TRG_COM_TIM11_IRQHandler);
WEAK_DEFAULT(TIM1_CC_IRQHandler);
WEAK_DEFAULT(TIM2_IRQHandler);
WEAK_DEFAULT(TIM3_IRQHandler);
WEAK_DEFAULT(TIM4_IRQHandler);
WEAK_DEFAULT(I2C1_EV_IRQHandler);
WEAK_DEFAULT(I2C1_ER_IRQHandler);
WEAK_DEFAULT(I2C2_EV_IRQHandler);
WEAK_DEFAULT(I2C2_ER_IRQHandler);
WEAK_DEFAULT(SPI1_IRQHandler);
WEAK_DEFAULT(SPI2_IRQHandler);
WEAK_DEFAULT(USART1_IRQHandler);
WEAK_DEFAULT(USART2_IRQHandler);
WEAK_DEFAULT(EXTI15_10_IRQHandler);
WEAK_DEFAULT(RTC_Alarm_IRQHandler);
WEAK_DEFAULT(OTG_FS_WKUP_IRQHandler);
WEAK_DEFAULT(DMA1_Stream7_IRQHandler);
WEAK_DEFAULT(SDIO_IRQHandler);
WEAK_DEFAULT(TIM5_IRQHandler);
WEAK_DEFAULT(SPI3_IRQHandler);
WEAK_DEFAULT(DMA2_Stream0_IRQHandler);
WEAK_DEFAULT(DMA2_Stream1_IRQHandler);
WEAK_DEFAULT(DMA2_Stream2_IRQHandler);
WEAK_DEFAULT(DMA2_Stream3_IRQHandler);
WEAK_DEFAULT(DMA2_Stream4_IRQHandler);
WEAK_DEFAULT(OTG_FS_IRQHandler);
WEAK_DEFAULT(DMA2_Stream5_IRQHandler);
WEAK_DEFAULT(DMA2_Stream6_IRQHandler);
WEAK_DEFAULT(DMA2_Stream7_IRQHandler);
WEAK_DEFAULT(USART6_IRQHandler);
WEAK_DEFAULT(I2C3_EV_IRQHandler);
WEAK_DEFAULT(I2C3_ER_IRQHandler);
WEAK_DEFAULT(FPU_IRQHandler);
WEAK_DEFAULT(SPI4_IRQHandler);

/*
 * The F401xE has 85 external interrupt slots. Named weak aliases let a later
 * UART, I2C, EXTI, DMA, or display driver supply a normal strong handler.
 */
__attribute__((section(".isr_vector"), used))
const IsrHandler g_vector_table[101] = {
    [0] = (IsrHandler)&_estack,
    [1] = Reset_Handler,
    [2] = NMI_Handler,
    [3] = HardFault_Handler,
    [4] = MemManage_Handler,
    [5] = BusFault_Handler,
    [6] = UsageFault_Handler,
    [7] = 0,
    [8] = 0,
    [9] = 0,
    [10] = 0,
    [11] = SVC_Handler,
    [12] = DebugMon_Handler,
    [13] = 0,
    [14] = PendSV_Handler,
    [15] = SysTick_Handler,

    [16] = WWDG_IRQHandler,
    [17] = PVD_IRQHandler,
    [18] = TAMP_STAMP_IRQHandler,
    [19] = RTC_WKUP_IRQHandler,
    [20] = FLASH_IRQHandler,
    [21] = RCC_IRQHandler,
    [22] = EXTI0_IRQHandler,
    [23] = EXTI1_IRQHandler,
    [24] = EXTI2_IRQHandler,
    [25] = EXTI3_IRQHandler,
    [26] = EXTI4_IRQHandler,
    [27] = DMA1_Stream0_IRQHandler,
    [28] = DMA1_Stream1_IRQHandler,
    [29] = DMA1_Stream2_IRQHandler,
    [30] = DMA1_Stream3_IRQHandler,
    [31] = DMA1_Stream4_IRQHandler,
    [32] = DMA1_Stream5_IRQHandler,
    [33] = DMA1_Stream6_IRQHandler,
    [34] = ADC_IRQHandler,
    [35] = 0,
    [36] = 0,
    [37] = 0,
    [38] = 0,
    [39] = EXTI9_5_IRQHandler,
    [40] = TIM1_BRK_TIM9_IRQHandler,
    [41] = TIM1_UP_TIM10_IRQHandler,
    [42] = TIM1_TRG_COM_TIM11_IRQHandler,
    [43] = TIM1_CC_IRQHandler,
    [44] = TIM2_IRQHandler,
    [45] = TIM3_IRQHandler,
    [46] = TIM4_IRQHandler,
    [47] = I2C1_EV_IRQHandler,
    [48] = I2C1_ER_IRQHandler,
    [49] = I2C2_EV_IRQHandler,
    [50] = I2C2_ER_IRQHandler,
    [51] = SPI1_IRQHandler,
    [52] = SPI2_IRQHandler,
    [53] = USART1_IRQHandler,
    [54] = USART2_IRQHandler,
    [55] = 0,
    [56] = EXTI15_10_IRQHandler,
    [57] = RTC_Alarm_IRQHandler,
    [58] = OTG_FS_WKUP_IRQHandler,
    [59] = 0,
    [60] = 0,
    [61] = 0,
    [62] = 0,
    [63] = DMA1_Stream7_IRQHandler,
    [64] = 0,
    [65] = SDIO_IRQHandler,
    [66] = TIM5_IRQHandler,
    [67] = SPI3_IRQHandler,
    [68] = 0,
    [69] = 0,
    [70] = 0,
    [71] = 0,
    [72] = DMA2_Stream0_IRQHandler,
    [73] = DMA2_Stream1_IRQHandler,
    [74] = DMA2_Stream2_IRQHandler,
    [75] = DMA2_Stream3_IRQHandler,
    [76] = DMA2_Stream4_IRQHandler,
    [77] = 0,
    [78] = 0,
    [79] = 0,
    [80] = 0,
    [81] = 0,
    [82] = 0,
    [83] = OTG_FS_IRQHandler,
    [84] = DMA2_Stream5_IRQHandler,
    [85] = DMA2_Stream6_IRQHandler,
    [86] = DMA2_Stream7_IRQHandler,
    [87] = USART6_IRQHandler,
    [88] = I2C3_EV_IRQHandler,
    [89] = I2C3_ER_IRQHandler,
    [90] = 0,
    [91] = 0,
    [92] = 0,
    [93] = 0,
    [94] = 0,
    [95] = 0,
    [96] = 0,
    [97] = FPU_IRQHandler,
    [98] = 0,
    [99] = 0,
    [100] = SPI4_IRQHandler
};

void Reset_Handler(void)
{
    uint32_t *source = &_sidata;
    uint32_t *destination = &_sdata;

    while (destination < &_edata) {
        *destination = *source;
        destination++;
        source++;
    }

    destination = &_sbss;
    while (destination < &_ebss) {
        *destination = 0U;
        destination++;
    }

    (void)main();
    Default_Handler();
}

void Default_Handler(void)
{
    while (1) {
        __asm volatile("wfi");
    }
}
