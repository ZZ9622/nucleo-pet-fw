#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "pet_view.h"

int main(int argc, char **argv)
{
    struct { uint8_t before[16]; uint8_t image[1024]; uint8_t after[16]; } guarded;
    uint8_t previous[1024];
    memset(&guarded, 0xA5, sizeof guarded);
    PetSnapshot pet = {.energy=60, .happiness=80, .level=1, .mood=PET_MOOD_CONTENT};
    pet_view_draw(guarded.image, &pet, 1000U);
    memcpy(previous, guarded.image, sizeof previous);
    bool saw_blink = false;
    for (unsigned t = 0U; t < 6000U; t += 100U) {
        pet_view_draw(guarded.image, &pet, t);
        if (memcmp(previous, guarded.image, sizeof previous) != 0) { saw_blink = true; }
    }
    assert(saw_blink);
    pet.is_sleeping = true;
    pet.mood = PET_MOOD_SLEEPING;
    pet_view_draw(guarded.image, &pet, 1000U);
    assert(memcmp(previous, guarded.image, sizeof previous) != 0);
    for (unsigned i = 0; i < 16U; ++i) {
        assert(guarded.before[i] == 0xA5 && guarded.after[i] == 0xA5);
    }
    /* Exercise both ends of bars and every mood, including time wrap. */
    for (unsigned i = 0; i < 5U; ++i) {
        pet.mood = (PetMood)i;
        pet.happiness = i == 0U ? 0U : 100U;
        pet_view_draw(guarded.image, &pet, UINT32_MAX);
    }
    /* Every mood has a distinct expression in the central region. */
    uint8_t expressions[5][1024];
    for (unsigned state = 0U; state < 5U; ++state) {
        pet.is_sleeping = state == 4U;
        pet.mood = (PetMood)state;
        pet_view_draw(expressions[state], &pet, 1000U);
        for (unsigned other = 0U; other < state; ++other) {
            assert(memcmp(expressions[state] + 3U * 128U,
                          expressions[other] + 3U * 128U, 4U * 128U) != 0);
        }
    }
    /* Side feedback changes only x<30 below the stats; cat stays unchanged. */
    pet.is_sleeping = false;
    pet.mood = PET_MOOD_CONTENT;
    pet.feedback = PET_EVENT_NONE;
    pet_view_draw(guarded.image, &pet, 1000U);
    memcpy(previous, guarded.image, sizeof previous);
    pet.feedback = PET_EVENT_PETTED;
    pet_view_draw(guarded.image, &pet, 1000U);
    assert(memcmp(previous, guarded.image, sizeof previous) != 0);
    for (unsigned y = 0U; y < 64U; ++y) {
        for (unsigned x = 0U; x < 128U; ++x) {
            if (x >= 30U || y < 19U) {
                const unsigned index = y / 8U * 128U + x;
                const unsigned mask = 1U << (y % 8U);
                assert((previous[index] & mask) == (guarded.image[index] & mask));
            }
        }
    }
    /* No full-width footer divider remains in the lower screen. */
    for (unsigned y = 58U; y < 64U; ++y) {
        unsigned lit = 0U;
        for (unsigned x = 0U; x < 128U; ++x) {
            lit += (guarded.image[y / 8U * 128U + x] >> (y % 8U)) & 1U;
        }
        assert(lit < 128U);
    }
    for (unsigned i = 0U; i < 16U; ++i) {
        assert(guarded.before[i] == 0xA5 && guarded.after[i] == 0xA5);
    }
    pet.feedback = PET_EVENT_NONE;
    if (argc == 2) {
        FILE *out = fopen(argv[1], "w");
        assert(out != NULL);
        fprintf(out, "P1\n128 320\n");
        for (unsigned state = 0; state < 5U; ++state) {
            pet.is_sleeping = state == 4U;
            pet.mood = (PetMood)state;
            pet.happiness = state == 2U || state == 3U ? 10U : 75U;
            pet_view_draw(guarded.image, &pet, 1000U);
            for (unsigned y = 0; y < 64U; ++y) {
                for (unsigned x = 0; x < 128U; ++x) {
                    /* PBM black on white; invert to preview OLED colors later. */
                    fprintf(out, "%u ", (guarded.image[y/8U*128U+x] >> (y%8U)) & 1U);
                }
                fputc('\n', out);
            }
        }
        fclose(out);
    }
    puts("pet view tests: passed");
    return 0;
}
