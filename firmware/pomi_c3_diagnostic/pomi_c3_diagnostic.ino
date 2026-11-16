#include <Arduino.h>
#include <Wire.h>

constexpr int sdaPin = 7;
constexpr int sclPin = 3;
constexpr uint8_t buttonPins[] = {0, 4, 6, 10};
const char *const buttonNames[] = {"FEED", "PET", "SLEEP", "PLAY"};
uint8_t oledAddress = 0;
uint8_t sensorAddress = 0;
bool rawPressed[4] = {};
bool pressed[4] = {};
uint32_t changedAt[4] = {};

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

bool writeI2C(uint8_t address, uint8_t prefix, const uint8_t *bytes, size_t count) {
    Wire.beginTransmission(address);
    Wire.write(prefix);
    Wire.write(bytes, count);
    return Wire.endTransmission() == 0;
}

bool readRegisters(uint8_t address, uint8_t reg, uint8_t *bytes, size_t count) {
    Wire.beginTransmission(address);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0 || Wire.requestFrom(address, count) != count) {
        return false;
    }
    for (size_t i = 0; i < count; ++i) {
        bytes[i] = Wire.read();
    }
    return true;
}

bool present(uint8_t address) {
    Wire.beginTransmission(address);
    return Wire.endTransmission() == 0;
}

void textPage(uint8_t page, const char *text) {
    uint8_t row[128] = {};
    for (size_t x = 6; *text && x + 3 <= sizeof row; ++text, x += 4) {
        const char c = *text;
        const uint8_t *glyph = c >= 'A' && c <= 'Z' ? letters[c - 'A']
                             : c >= '0' && c <= '9' ? digits[c - '0'] : nullptr;
        if (glyph) memcpy(row + x, glyph, 3);
    }
    const uint8_t position[] = {uint8_t(0xB0 | page), 0x00, 0x10};
    if (!writeI2C(oledAddress, 0x00, position, sizeof position)) return;
    for (size_t x = 0; x < sizeof row; x += 16) {
        if (!writeI2C(oledAddress, 0x40, row + x, 16)) return;
    }
}

void setup() {
    Serial.begin(115200);
    Wire.begin(sdaPin, sclPin, 100000);
    for (size_t i = 0; i < 4; ++i) pinMode(buttonPins[i], INPUT_PULLUP);
    // Give the USB console and modules a moment to start.
    delay(500);
    Serial.println("POMI TEST | SDA GPIO7 | SCL GPIO3");

    if (present(0x3C)) oledAddress = 0x3C;
    else if (present(0x3D)) oledAddress = 0x3D;
    if (oledAddress) {
        const uint8_t init[] = {
            0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40,
            0x8D, 0x14, 0x20, 0x02, 0xA1, 0xC8, 0xDA, 0x12,
            0x81, 0x7F, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0x2E
        };
        const uint8_t on = 0xAF;
        if (writeI2C(oledAddress, 0x00, init, sizeof init)) {
            for (uint8_t page = 0; page < 8; ++page) textPage(page, "");
            textPage(1, "POMI TEST");
            textPage(5, "PRESS A BUTTON");
            writeI2C(oledAddress, 0x00, &on, 1);
        }
    }
    if (oledAddress) Serial.printf("OLED 0x%02X\n", oledAddress);
    else Serial.println("OLED NOT FOUND (0x3C/0x3D)");

    for (uint8_t candidate : {0x19, 0x18}) {
        uint8_t identity = 0;
        if (readRegisters(candidate, 0x0F, &identity, 1) && identity == 0x33) {
            const uint8_t highResolution = 0x88;
            const uint8_t enabled = 0x47;
            if (writeI2C(candidate, 0x23, &highResolution, 1) &&
                writeI2C(candidate, 0x20, &enabled, 1)) {
                sensorAddress = candidate;
                break;
            }
        }
    }
    if (sensorAddress) Serial.printf("LIS3DH 0x%02X WHO_AM_I 0x33\n", sensorAddress);
    else Serial.println("LIS3DH NOT FOUND (0x18/0x19)");
    if (oledAddress) textPage(3, sensorAddress ? "LIS3DH OK" : "LIS3DH MISSING");
}

void loop() {
    const uint32_t now = millis();
    for (size_t i = 0; i < 4; ++i) {
        const bool down = digitalRead(buttonPins[i]) == LOW;
        if (rawPressed[i] != down) {
            rawPressed[i] = down;
            changedAt[i] = now;
        }
        if (pressed[i] != down && now - changedAt[i] >= 25) {
            pressed[i] = down;
            if (down) {
                Serial.printf("BUTTON %s GPIO%u\n", buttonNames[i], buttonPins[i]);
                if (oledAddress) textPage(5, buttonNames[i]);
            }
        }
    }

    static uint32_t lastReport = 0;
    if (now - lastReport >= 500) {
        lastReport = now;
        uint8_t bytes[6];
        if (sensorAddress && readRegisters(sensorAddress, 0x28 | 0x80, bytes, sizeof bytes)) {
            int axes[3];
            for (size_t i = 0; i < 3; ++i) {
                axes[i] = int16_t(uint16_t(bytes[i * 2]) | (uint16_t(bytes[i * 2 + 1]) << 8)) / 16;
            }
            Serial.printf("LIS3DH X=%d Y=%d Z=%d mg\n", axes[0], axes[1], axes[2]);
        } else {
            Serial.println("LIS3DH NO DATA");
        }
    }
    delay(5);
}
