#include <assert.h>
#include <stdio.h>
#include "screen_idle.h"
#include "button.h"
#include "pet.h"

int main(void)
{
    ScreenIdle screen;
    screen_idle_init(&screen, 0U);
    assert(screen_idle_update(&screen, false, 29999U));
    assert(!screen_idle_update(&screen, false, 30000U));
    assert(!screen.awake);
    assert(!screen_idle_update(&screen, true, 31000U));
    assert(screen.awake);
    assert(!screen_idle_update(&screen, true, 90000U));
    assert(!screen_idle_update(&screen, false, 90025U));
    assert(screen_idle_update(&screen, true, 91000U));
    assert(screen_idle_update(&screen, false, 91100U));
    assert(!screen_idle_update(&screen, false, 121000U));
    /* Awake holds count as activity and postpone timeout. */
    screen_idle_init(&screen, 0U);
    assert(screen_idle_update(&screen, true, 60000U));
    assert(screen_idle_update(&screen, false, 89999U));
    assert(!screen_idle_update(&screen, false, 90000U));
    /* Idle timeout remains correct across the 32-bit tick rollover. */
    screen_idle_init(&screen, UINT32_MAX - 10000U);
    assert(screen_idle_update(&screen, false, 19998U));
    assert(!screen_idle_update(&screen, false, 19999U));
    /* A debounced wake press, even >5s B1 hold, consumes its release event. */
    Button button;
    button_init(&button, false, 0U);
    screen_idle_init(&screen, 0U);
    assert(!screen_idle_update(&screen, false, 30000U));
    button_update(&button, true, 31000U);
    button_update(&button, true, 31025U);
    assert(!screen_idle_update(&screen, button.stable_pressed, 31025U));
    button_update(&button, false, 37000U);
    button_update(&button, false, 37025U);
    assert(!screen_idle_update(&screen, button.stable_pressed, 37025U));
    assert(button_take_event(&button) == BUTTON_EVENT_RESET);
    assert(button_take_event(&button) == BUTTON_EVENT_NONE);
    assert(screen_idle_update(&screen, false, 37026U));
    /* Screen state and pet sleep are independent; simulation keeps advancing. */
    PetState pet;
    PetTransition transition;
    pet_init(&pet, 1U);
    pet_advance(&pet, &PET_RULES_DEFAULT, 36000U, &transition);
    assert(pet.energy == 70U && !pet.is_sleeping);
    const PetCommand sleep = {.type = PET_CMD_SLEEP_TOGGLE};
    pet_apply(&pet, &PET_RULES_DEFAULT, &sleep, &transition);
    pet_advance(&pet, &PET_RULES_DEFAULT, 180U, &transition);
    assert(pet.energy == 73U && pet.is_sleeping);
    puts("screen idle tests: passed");
    return 0;
}
