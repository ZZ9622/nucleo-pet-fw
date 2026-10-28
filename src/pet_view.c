#include "pet_view.h"
#include "pet_animation.h"

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
/* Dark features cut out of the solid monochrome silhouette. */
static void cut_rect(uint8_t *f, int x, int y, int w, int h)
{
    for (int j = 0; j < h; ++j) {
        for (int i = 0; i < w; ++i) {
            int px = x + i;
            int py = y + j;
            if (px >= 0 && px < 128 && py >= 0 && py < 64) {
                f[(unsigned)py / 8U * 128U + (unsigned)px] &=
                    (uint8_t)~(1U << ((unsigned)py % 8U));
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
/* Compact speech beside the cat; 7 glyph columns fit before x=30.
 * Multiword feedback is wrapped explicitly to keep the cat's path clear. */
static void side_text(uint8_t *frame, const char *message)
{
    int x = 2;
    int y = 33;
    for (const char *c = message; *c != '\0'; ++c) {
        if (*c == '\n') { x = 2; y += 7; continue; }
        char glyph[2] = {*c, '\0'};
        text(frame, x, y, glyph);
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
    text(f, 2, y, label);
    number(f, 44, y, value);
    rect(f, 62, y, 64, 5, false);
    rect(f, 63, y + 1, (int)(value * 62U / 100U), 3, true);
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
    stat(frame, 1, "HAPPINESS", pet->happiness);
    stat(frame, 10, "ENERGY", pet->energy);
    rect(frame, 0, 18, 128, 1, true);

    if (pet->is_collapsed) {
        /* Lying on the floor, head down, paws out; only the back breathes. */
        const int breath = (int)(time_ms / 1200U % 2U);
        rect(frame, 53, 49 - breath, 28, 10 + breath, true);
        rect(frame, 37, 46, 19, 13, true);
        rect(frame, 38, 43, 4, 5, true);
        rect(frame, 49, 44, 4, 4, true);
        rect(frame, 48, 57, 14, 3, true);
        rect(frame, 74, 57, 13, 3, true);
        rect(frame, 80, 53, 10, 3, true);
        cut_rect(frame, 40, 51, 4, 1);
        cut_rect(frame, 48, 51, 4, 1);
        cut_rect(frame, 44, 55, 3, 1);
        rect(frame, 32, 61, 64, 1, true);
        side_text(frame, "FEED\nME");
        return;
    }
    PetPose pose;
    pet_animation_sample(pet, time_ms, &pose);
    const bool sleeping = pose.kind == PET_ANIM_SLEEP;
    const int top = 29 + pose.y_offset;
    /* Reference-inspired block cat: square ears, stepped cheeks, flat chin.
     * Uses the enlarged area below the stats, with feedback on the left. */
    rect(frame, pose.x_offset + 48, top, 6, 6, true);
    rect(frame, pose.x_offset + 74, top, 6, 6, true);
    rect(frame, pose.x_offset + 48, top + 5, 32, 25, true);
    rect(frame, pose.x_offset + 43, top + 9, 42, 16, true);

    if (pose.eyes_closed) {
        cut_rect(frame, pose.x_offset + 54, top + 14, 5, 2);
        cut_rect(frame, pose.x_offset + 70, top + 14, 5, 2);
    } else if (pet->mood == PET_MOOD_HAPPY || pose.kind == PET_ANIM_JUMP) {
        /* Two little upturned eyes. */
        for (int x = 54; x <= 70; x += 16) {
            cut_rect(frame, pose.x_offset + x, top + 14, 2, 2);
            cut_rect(frame, pose.x_offset + x + 2, top + 12, 2, 2);
            cut_rect(frame, pose.x_offset + x + 4, top + 14, 2, 2);
        }
    } else if (pet->mood == PET_MOOD_CRITICAL) {
        cut_rect(frame, pose.x_offset + 53, top + 14, 6, 2);
        cut_rect(frame, pose.x_offset + 70, top + 14, 6, 2);
        cut_rect(frame, pose.x_offset + 57, top + 16, 2, 2);
        cut_rect(frame, pose.x_offset + 70, top + 16, 2, 2);
    } else {
        cut_rect(frame, pose.x_offset + 54, top + 14, 4, 5);
        cut_rect(frame, pose.x_offset + 71, top + 14, 4, 5);
    }

    if (pose.kind == PET_ANIM_YAWN) {
        cut_rect(frame, pose.x_offset + 61, top + 20, 6, 3 + pose.phase);
    } else if (sleeping) {
        cut_rect(frame, pose.x_offset + 62, top + 23, 4, 1);
        text(frame, pose.x_offset + 87, 24 - (int)(time_ms / 500U % 3U), "Z");
        text(frame, pose.x_offset + 94, 20 - (int)(time_ms / 500U % 3U), "Z");
    } else if (pet->mood == PET_MOOD_HAPPY || pose.kind == PET_ANIM_JUMP) {
        cut_rect(frame, pose.x_offset + 60, top + 22, 2, 2);
        cut_rect(frame, pose.x_offset + 66, top + 22, 2, 2);
        cut_rect(frame, pose.x_offset + 62, top + 24, 4, 2);
    } else if (pet->mood == PET_MOOD_NEEDY || pet->mood == PET_MOOD_CRITICAL) {
        cut_rect(frame, pose.x_offset + 62, top + 22, 4, 2);
        cut_rect(frame, pose.x_offset + 60, top + 24, 2, 2);
        cut_rect(frame, pose.x_offset + 66, top + 24, 2, 2);
        if (pet->mood == PET_MOOD_CRITICAL && time_ms / 400U % 2U == 0U) {
            rect(frame, pose.x_offset + 90, 32, 2, 5, true);
            rect(frame, pose.x_offset + 90, 39, 2, 2, true);
        }
    } else {
        /* Neutral face follows the reference's two eyes and small square mouth. */
        cut_rect(frame, pose.x_offset + 62, top + 22, 4, 3);
    }
    if (!sleeping) {
        const int stride = pose.kind == PET_ANIM_WALK ? (int)pose.phase : 0;
        rect(frame, pose.x_offset + 50 + stride, top + 29, 7, 2, true);
        rect(frame, pose.x_offset + 72 - stride, top + 29, 7, 2, true);
    }
    const char *feedback = pose.kind == PET_ANIM_YAWN ? "YAWN" : mood;
    if (!sleeping) {
        switch (pet->feedback) {
        case PET_EVENT_FED: feedback = "YUMMY"; break;
        case PET_EVENT_PETTED: feedback = "LOVE\nYOU"; break;
        case PET_EVENT_PLAYED: feedback = "THAT\nWAS FUN"; break;
        case PET_EVENT_WOKE: feedback = "GOOD\nMORNING"; break;
        case PET_EVENT_GAME_REWARD: feedback = "NICE\nGAME"; break;
        default: break;
        }
    }
    side_text(frame, feedback);
}
