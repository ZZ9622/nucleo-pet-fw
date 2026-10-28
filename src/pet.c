#include "pet.h"

const PetRules PET_RULES_DEFAULT = {
    .awake_decay_interval_s = 3600U,
    .sleep_recovery_interval_s = 60U,
    .energy_decay_awake_per_step = 1U,
    .happiness_decay_awake_per_step = 1U,
    .energy_recovery_sleep_per_step = 1U,
    .happiness_decay_sleep_per_step = 0U,
    .feed_energy_gain = 30U,
    .pet_happiness_gain = 10U,
    .play_happiness_gain = 20U,
    .play_energy_cost = 12U
};

static uint8_t increase_need(uint8_t value, uint32_t amount)
{
    if (amount >= (100U - value)) {
        return 100U;
    }
    return (uint8_t)(value + amount);
}

static uint8_t decrease_need(uint8_t value, uint32_t amount)
{
    if (amount >= value) {
        return 0U;
    }
    return (uint8_t)(value - amount);
}

static uint16_t increase_u16(uint16_t value, uint32_t amount)
{
    if (amount >= (65535U - value)) {
        return 65535U;
    }
    return (uint16_t)(value + amount);
}

static uint8_t lowest_need(const PetState *pet)
{
    return pet->energy < pet->happiness ? pet->energy : pet->happiness;
}

static uint32_t attention_mask(const PetState *pet)
{
    uint32_t mask = 0U;
    if (pet->energy <= 50U) { mask |= PET_ATTENTION_ENERGY; }
    if (pet->happiness <= 50U) { mask |= PET_ATTENTION_HAPPINESS; }
    return mask;
}

static void transition_clear(PetTransition *transition)
{
    transition->count = 0U;
}

static void transition_add(PetTransition *transition, PetEvent event)
{
    if (transition->count < PET_TRANSITION_EVENT_CAPACITY) {
        transition->events[transition->count] = event;
        transition->count++;
    }
}

static void update_level(PetState *pet, PetTransition *transition)
{
    uint16_t calculated_level = (uint16_t)(pet->experience / 100U) + 1U;
    if (calculated_level > 99U) {
        calculated_level = 99U;
    }

    if (calculated_level > pet->level) {
        pet->level = (uint8_t)calculated_level;
        transition_add(transition, PET_EVENT_LEVEL_UP);
    }

    if (pet->level >= 10U) {
        pet->stage = PET_STAGE_MATURE;
    } else if (pet->level >= 3U) {
        pet->stage = PET_STAGE_GROWING;
    }
}

void pet_init(PetState *pet, uint32_t seed)
{
    pet->energy = 80U;
    pet->happiness = 75U;
    pet->experience = 0U;
    pet->coins = 0U;
    pet->level = 1U;
    pet->stage = PET_STAGE_HATCHLING;
    pet->is_sleeping = false;
    pet->seconds_since_feed = 0U;
    pet->low_energy_awake_s = 0U;
    pet->awake_decay_elapsed_s = 0U;
    pet->sleep_recovery_elapsed_s = 0U;
    pet->game_time_s = 0U;
    pet->rng_state = seed;
    pet->feedback = PET_EVENT_NONE;
}

void pet_advance(PetState *pet, const PetRules *rules, uint32_t elapsed_s,
                 PetTransition *transition)
{
    const uint32_t old_attention = attention_mask(pet);
    transition_clear(transition);

    for (uint32_t second = 0U; second < elapsed_s; second++) {
        if (pet->seconds_since_feed < PET_FEED_DEADLINE_S) {
            pet->seconds_since_feed++;
            if (pet->seconds_since_feed == PET_FEED_DEADLINE_S) {
                pet->energy = 0U;
                transition_add(transition, PET_EVENT_NEEDS_ATTENTION);
            }
        }
        if (pet->seconds_since_feed >= PET_FEED_DEADLINE_S) {
            /* Sleeping cannot substitute for food once the pet has collapsed. */
            pet->game_time_s++;
            continue;
        }
        if (pet->is_sleeping) {
            pet->sleep_recovery_elapsed_s++;
            if (rules->sleep_recovery_interval_s == 0U ||
                pet->sleep_recovery_elapsed_s >= rules->sleep_recovery_interval_s) {
                pet->sleep_recovery_elapsed_s = 0U;
                pet->energy = increase_need(pet->energy, rules->energy_recovery_sleep_per_step);
                pet->happiness = decrease_need(pet->happiness, rules->happiness_decay_sleep_per_step);
            }
        } else {
            pet->awake_decay_elapsed_s++;
            if (rules->awake_decay_interval_s == 0U ||
                pet->awake_decay_elapsed_s >= rules->awake_decay_interval_s) {
                pet->awake_decay_elapsed_s = 0U;
                pet->energy = decrease_need(pet->energy, rules->energy_decay_awake_per_step);
                pet->happiness = decrease_need(pet->happiness, rules->happiness_decay_awake_per_step);
            }
        }
        if (!pet->is_sleeping && pet->energy <= PET_AUTO_SLEEP_ENERGY) {
            if (pet->low_energy_awake_s < PET_AUTO_SLEEP_DELAY_S) {
                pet->low_energy_awake_s++;
            }
            if (pet->low_energy_awake_s >= PET_AUTO_SLEEP_DELAY_S) {
                pet->is_sleeping = true;
                pet->low_energy_awake_s = 0U;
                transition_add(transition, PET_EVENT_SLEPT);
            }
        } else {
            pet->low_energy_awake_s = 0U;
        }
        pet->game_time_s++;
    }

    if ((old_attention == 0U) && (attention_mask(pet) != 0U)) {
        transition_add(transition, PET_EVENT_NEEDS_ATTENTION);
    }
}

