BUILD_DIR := build/nucleo-f401re
TOOLCHAIN := cmake/arm-none-eabi-gcc.cmake

.PHONY: all configure build flash probe test clean

all: build

configure: $(BUILD_DIR)/CMakeCache.txt

$(BUILD_DIR)/CMakeCache.txt:
	cmake -S . -B $(BUILD_DIR) -G "Unix Makefiles" \
		-DCMAKE_TOOLCHAIN_FILE=$(TOOLCHAIN)

build: configure
	cmake --build $(BUILD_DIR)

flash: build
	cmake --build $(BUILD_DIR) --target flash

# Read-only check: confirms that OpenOCD can see the ST-LINK and STM32 target.
probe:
	openocd -f openocd/nucleo-f401re.cfg -c "init; targets; shutdown"

test:
	mkdir -p build/host-tests
	$(CC) -std=c11 -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes \
		-Iinclude tests/pet_test.c src/pet.c -o build/host-tests/pet_test
	build/host-tests/pet_test
	$(CC) -std=c11 -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes \
		-Iinclude tests/pet_view_test.c src/pet_view.c -o build/host-tests/pet_view_test
	build/host-tests/pet_view_test

clean:
	rm -rf build
