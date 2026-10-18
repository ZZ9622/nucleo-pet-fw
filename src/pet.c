#include "pet.h"

const PetRules PET_RULES_DEMO = {
    .satiety_decay_awake_per_s = 6U,
    .energy_decay_awake_per_s = 3U,
    .joy_decay_awake_per_s = 1U,
    .hygiene_decay_awake_per_s = 1U,
    .satiety_decay_sleep_per_s = 1U,
    .energy_recovery_sleep_per_s = 8U,
    .joy_decay_sleep_per_s = 0U,
    .health_recovery_per_s = 1U,
    .health_decay_when_critical_per_s = 2U,
    .feed_satiety_gain = 35U,
    .care_joy_gain = 10U,
    .play_joy_gain = 20U,
    .play_energy_cost = 12U,
    .clean_hygiene_gain = 30U,
    .medicine_health_gain = 25U
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
    uint8_t lowest = pet->satiety;

    if (pet->energy < lowest) {
        lowest = pet->energy;
    }
    if (pet->joy < lowest) {
        lowest = pet->joy;
    }
    if (pet->hygiene < lowest) {
        lowest = pet->hygiene;
    }
    if (pet->health < lowest) {
        lowest = pet->health;
    }
    return lowest;
}

static uint32_t attention_mask(const PetState *pet)
{
    uint32_t mask = 0U;

    if (pet->satiety <= 50U) {
        mask |= PET_ATTENTION_SATIETY;
    }
    if (pet->energy <= 50U) {
        mask |= PET_ATTENTION_ENERGY;
    }
    if (pet->joy <= 50U) {
        mask |= PET_ATTENTION_JOY;
    }
    if (pet->hygiene <= 50U) {
        mask |= PET_ATTENTION_HYGIENE;
    }
    if (pet->health <= 50U) {
        mask |= PET_ATTENTION_HEALTH;
    }
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
    pet->satiety = 85U;
    pet->energy = 80U;
    pet->joy = 75U;
    pet->hygiene = 90U;
    pet->health = 100U;
    pet->experience = 0U;
    pet->coins = 0U;
    pet->level = 1U;
    pet->stage = PET_STAGE_HATCHLING;
    pet->asleep = false;
    pet->game_time_s = 0U;
    pet->rng_state = seed;
}

void pet_advance(PetState *pet, const PetRules *rules, uint32_t elapsed_s,
                 PetTransition *transition)
{
    const uint32_t old_attention = attention_mask(pet);
    transition_clear(transition);

    for (uint32_t second = 0U; second < elapsed_s; second++) {
        if (pet->asleep) {
            pet->satiety = decrease_need(pet->satiety,
                                         rules->satiety_decay_sleep_per_s);
            pet->energy = increase_need(pet->energy,
                                        rules->energy_recovery_sleep_per_s);
            pet->joy = decrease_need(pet->joy, rules->joy_decay_sleep_per_s);
        } else {
            pet->satiety = decrease_need(pet->satiety,
                                         rules->satiety_decay_awake_per_s);
            pet->energy = decrease_need(pet->energy,
                                        rules->energy_decay_awake_per_s);
            pet->joy = decrease_need(pet->joy, rules->joy_decay_awake_per_s);
            pet->hygiene = decrease_need(pet->hygiene,
                                         rules->hygiene_decay_awake_per_s);
        }

        if (lowest_need(pet) <= 20U) {
            pet->health = decrease_need(pet->health,
                                        rules->health_decay_when_critical_per_s);
        } else {
            pet->health = increase_need(pet->health,
                                        rules->health_recovery_per_s);
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

    if (command->type == PET_CMD_SLEEP_TOGGLE) {
        pet->asleep = !pet->asleep;
        transition_add(transition, pet->asleep ? PET_EVENT_SLEPT : PET_EVENT_WOKE);
        return;
    }

    if (pet->asleep) {
        return;
    }

    switch (command->type) {
    case PET_CMD_FEED:
        pet->satiety = increase_need(pet->satiety, rules->feed_satiety_gain);
        pet->joy = increase_need(pet->joy, rules->care_joy_gain);
        pet->experience = increase_u16(pet->experience, 5U);
        transition_add(transition, PET_EVENT_FED);
        update_level(pet, transition);
        break;
    case PET_CMD_PLAY:
        pet->joy = increase_need(pet->joy, rules->play_joy_gain);
        pet->energy = decrease_need(pet->energy, rules->play_energy_cost);
        pet->experience = increase_u16(pet->experience, 10U);
        transition_add(transition, PET_EVENT_PLAYED);
        update_level(pet, transition);
        break;
    case PET_CMD_CLEAN:
        pet->hygiene = increase_need(pet->hygiene, rules->clean_hygiene_gain);
        transition_add(transition, PET_EVENT_CLEANED);
        break;
    case PET_CMD_MEDICINE:
        pet->health = increase_need(pet->health, rules->medicine_health_gain);
        transition_add(transition, PET_EVENT_MEDICATED);
        break;
    case PET_CMD_SUBMIT_GAME_RESULT:
        if (command->game.completed) {
            const uint32_t score = command->game.score;
            const uint32_t joy_gain = 5U + (score / 10U);
            const uint32_t energy_cost = 3U + (command->game.duration_s / 60U);

            pet->joy = increase_need(pet->joy, joy_gain);
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
}

void pet_make_snapshot(const PetState *pet, PetSnapshot *snapshot)
{
    snapshot->satiety = pet->satiety;
    snapshot->energy = pet->energy;
    snapshot->joy = pet->joy;
    snapshot->hygiene = pet->hygiene;
    snapshot->health = pet->health;
    snapshot->experience = pet->experience;
    snapshot->coins = pet->coins;
    snapshot->level = pet->level;
    snapshot->stage = pet->stage;
    snapshot->asleep = pet->asleep;
    snapshot->attention_mask = attention_mask(pet);

    if (pet->asleep) {
        snapshot->mood = PET_MOOD_SLEEPING;
    } else if (lowest_need(pet) <= 20U) {
        snapshot->mood = PET_MOOD_CRITICAL;
    } else if (snapshot->attention_mask != 0U) {
        snapshot->mood = PET_MOOD_NEEDY;
    } else if ((pet->satiety >= 75U) && (pet->energy >= 75U) &&
               (pet->joy >= 75U) && (pet->health >= 75U)) {
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
