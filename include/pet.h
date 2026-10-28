#ifndef PET_H
#define PET_H

#include <stdbool.h>
#include <stdint.h>

#define PET_TRANSITION_EVENT_CAPACITY 4U
#define PET_AUTO_SLEEP_ENERGY 10U
#define PET_AUTO_SLEEP_DELAY_S 3U
#define PET_FEED_DEADLINE_S (24UL * 60UL * 60UL)

typedef enum {
    PET_STAGE_HATCHLING = 0,
    PET_STAGE_GROWING,
    PET_STAGE_MATURE
} PetLifeStage;

typedef enum {
    PET_MOOD_HAPPY = 0,
    PET_MOOD_CONTENT,
    PET_MOOD_NEEDY,
    PET_MOOD_CRITICAL,
    PET_MOOD_SLEEPING
} PetMood;

typedef enum {
    PET_CMD_FEED = 0,
    PET_CMD_PLAY,
    PET_CMD_SLEEP_TOGGLE,
    PET_CMD_PET,
    PET_CMD_SUBMIT_GAME_RESULT,
    PET_CMD_RESET
} PetCommandType;

typedef enum {
    PET_EVENT_NONE = 0,
    PET_EVENT_FED,
    PET_EVENT_PLAYED,
    PET_EVENT_SLEPT,
    PET_EVENT_WOKE,
    PET_EVENT_PETTED,
    PET_EVENT_GAME_REWARD,
    PET_EVENT_LEVEL_UP,
    PET_EVENT_NEEDS_ATTENTION,
    PET_EVENT_RESET
} PetEvent;

enum {
    PET_ATTENTION_ENERGY = 1U << 1,
    PET_ATTENTION_HAPPINESS = 1U << 2,
};

typedef struct {
    uint8_t game_id;
    uint16_t score;
    uint16_t duration_s;
    bool completed;
} PetGameResult;

typedef struct {
    PetCommandType type;
    PetGameResult game;
} PetCommand;

/* All needs are 0..100, where a larger number is better. */
typedef struct {
    uint8_t energy;
    uint8_t happiness;
    uint16_t experience;
    uint16_t coins;
    uint8_t level;
    PetLifeStage stage;
    bool is_sleeping;
    uint8_t low_energy_awake_s;
    uint32_t seconds_since_feed;
    uint32_t awake_decay_elapsed_s;
    uint32_t sleep_recovery_elapsed_s;
    uint32_t game_time_s;
    uint32_t rng_state;
    PetEvent feedback;
} PetState;

typedef struct {
    uint32_t awake_decay_interval_s;
    uint32_t sleep_recovery_interval_s;
    uint8_t energy_decay_awake_per_step;
    uint8_t happiness_decay_awake_per_step;
    uint8_t energy_recovery_sleep_per_step;
    uint8_t happiness_decay_sleep_per_step;
    uint8_t feed_energy_gain;
    uint8_t pet_happiness_gain;
    uint8_t play_happiness_gain;
    uint8_t play_energy_cost;
} PetRules;

typedef struct {
    PetEvent events[PET_TRANSITION_EVENT_CAPACITY];
    uint8_t count;
} PetTransition;

/* This is the display/LED-friendly view of a pet, not its persistent state. */
typedef struct {
    uint8_t energy;
    uint8_t happiness;
    uint16_t experience;
    uint16_t coins;
    uint8_t level;
    PetLifeStage stage;
    uint32_t feedback_elapsed_ms;
    PetMood mood;
    PetEvent feedback;
    bool is_sleeping;
    bool is_collapsed;
    uint32_t attention_mask;
} PetSnapshot;

extern const PetRules PET_RULES_DEFAULT;

void pet_init(PetState *pet, uint32_t seed);
void pet_advance(PetState *pet, const PetRules *rules, uint32_t elapsed_s,
                 PetTransition *transition);
void pet_apply(PetState *pet, const PetRules *rules, const PetCommand *command,
               PetTransition *transition);
void pet_make_snapshot(const PetState *pet, PetSnapshot *snapshot);
bool pet_transition_has(const PetTransition *transition, PetEvent event);

#endif
