#include <assert.h>
#include <stdio.h>

#include "pet.h"

static void test_initial_state(void)
{
    PetState pet;
    pet_init(&pet, 123U);

    assert(pet.satiety == 85U);
    assert(pet.energy == 80U);
    assert(pet.level == 1U);
    assert(!pet.asleep);
}

static void test_feed_is_capped_and_happy(void)
{
    PetState pet;
    PetTransition transition;
    const PetCommand command = {.type = PET_CMD_FEED};

    pet_init(&pet, 1U);
    pet.satiety = 90U;
    pet_apply(&pet, &PET_RULES_DEMO, &command, &transition);

    assert(pet.satiety == 100U);
    assert(pet_transition_has(&transition, PET_EVENT_FED));
}

static void test_sleep_recovers_energy(void)
{
    PetState pet;
    PetTransition transition;
    const PetCommand sleep = {.type = PET_CMD_SLEEP_TOGGLE};

    pet_init(&pet, 2U);
    pet.energy = 10U;
    pet_apply(&pet, &PET_RULES_DEMO, &sleep, &transition);
    assert(pet.asleep);
    assert(pet_transition_has(&transition, PET_EVENT_SLEPT));

    pet_advance(&pet, &PET_RULES_DEMO, 3U, &transition);
    assert(pet.energy == 34U);
    assert(pet.satiety == 82U);
}

static void test_game_reward_levels_up(void)
{
    PetState pet;
    PetTransition transition;
    PetCommand command = {.type = PET_CMD_SUBMIT_GAME_RESULT};

    pet_init(&pet, 3U);
    pet.experience = 95U;
    command.game.game_id = 1U;
    command.game.score = 200U;
    command.game.duration_s = 30U;
    command.game.completed = true;
    pet_apply(&pet, &PET_RULES_DEMO, &command, &transition);

    assert(pet.experience == 110U);
    assert(pet.coins == 4U);
    assert(pet.level == 2U);
    assert(pet_transition_has(&transition, PET_EVENT_GAME_REWARD));
    assert(pet_transition_has(&transition, PET_EVENT_LEVEL_UP));
}

static void test_critical_mood_is_derived(void)
{
    PetState pet;
    PetSnapshot snapshot;

    pet_init(&pet, 4U);
    pet.health = 20U;
    pet_make_snapshot(&pet, &snapshot);

    assert(snapshot.mood == PET_MOOD_CRITICAL);
    assert((snapshot.attention_mask & PET_ATTENTION_HEALTH) != 0U);
}

int main(void)
{
    test_initial_state();
    test_feed_is_capped_and_happy();
    test_sleep_recovers_energy();
    test_game_reward_levels_up();
    test_critical_mood_is_derived();

    puts("pet core tests: passed");
    return 0;
}
