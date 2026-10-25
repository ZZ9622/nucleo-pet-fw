#include "pet_view.h"

/* Three-column, five-row glyphs. Bit zero is the top pixel. */
static const uint8_t letters[26][3] = {
    {30,5,30},{31,21,10},{14,17,17},{31,17,14},{31,21,17},
    {31,5,1},{14,17,29},{31,4,31},{17,31,17},{8,16,15},
    {31,4,27},{31,16,16},{31,2,31},{31,1,30},{14,17,14},
    {31,5,2},{14,25,30},{31,13,22},{18,21,9},{1,31,1},
    {15,16,15},{7,24,7},{31,8,31},{27,4,27},{3,28,3},{25,21,19}
};
static const uint8_t digits[10][3] = {
    {31,17,31},{18,31,16},{29,21,23},{21,21,31},{7,4,31},
    {23,21,29},{31,21,29},{1,29,3},{31,21,31},{23,21,31}
};
static void pixel(uint8_t *f, int x, int y)
{
    if (x >= 0 && x < 128 && y >= 0 && y < 64) {
        f[(unsigned)y / 8U * 128U + (unsigned)x] |= (uint8_t)(1U << ((unsigned)y % 8U));
    }
}
static void rect(uint8_t *f, int x, int y, int w, int h, bool filled)
{
    for (int j = 0; j < h; ++j) {
        for (int i = 0; i < w; ++i) {
            if (filled || i == 0 || j == 0 || i == w - 1 || j == h - 1) {
                pixel(f, x + i, y + j);
            }
        }
    }
}
static void text(uint8_t *f, int x, int y, const char *s)
{
    while (*s != '\0') {
        char c = *s++;
        const uint8_t *glyph = 0;
        if (c >= 'A' && c <= 'Z') { glyph = letters[(unsigned)(c - 'A')]; }
        if (c >= '0' && c <= '9') { glyph = digits[(unsigned)(c - '0')]; }
        if (glyph != 0) {
            for (unsigned i = 0U; i < 3U; ++i) {
                for (unsigned j = 0U; j < 5U; ++j) {
                    if ((glyph[i] & (1U << j)) != 0U) { pixel(f, x + (int)i, y + (int)j); }
                }
            }
        }
        x += 4;
    }
}
static void number(uint8_t *f, int x, int y, unsigned value)
{
    char s[4];
    value = value > 999U ? 999U : value;
    s[0] = (char)('0' + value / 100U);
    s[1] = (char)('0' + value / 10U % 10U);
    s[2] = (char)('0' + value % 10U);
    s[3] = '\0';
    text(f, x, y, s);
}
static void stat(uint8_t *f, int y, const char *label, unsigned value)
{
    value = value > 100U ? 100U : value;
    text(f, 68, y, label);
    number(f, 112, y, value);
    rect(f, 68, y + 6, 56, 3, false);
    rect(f, 69, y + 7, (int)(value * 54U / 100U), 1, true);
}
void pet_view_draw(uint8_t *frame, const PetSnapshot *pet, uint32_t time_ms)
{
    for (unsigned i = 0U; i < 1024U; ++i) { frame[i] = 0U; }
    const char *mood = "CONTENT";
    switch (pet->mood) {
    case PET_MOOD_HAPPY: mood = "HAPPY"; break;
    case PET_MOOD_NEEDY: mood = "NEEDY"; break;
    case PET_MOOD_CRITICAL: mood = "HELP"; break;
    case PET_MOOD_SLEEPING: mood = "SLEEP"; break;
    case PET_MOOD_CONTENT: default: break;
    }
    text(frame, 4, 1, mood);
    text(frame, 92, 1, "LV");
    number(frame, 108, 1, pet->level);
    rect(frame, 0, 8, 128, 1, true);
    stat(frame, 10, "FOOD", pet->satiety);
    stat(frame, 20, "ENERGY", pet->energy);
    stat(frame, 30, "JOY", pet->joy);
    stat(frame, 40, "CLEAN", pet->hygiene);
    stat(frame, 50, "HEALTH", pet->health);

    int bob = (time_ms / (pet->asleep ? 800U : 400U)) % 2U == 0U ? 0 : 1;
    int top = 22 + bob;
    /* A small cat with ears, paws, and an animated tail. */
    rect(frame, 12, top, 40, 27, false);
    for (int i = 0; i < 8; ++i) {
        pixel(frame, 12 + i, top - 8 + i);
        pixel(frame, 12, top - i);
        pixel(frame, 51 - i, top - 8 + i);
        pixel(frame, 51, top - i);
    }
    rect(frame, 18, top + 27, 9, 3, false);
    rect(frame, 37, top + 27, 9, 3, false);
    rect(frame, 52, top + 19, 6, 2, true);
    rect(frame, 57, top + 14 - bob * 3, 2, 7 + bob * 3, true);
    bool closed = pet->asleep || time_ms % 3200U < 240U;
    if (closed) {
        rect(frame, 21, top + 9, 6, 1, true);
        rect(frame, 38, top + 9, 6, 1, true);
    } else {
        rect(frame, 22, top + 6, 3, 5, true);
        rect(frame, 39, top + 6, 3, 5, true);
    }
    pixel(frame, 32, top + 13);
    bool sad = pet->mood == PET_MOOD_NEEDY || pet->mood == PET_MOOD_CRITICAL;
    rect(frame, 28, top + (sad ? 17 : 20), 9, 1, true);
    pixel(frame, 27, top + 18);
    pixel(frame, 37, top + 18);
    if (pet->asleep) {
        text(frame, 45, 12 - (int)(time_ms / 500U % 3U), "Z");
        text(frame, 55, 16 - (int)(time_ms / 500U % 3U), "Z");
    } else if (pet->mood == PET_MOOD_CRITICAL && time_ms / 400U % 2U == 0U) {
        rect(frame, 59, 12, 2, 5, true);
        rect(frame, 59, 19, 2, 1, true);
    }
    text(frame, 2, 59, "B1 FEED  2S SLEEP  5S RESET");
}
