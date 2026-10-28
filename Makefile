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
		-Iinclude tests/pet_view_test.c src/pet_view.c src/pet_animation.c -o build/host-tests/pet_view_test
	build/host-tests/pet_view_test
	$(CC) -std=c11 -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes \
		-Iinclude tests/button_test.c src/button.c -o build/host-tests/button_test
	build/host-tests/button_test
	$(CC) -std=c11 -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes \
		-Iinclude tests/screen_idle_test.c src/screen_idle.c src/button.c src/pet.c -o build/host-tests/screen_idle_test
	build/host-tests/screen_idle_test
	$(CC) -std=c11 -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes \
		-Iinclude tests/daily_care_test.c src/pet.c src/pet_view.c src/pet_animation.c -o build/host-tests/daily_care_test
	build/host-tests/daily_care_test
	$(CC) -std=c11 -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes \
		-Iinclude tests/pet_animation_test.c src/pet_animation.c src/pet_view.c src/pet.c -o build/host-tests/pet_animation_test
	build/host-tests/pet_animation_test

clean:
	rm -rf build
