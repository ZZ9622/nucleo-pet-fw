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
    PetSnapshot pet = {.satiety=75, .energy=60, .joy=80, .hygiene=90,
                       .health=100, .level=1, .mood=PET_MOOD_CONTENT};
    pet_view_draw(guarded.image, &pet, 1000U);
    memcpy(previous, guarded.image, sizeof previous);
    pet_view_draw(guarded.image, &pet, 0U);
    assert(memcmp(previous, guarded.image, sizeof previous) != 0); /* Blink. */
    pet.asleep = true;
    pet.mood = PET_MOOD_SLEEPING;
    pet_view_draw(guarded.image, &pet, 1000U);
    assert(memcmp(previous, guarded.image, sizeof previous) != 0);
    for (unsigned i = 0; i < 16U; ++i) {
        assert(guarded.before[i] == 0xA5 && guarded.after[i] == 0xA5);
    }
    /* Exercise both ends of bars and every mood, including time wrap. */
    for (unsigned i = 0; i < 5U; ++i) {
        pet.mood = (PetMood)i;
        pet.satiety = i == 0U ? 0U : 100U;
        pet_view_draw(guarded.image, &pet, UINT32_MAX);
    }
    if (argc == 2) {
        FILE *out = fopen(argv[1], "w");
        assert(out != NULL);
        fprintf(out, "P1\n128 192\n");
        for (unsigned state = 0; state < 3U; ++state) {
            pet.asleep = state == 1U;
            pet.mood = state == 0U ? PET_MOOD_CONTENT :
                       (state == 1U ? PET_MOOD_SLEEPING : PET_MOOD_CRITICAL);
            pet.satiety = state == 2U ? 10U : 75U;
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
