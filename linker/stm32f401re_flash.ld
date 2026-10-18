/* STM32F401RE: 512 KiB Flash at 0x08000000 and 96 KiB SRAM at 0x20000000. */
ENTRY(Reset_Handler)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 512K
    RAM (xrw)   : ORIGIN = 0x20000000, LENGTH = 96K
}

__StackSize = 0x800;
__StackTop = ORIGIN(RAM) + LENGTH(RAM);
__StackLimit = __StackTop - __StackSize;
_estack = __StackTop;

SECTIONS
{
    .isr_vector :
    {
        . = ALIGN(4);
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    } > FLASH

    .text :
    {
        . = ALIGN(4);
        *(.text*)
        *(.rodata*)
        *(.glue_7*)
        . = ALIGN(4);
        _etext = .;
    } > FLASH

    .data : AT(_etext)
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM
    _sidata = LOADADDR(.data);

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    . = ALIGN(8);
    _end = .;

    ASSERT(_end <= __StackLimit, "RAM overflow: data collides with reserved stack")

    /*
     * The top 2 KiB stays unallocated for MSP stack frames. The assertion
     * above catches normal data/BSS growth before it can collide with stack.
     * A section is deliberately not emitted here, so size reports show the
     * actual static-RAM use rather than the whole reserved address range.
     */
}