void pet_apply(PetState *pet, const PetRules *rules, const PetCommand *command,
               PetTransition *transition)
{
    transition_clear(transition);

    if (command->type == PET_CMD_RESET) {
        const uint32_t seed = pet->rng_state;
        pet_init(pet, seed);
        transition_add(transition, PET_EVENT_RESET);
        return;
    }

    if (pet->seconds_since_feed >= PET_FEED_DEADLINE_S) {
        if (command->type != PET_CMD_FEED) { return; }
        pet->is_sleeping = false; /* Feeding rescues even a sleeping collapsed cat. */
    }

    if (command->type == PET_CMD_SLEEP_TOGGLE) {
        pet->is_sleeping = !pet->is_sleeping;
        pet->low_energy_awake_s = 0U;
        pet->feedback = pet->is_sleeping ? PET_EVENT_SLEPT : PET_EVENT_WOKE;
        transition_add(transition, pet->is_sleeping ? PET_EVENT_SLEPT : PET_EVENT_WOKE);
        return;
    }

    if (pet->is_sleeping) {
        return;
    }

    switch (command->type) {
    case PET_CMD_FEED:
        pet->seconds_since_feed = 0U;
        pet->low_energy_awake_s = 0U;
        pet->awake_decay_elapsed_s = 0U;
        pet->energy = increase_need(pet->energy, rules->feed_energy_gain);
        pet->experience = increase_u16(pet->experience, 5U);
        transition_add(transition, PET_EVENT_FED);
        update_level(pet, transition);
        break;
    case PET_CMD_PLAY:
        pet->happiness = increase_need(pet->happiness, rules->play_happiness_gain);
        pet->energy = decrease_need(pet->energy, rules->play_energy_cost);
        pet->experience = increase_u16(pet->experience, 10U);
        transition_add(transition, PET_EVENT_PLAYED);
        update_level(pet, transition);
        break;
    case PET_CMD_PET:
        pet->happiness = increase_need(pet->happiness, rules->pet_happiness_gain);
        transition_add(transition, PET_EVENT_PETTED);
        break;
    case PET_CMD_SUBMIT_GAME_RESULT:
        if (command->game.completed) {
            const uint32_t score = command->game.score;
            const uint32_t happiness_gain = 5U + (score / 10U);
            const uint32_t energy_cost = 3U + (command->game.duration_s / 60U);

            pet->happiness = increase_need(pet->happiness, happiness_gain);
            pet->energy = decrease_need(pet->energy, energy_cost);
            pet->experience = increase_u16(pet->experience, 5U + (score / 20U));
            pet->coins = increase_u16(pet->coins, score / 50U);
            transition_add(transition, PET_EVENT_GAME_REWARD);
            update_level(pet, transition);
        }
        break;
    case PET_CMD_SLEEP_TOGGLE:
    case PET_CMD_RESET:
    default:
        break;
    }
    if (transition->count != 0U) { pet->feedback = transition->events[0]; }
}

void pet_make_snapshot(const PetState *pet, PetSnapshot *snapshot)
{
    snapshot->energy = pet->energy;
    snapshot->happiness = pet->happiness;
    snapshot->experience = pet->experience;
    snapshot->coins = pet->coins;
    snapshot->level = pet->level;
    snapshot->stage = pet->stage;
    snapshot->feedback = pet->feedback;
    snapshot->feedback_elapsed_ms = 0U;
    snapshot->is_sleeping = pet->is_sleeping;
    snapshot->attention_mask = attention_mask(pet);
    snapshot->is_collapsed = pet->seconds_since_feed >= PET_FEED_DEADLINE_S;

    if (snapshot->is_collapsed) {
        snapshot->mood = PET_MOOD_CRITICAL;
    } else if (pet->is_sleeping) {
        snapshot->mood = PET_MOOD_SLEEPING;
    } else if (lowest_need(pet) <= 20U) {
        snapshot->mood = PET_MOOD_CRITICAL;
    } else if (snapshot->attention_mask != 0U) {
        snapshot->mood = PET_MOOD_NEEDY;
    } else if ((pet->energy >= 75U) && (pet->happiness >= 75U)) {
        snapshot->mood = PET_MOOD_HAPPY;
    } else {
        snapshot->mood = PET_MOOD_CONTENT;
    }
}

bool pet_transition_has(const PetTransition *transition, PetEvent event)
{
    for (uint8_t index = 0U; index < transition->count; index++) {
        if (transition->events[index] == event) {
            return true;
        }
    }
    return false;
}
