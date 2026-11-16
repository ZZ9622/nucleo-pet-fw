#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <atomic>
#include <esp_mac.h>
#include "pomi_c3_transport.h"

namespace {
constexpr char serviceUUID[] = "a27c38e1-9447-454a-898f-f1b8719391e3";
constexpr char channelUUID[] = "87a0909e-5440-4883-a0b9-5fb589496ad8";
constexpr size_t frameCapacity = 1024;
struct Frame {
    uint32_t connection;
    char text[frameCapacity];
};
QueueHandle_t requests;
BLECharacteristic *channel;
std::atomic<bool> connected{false};
std::atomic<bool> restartAdvertising{false};
std::atomic<uint32_t> connection{0};

struct FrameReader {
    char text[frameCapacity];
    size_t used = 0;

    bool add(char byte) {
        if (byte == '!') used = 0;
        if (used == 0 && byte != '!') return false;
        if (byte == '\n') {
            text[used] = '\0';
            used = 0;
            return true;
        }
        if (used == sizeof text - 1) {
            used = 0;
            return false;
        }
        text[used++] = byte;
        return false;
    }
};
FrameReader bleReader, usbReader;
bool replyViaBLE;
uint32_t replyConnection;

class ServerEvents : public BLEServerCallbacks {
    void onConnect(BLEServer *) override {
        bleReader.used = 0;
        ++connection;
        connected = true;
    }

    void onDisconnect(BLEServer *) override {
        connected = false;
        ++connection;
        bleReader.used = 0;
        restartAdvertising = true;
    }
};

class ChannelEvents : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *source) override {
        const String value = source->getValue();
        const uint32_t current = connection.load();
        for (size_t i = 0; i < value.length(); ++i) {
            if (bleReader.add(value[i])) {
                Frame frame{};
                frame.connection = current;
                strcpy(frame.text, bleReader.text);
                xQueueSend(requests, &frame, 0);
            }
        }
    }
};
}

extern "C" void pomi_transport_init(uint32_t identity[4]) {
    Serial.begin(115200);
    uint8_t mac[6] = {};
    esp_efuse_mac_get_default(mac);
    identity[0] = 0x504f4d49;  // Distinguishes this board from the STM32 UID.
    identity[1] = (uint32_t(mac[0]) << 24) | (uint32_t(mac[1]) << 16) |
                  (uint32_t(mac[2]) << 8) | mac[3];
    identity[2] = (uint32_t(mac[4]) << 8) | mac[5];
    identity[3] = 1;

    requests = xQueueCreate(2, sizeof(Frame));
    if (!requests) return;
    BLEDevice::init("Pomi");
    BLEDevice::setMTU(185);
    BLEServer *server = BLEDevice::createServer();
    server->setCallbacks(new ServerEvents());
    BLEService *service = server->createService(serviceUUID);
    channel = service->createCharacteristic(
        channelUUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE |
                     BLECharacteristic::PROPERTY_NOTIFY);
    channel->addDescriptor(new BLE2902());
    channel->setCallbacks(new ChannelEvents());
    channel->setValue("POMI C3 V2");
    service->start();
    BLEAdvertisementData advertisement;
    advertisement.setFlags(0x06);
    advertisement.setCompleteServices(BLEUUID(serviceUUID));
    advertisement.setName("Pomi");
    BLEAdvertising *advertising = server->getAdvertising();
    advertising->setAdvertisementData(advertisement);
    advertising->start();
}

extern "C" bool pomi_transport_receive(char *frame, size_t capacity) {
    if (restartAdvertising.exchange(false)) BLEDevice::startAdvertising();
    Frame pending;
    if (requests && xQueueReceive(requests, &pending, 0) == pdTRUE &&
        connected && connection.load() == pending.connection &&
        strlen(pending.text) < capacity) {
        strcpy(frame, pending.text);
        replyViaBLE = true;
        replyConnection = pending.connection;
        return true;
    }

    for (unsigned reads = 0; reads < frameCapacity && Serial.available(); ++reads) {
        if (usbReader.add(char(Serial.read())) && strlen(usbReader.text) < capacity) {
            strcpy(frame, usbReader.text);
            replyViaBLE = false;
            return true;
        }
    }
    return false;
}

extern "C" void pomi_transport_send(const char *bytes, size_t size) {
    if (!replyViaBLE) {
        Serial.write(reinterpret_cast<const uint8_t *>(bytes), size);
        return;
    }
    for (size_t offset = 0; offset < size && connected && replyConnection == connection.load(); offset += 20) {
        const size_t chunk = min(size_t(20), size - offset);
        channel->setValue(reinterpret_cast<const uint8_t *>(bytes + offset), chunk);
        channel->notify();
        delay(6);
    }
}
