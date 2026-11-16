#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
profile=${POMI_ACTIVITY_PROFILE_ID:-3}
case "$profile" in
    1) seconds=30 ;;
    2|3) seconds=600 ;;
    *) echo "POMI_ACTIVITY_PROFILE_ID must be 1, 2, or 3" >&2; exit 2 ;;
esac

# Stage the shared sources so Arduino builds the same code without a second copy in Git.
staging=$(mktemp -d)
trap 'rm -r "$staging"' EXIT
sketch="$staging/pomi_c3"
cp -R "$repo/firmware/pomi_c3" "$sketch"
cp "$repo"/include/*.h "$sketch/src/"
for source in pet pet_view pet_animation pet_handoff pet_serial activity_reward button screen_idle led motion lis3dh display_ssd1306; do
    cp "$repo/src/$source.c" "$sketch/src/"
done
cp -R "$repo/src/adventure" "$sketch/src/"
sed 's/^int main(void)$/void pomi_run(void)/' "$repo/src/main.c" > "$sketch/src/runtime.c"
flags="-DPOMI_ACTIVITY_PROFILE_ID=$profile -DPOMI_ACTIVITY_SECONDS=$seconds"
arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc \
    --build-path "$repo/build/pomi-c3-$profile" \
    --build-property "compiler.c.extra_flags=$flags" \
    "$sketch"
