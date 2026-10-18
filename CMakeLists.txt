cmake_minimum_required(VERSION 3.20)

project(nucleo_pet_fw LANGUAGES C)

if(NOT CMAKE_CROSSCOMPILING)
    message(FATAL_ERROR "Use cmake/arm-none-eabi-gcc.cmake to configure this firmware.")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)

set(FIRMWARE_SOURCES
    src/startup.c
    src/board.c
    src/button.c
    src/display_null.c
    src/led.c
    src/main.c
    src/pet.c
)

add_executable(pet.elf ${FIRMWARE_SOURCES})
set_target_properties(pet.elf PROPERTIES OUTPUT_NAME pet SUFFIX ".elf")

target_include_directories(pet.elf PRIVATE include)

target_compile_options(pet.elf PRIVATE
    -mcpu=cortex-m4
    -mthumb
    -mfloat-abi=soft
    -ffreestanding
    -fno-builtin
    -fdata-sections
    -ffunction-sections
    -fno-unwind-tables
    -fno-asynchronous-unwind-tables
    -Og
    -g3
    -Wall
    -Wextra
    -Werror
    -Wshadow
    -Wstrict-prototypes
)

target_link_options(pet.elf PRIVATE
    -mcpu=cortex-m4
    -mthumb
    -mfloat-abi=soft
    -T${CMAKE_CURRENT_SOURCE_DIR}/linker/stm32f401re_flash.ld
    -Wl,--gc-sections
    -Wl,--print-memory-usage
    -Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/pet.map
    -nostartfiles
    -nostdlib
)

target_link_libraries(pet.elf PRIVATE gcc)

add_custom_command(TARGET pet.elf POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary
        $<TARGET_FILE:pet.elf> ${CMAKE_CURRENT_BINARY_DIR}/pet.bin
    COMMAND ${CMAKE_OBJCOPY} -O ihex
        $<TARGET_FILE:pet.elf> ${CMAKE_CURRENT_BINARY_DIR}/pet.hex
    COMMAND ${CMAKE_SIZE} $<TARGET_FILE:pet.elf>
    BYPRODUCTS
        ${CMAKE_CURRENT_BINARY_DIR}/pet.bin
        ${CMAKE_CURRENT_BINARY_DIR}/pet.hex
    COMMENT "Creating pet.bin and pet.hex"
)

find_program(OPENOCD_EXECUTABLE openocd)
if(OPENOCD_EXECUTABLE)
    add_custom_target(flash
        COMMAND ${OPENOCD_EXECUTABLE}
            -f ${CMAKE_CURRENT_SOURCE_DIR}/openocd/nucleo-f401re.cfg
            -c "program $<TARGET_FILE:pet.elf> verify reset exit"
        DEPENDS pet.elf
        USES_TERMINAL
        COMMENT "Programming NUCLEO-F401RE through its onboard ST-LINK"
    )
else()
    add_custom_target(flash
        COMMAND ${CMAKE_COMMAND} -E echo
            "OpenOCD was not found. Install it, then rerun CMake before flashing."
        COMMAND ${CMAKE_COMMAND} -E false
        DEPENDS pet.elf
        COMMENT "OpenOCD is required to flash the NUCLEO-F401RE"
    )
endif()
