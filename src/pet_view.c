#include "pet_view.h"
#include "pet_animation.h"
#include "adventure/adventure_captions.h"

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
static void adventure_draw(uint8_t *frame, const PetSnapshot *pet, uint32_t time_ms)
{
    const unsigned stage = pet->adventure_stage;
    const bool waking = pet->adventure_waking;
    const bool resting = pet->adventure_riding || pet->adventure_paused;
    const unsigned beat = pet->adventure_paused ? 0U : time_ms / 180U;
    const unsigned caption = waking ? 6U : stage - 1U;
    /* Keep the caption above the motion area, with room for the longest line. */
    static const int caption_offsets[] = {-24, 24, 0, -24, 24, 0, 0};
    const int caption_x = 16 + caption_offsets[caption];
    for (int y = 0; y < 13; ++y) {
        for (int x = 0; x < 96; ++x) {
            if (adventure_captions[caption][y * 12 + x / 8] & (1U << (x % 8))) {
                pixel(frame, caption_x + x, 20 + y);
            }
        }
    }

    if (!waking) {
        for (int y = 50; y < 64; ++y) {
            for (int x = -44; x <= 44; ++x) {
                const int curve = x * x / 145;
                const int depth = y - 50 - curve;
                const int longitude = (x + 88 + (int)(beat % 36U) + depth / 2) % 36;
                if (depth == 0 || (depth > 1 && longitude < 7 + depth % 6)) {
                    pixel(frame, 64 + x, y);
                }
            }
        }
        number(frame, 4, 55, stage);
        if (stage == 1U) {
            rect(frame, 93, 37, 1, 5, true);
            rect(frame, 91, 39, 5, 1, true);
        } else if (stage == 2U) {
            for (int row = 0; row < 7; ++row) {
                rect(frame, 93 - row, 44 + row, row * 2 + 1, 1, true);
            }
        } else if (stage == 3U) {
            const int x = 90 + (int)(beat % 6U);
            rect(frame, x, 39, 13, 3, true);
            rect(frame, x + 4, 37, 6, 3, true);
        } else if (stage == 4U) {
            rect(frame, 88, 48, 8, 2, true);
            rect(frame, 104, 50, 8, 2, true);
            pixel(frame, 94 + (int)(beat % 4U), 44);
        } else if (stage == 5U) {
            rect(frame, 91, 42, 12, 3, false);
            rect(frame, 101, 41, 4, 5, true);
        } else if (stage == 6U) {
            rect(frame, 89, 35, 1, 16, true);
            rect(frame, 90, 35, 10, 6, true);
            pixel(frame, 103 + (int)(beat % 3U), 39);
        }
        if (pet->adventure_riding) { text(frame, 103, 55, "RIDE"); }
    }

    static const int hops[] = {2, 4, 5, 3, 1, 4};
    const int hop = resting || waking || beat % 4U != 2U ? 0 : hops[stage - 1U];
    const int x = 53 + (resting ? 0 : (int)(beat % 3U));
    const int y = 37 - hop;
    rect(frame, x + 8, y, 3, 4, true);
    rect(frame, x + 17, y, 3, 4, true);
    rect(frame, x + 7, y + 3, 14, 8, true);
    rect(frame, x + 4, y + 8, 13, 5, true);
    rect(frame, x + 2, y + 6, 5, 5, false);
    rect(frame, x, y + 6 - (int)(beat % 2U), 3, 2, true);
    cut_rect(frame, x + 11, y + 5, 2, 1);
    cut_rect(frame, x + 17, y + 5, 2, 1);
    if (waking) {
        cut_rect(frame, x + 12, y + 8, 3, 2 + (int)(beat % 2U));
        rect(frame, x + 18, y + 6, 4, 2, true);
    } else if (resting) {
        rect(frame, x + 10, y + 11, 10, 2, true);
        if (!pet->adventure_paused && beat % 4U < 2U) { rect(frame,x + 19,y + 7,3,2,true); }
    } else {
        const int stride = (int)(beat % 2U);
        rect(frame, x + 5 + stride, y + 12, 3, 2, true);
        rect(frame, x + 14 - stride, y + 12, 3, 2, true);
    }
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

    if ((pet->adventure_stage && pet->adventure_stage <= 6U) || pet->adventure_waking) {
        if (pet->adventure_preview || (!pet->is_away && !pet->is_transferring &&
            !pet->item_food_pending && !pet->item_box_animation && !pet->is_collapsed)) {
            adventure_draw(frame, pet, time_ms);
            return;
        }
    }
    if (pet->is_away || pet->is_transferring) {
        rect(frame, 53, 25, 22, 28, false);
        rect(frame, 69, 39, 2, 2, true);
        text(frame, 20, 58, pet->is_transferring ? "TRANSFER PENDING" : "VISITING PHONE");
        return;
    }

    if(pet->item_food_pending) {
        rect(frame,53,27,22,20,true);rect(frame,53,23,5,7,true);rect(frame,70,23,5,7,true);
        cut_rect(frame,58,33,3,3);cut_rect(frame,67,33,3,3);
        text(frame,pet->is_sleeping && !pet->is_collapsed?7:17,56,pet->is_sleeping && !pet->is_collapsed?"HOLD B1 TO WAKE":"B1 CONFIRM FOOD");return;
    }
    if(pet->item_box_animation) {
        const int x=20+(int)(pet->feedback_elapsed_ms*45U/2400U);
        rect(frame,103,25,20,28,false);rect(frame,118,38,2,2,true);
        rect(frame,x,32,22,19,true);rect(frame,x,27,5,8,true);rect(frame,x+17,27,5,8,true);
        cut_rect(frame,x+5,37,3,3);cut_rect(frame,x+14,37,3,3);
        rect(frame,x+23,38,12,13,false);rect(frame,x+28,38,2,13,true);
        text(frame,34,57,"YOUR BOX");return;
    }
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
