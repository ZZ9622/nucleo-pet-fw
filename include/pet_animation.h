#ifndef PET_ANIMATION_H
#define PET_ANIMATION_H
#include "pet.h"

typedef enum { PET_ANIM_IDLE, PET_ANIM_BLINK, PET_ANIM_WALK,
               PET_ANIM_JUMP, PET_ANIM_YAWN, PET_ANIM_SLEEP,
               PET_ANIM_COLLAPSED } PetAnimationKind;
typedef struct {
    PetAnimationKind kind;
    int x_offset;
    int y_offset;
    bool eyes_closed;
    uint8_t phase;
} PetPose;
/* Pure visual sampling: never changes needs or gameplay random state. */
void pet_animation_sample(const PetSnapshot *pet, uint32_t time_ms, PetPose *pose);
#endif
