#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "pet.h"
#include "pet_view.h"

int main(int argc, char **argv)
{
    PetState pet, chunked;
    PetSnapshot snapshot;
    PetTransition transition;
    const PetCommand feed = {.type = PET_CMD_FEED};
    const PetCommand sleep = {.type = PET_CMD_SLEEP_TOGGLE};
    const PetCommand play = {.type = PET_CMD_PLAY};
    pet_init(&pet, 1U);
    pet_advance(&pet, &PET_RULES_DEFAULT, 3599U, &transition);
    assert(pet.energy == 80U && pet.happiness == 75U);
    pet_advance(&pet, &PET_RULES_DEFAULT, 1U, &transition);
    assert(pet.energy == 79U && pet.happiness == 74U);
    pet_init(&pet, 1U);
    pet_advance(&pet, &PET_RULES_DEFAULT, PET_FEED_DEADLINE_S - 1U, &transition);
    pet_make_snapshot(&pet, &snapshot);
    assert(!snapshot.is_collapsed);
    pet_advance(&pet, &PET_RULES_DEFAULT, 1U, &transition);
    pet_make_snapshot(&pet, &snapshot);
    assert(snapshot.is_collapsed && snapshot.mood == PET_MOOD_CRITICAL);
    assert(pet.energy == 0U);
    pet_apply(&pet, &PET_RULES_DEFAULT, &play, &transition);
    assert(transition.count == 0U);
    pet_advance(&pet, &PET_RULES_DEFAULT, 86400U, &transition);
    assert(pet.seconds_since_feed == PET_FEED_DEADLINE_S);
    uint8_t first[1024], second[1024];
    pet_view_draw(first, &snapshot, 0U);
    pet_view_draw(second, &snapshot, 1200U);
    assert(memcmp(first, second, sizeof first) != 0); /* Breathing. */
    if (argc == 2) {
        FILE *out = fopen(argv[1], "w");
        assert(out != NULL);
        fprintf(out, "P1\n128 64\n");
        for (unsigned y = 0U; y < 64U; ++y) {
            for (unsigned x = 0U; x < 128U; ++x) {
                fprintf(out, "%u ", (first[y / 8U * 128U + x] >> (y % 8U)) & 1U);
            }
            fputc('\n', out);
        }
        fclose(out);
    }
    pet_apply(&pet, &PET_RULES_DEFAULT, &feed, &transition);
    pet_make_snapshot(&pet, &snapshot);
    assert(!snapshot.is_collapsed && pet.seconds_since_feed == 0U && pet.energy == 30U);
    /* Feeding before the deadline grants a fresh rolling 24h window. */
    pet_advance(&pet, &PET_RULES_DEFAULT, 80000U, &transition);
    if (pet.is_sleeping) { pet_apply(&pet, &PET_RULES_DEFAULT, &sleep, &transition); }
    pet_apply(&pet, &PET_RULES_DEFAULT, &feed, &transition);
    pet_advance(&pet, &PET_RULES_DEFAULT, 7000U, &transition);
    pet_make_snapshot(&pet, &snapshot);
    assert(!snapshot.is_collapsed && pet.seconds_since_feed == 7000U);
    /* Sleep counts toward hunger; a rescue feed wakes the pet. */
    pet_init(&pet, 2U);
    pet_apply(&pet, &PET_RULES_DEFAULT, &sleep, &transition);
    pet_advance(&pet, &PET_RULES_DEFAULT, PET_FEED_DEADLINE_S, &transition);
    assert(pet.energy == 0U);
    pet_apply(&pet, &PET_RULES_DEFAULT, &feed, &transition);
    assert(!pet.is_sleeping && pet.seconds_since_feed == 0U && pet.energy == 30U);
    /* Time segmentation must not affect simulation or partially elapsed steps. */
    pet_init(&pet, 3U);
    pet_init(&chunked, 3U);
    pet_advance(&pet, &PET_RULES_DEFAULT, 86400U, &transition);
    for (unsigned i = 0U; i < 86400U; ++i) {
        pet_advance(&chunked, &PET_RULES_DEFAULT, 1U, &transition);
    }
    assert(pet.energy == chunked.energy && pet.happiness == chunked.happiness);
    assert(pet.seconds_since_feed == chunked.seconds_since_feed);
    puts("daily care tests: passed");
    return 0;
}
