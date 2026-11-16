#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <esp_timer.h>

extern "C" {
#include "board.h"
#include "board_i2c.h"
#include "pet_handoff.h"
}

namespace {
constexpr uint8_t actionPins[] = {0, 4, 6, 10};
constexpr uint8_t confirmPin = 9;  // Olimex USER button. Leave released during boot.
constexpr uint8_t ledPin = 8;
constexpr uint8_t sdaPin = 7;
constexpr uint8_t sclPin = 3;
constexpr uint32_t storageVersion = 1;
constexpr char namespaceName[] = "pomi-pet";
constexpr char stateKey[] = "state";
struct SaveRecord {
    uint32_t version;
    PetHandoff handoff;
    uint32_t checksum;
};
Preferences storage;
bool storageReady;
}

extern "C" {

void board_init(void) {
    for (uint8_t pin : actionPins) pinMode(pin, INPUT_PULLUP);
    pinMode(confirmPin, INPUT_PULLUP);
    pinMode(ledPin, OUTPUT);
    storageReady = storage.begin(namespaceName, false);
}

bool board_action_pressed(BoardAction action) {
    return static_cast<unsigned>(action) < BOARD_ACTION_COUNT && digitalRead(actionPins[action]) == LOW;
}

uint32_t board_clock_millis(void) { return uint32_t(esp_timer_get_time() / 1000); }
uint32_t board_millis(void) { return board_clock_millis(); }
bool board_button_pressed(void) { return digitalRead(confirmPin) == LOW; }
void board_led_write(bool on) { digitalWrite(ledPin, on ? HIGH : LOW); }
void board_idle(void) { delay(1); }

void board_i2c_init(void) { Wire.begin(sdaPin, sclPin, 100000); }

bool board_i2c_write(uint8_t address, uint8_t prefix, const uint8_t *data, size_t count) {
    Wire.beginTransmission(address);
    Wire.write(prefix);
    if (count) Wire.write(data, count);
    return Wire.endTransmission() == 0;
}

bool board_i2c_read_register(uint8_t address, uint8_t reg, uint8_t *value) {
    Wire.beginTransmission(address);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0 || Wire.requestFrom(address, size_t(1)) != 1) return false;
    *value = uint8_t(Wire.read());
    return true;
}

int pet_storage_load(PetHandoff *handoff) {
    if (!storageReady) return -1;
    if (!storage.isKey(stateKey)) return 0;
    SaveRecord record{};
    if (storage.getBytesLength(stateKey) != sizeof record ||
        storage.getBytes(stateKey, &record, sizeof record) != sizeof record ||
        record.version != storageVersion ||
        record.checksum != pet_crc32(&record, offsetof(SaveRecord, checksum)) ||
        record.handoff.phase > PET_RETURN_STAGED) return -1;
    *handoff = record.handoff;
    return 1;
}

bool pet_storage_save(const PetHandoff *handoff) {
    if (!storageReady || handoff->phase > PET_RETURN_STAGED) return false;
    SaveRecord record{};
    record.version = storageVersion;
    record.handoff = *handoff;
    record.checksum = pet_crc32(&record, offsetof(SaveRecord, checksum));
    return storage.putBytes(stateKey, &record, sizeof record) == sizeof record;
}

}
