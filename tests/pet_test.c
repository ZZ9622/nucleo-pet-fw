#include <assert.h>
#include <stdio.h>

#include "pet.h"

static PetRules fast_rules;

static void test_initial_state(void)
{
    PetState pet;
    pet_init(&pet, 123U);

    assert(pet.happiness == 75U);
    assert(pet.energy == 80U);
    assert(pet.level == 1U);
    assert(!pet.is_sleeping);
}

static void test_feed_is_capped_and_happy(void)
{
    PetState pet;
    PetTransition transition;
    const PetCommand command = {.type = PET_CMD_FEED};

    pet_init(&pet, 1U);
    pet.energy = 90U;
    pet_apply(&pet, &fast_rules, &command, &transition);

    assert(pet.energy == 100U);
    assert(pet_transition_has(&transition, PET_EVENT_FED));
}

static void test_sleep_recovers_energy(void)
{
    PetState pet;
    PetTransition transition;
    const PetCommand sleep = {.type = PET_CMD_SLEEP_TOGGLE};

    pet_init(&pet, 2U);
    pet.energy = 10U;
    pet_apply(&pet, &fast_rules, &sleep, &transition);
    assert(pet.is_sleeping);
    assert(pet_transition_has(&transition, PET_EVENT_SLEPT));

    pet_advance(&pet, &fast_rules, 3U, &transition);
    assert(pet.energy == 22U);
    assert(pet.happiness == 75U);
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
    pet_apply(&pet, &fast_rules, &command, &transition);

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
    pet.happiness = 20U;
    pet_make_snapshot(&pet, &snapshot);

    assert(snapshot.mood == PET_MOOD_CRITICAL);
    assert((snapshot.attention_mask & PET_ATTENTION_HAPPINESS) != 0U);
}

static void test_two_needs_and_sleep_state(void)
{
    PetState pet;
    PetTransition transition;
    PetSnapshot snapshot;
    PetCommand command = {.type = PET_CMD_PET};
    pet_init(&pet, 5U);
    pet.happiness = 95U;
    pet_apply(&pet, &fast_rules, &command, &transition);
    assert(pet.happiness == 100U && pet.energy == 80U);
    assert(pet.feedback == PET_EVENT_PETTED);
    command.type = PET_CMD_PLAY;
    pet.energy = 3U;
    pet_apply(&pet, &fast_rules, &command, &transition);
    assert(pet.energy == 0U && pet.happiness == 100U);
    assert(!pet.is_sleeping); /* Energy alone does not toggle sleep. */
    pet_advance(&pet, &fast_rules, 2U, &transition);
    pet.happiness = 0U;
    assert(pet.energy == 0U && pet.happiness == 0U);
    command.type = PET_CMD_SLEEP_TOGGLE;
    pet_apply(&pet, &fast_rules, &command, &transition);
    const PetCommandType ignored[] = {PET_CMD_FEED, PET_CMD_PET, PET_CMD_PLAY};
    for (unsigned i = 0U; i < 3U; ++i) {
        command.type = ignored[i];
        pet_apply(&pet, &fast_rules, &command, &transition);
        assert(transition.count == 0U && pet.energy == 0U && pet.happiness == 0U);
    }
    pet_advance(&pet, &fast_rules, 100U, &transition);
    assert(pet.energy == 100U && pet.happiness == 0U && pet.is_sleeping);
    pet_make_snapshot(&pet, &snapshot);
    assert(snapshot.is_sleeping && snapshot.mood == PET_MOOD_SLEEPING);
    command.type = PET_CMD_SLEEP_TOGGLE;
    pet_apply(&pet, &fast_rules, &command, &transition);
    assert(!pet.is_sleeping && pet.feedback == PET_EVENT_WOKE);
    command.type = PET_CMD_RESET;
    pet_apply(&pet, &fast_rules, &command, &transition);
    assert(pet.energy == 80U && pet.happiness == 75U && !pet.is_sleeping);
    assert(pet.rng_state == 5U && pet.experience == 0U);
}

int main(void)
{
    fast_rules = PET_RULES_DEFAULT;
    fast_rules.awake_decay_interval_s = 1U;
    fast_rules.sleep_recovery_interval_s = 1U;
    fast_rules.energy_recovery_sleep_per_step = 4U;
    test_two_needs_and_sleep_state();
    test_initial_state();
    test_feed_is_capped_and_happy();
    test_sleep_recovers_energy();
    test_game_reward_levels_up();
    test_critical_mood_is_derived();

    puts("pet core tests: passed");
    return 0;
}
