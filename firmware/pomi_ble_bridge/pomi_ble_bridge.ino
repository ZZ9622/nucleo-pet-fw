#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <atomic>

// Verified from the attached module's previous firmware: RX=4, TX=5, 115200 8N1.
#ifndef POMI_UART_RX
#define POMI_UART_RX 4
#endif
#ifndef POMI_UART_TX
#define POMI_UART_TX 5
#endif
static const char *SERVICE="a27c38e1-9447-454a-898f-f1b8719391e3";
static const char *CHANNEL="87a0909e-5440-4883-a0b9-5fb589496ad8";
struct Frame { uint32_t epoch; uint16_t length; char data[1024]; };
static QueueHandle_t requests;
static BLECharacteristic *channel;
static std::atomic<bool> connected{false}, advertise{false};
static std::atomic<uint32_t> epoch{0};
static char input[1024];
static size_t inputSize;
static std::atomic<unsigned> bleBytes{0}, goodFrames{0}, uartBytes{0};
static uint32_t crc32(const char *data,size_t size) {
  uint32_t crc=0xffffffff;
  for(size_t i=0;i<size;++i){crc^=(uint8_t)data[i];for(unsigned j=0;j<8;++j){crc=(crc>>1)^((crc&1)?0xedb88320:0);}}
  return crc^0xffffffff;
}
static bool valid(const char *data,size_t size) {
  if(size && data[size-1]=='\n'){--size;}
  if(size<10 || data[size-9]!='|'){return false;}
  uint32_t expected=0;
  for(size_t i=size-8;i<size;++i){char c=data[i];unsigned d=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:99;if(d>15){return false;}expected=expected*16+d;}
  return crc32(data,size-9)==expected;
}
class ServerEvents: public BLEServerCallbacks {
  void onConnect(BLEServer *) override { inputSize=0;epoch.fetch_add(1);connected=true; }
  void onDisconnect(BLEServer *) override { connected=false;epoch.fetch_add(1);inputSize=0;advertise=true; }
};
class ChannelEvents: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    const String value=c->getValue();
    bleBytes.fetch_add(value.length());
    for(size_t i=0;i<value.length();++i){
      const char byte=value[i];
      if(byte=='!'){inputSize=0;}
      if(inputSize==0 && byte!='!'){continue;}
      if(inputSize>=sizeof(input)-1){inputSize=0;continue;}
      input[inputSize++]=byte;
      if(byte=='\n'){
        if(inputSize>35 && valid(input,inputSize)){
          goodFrames.fetch_add(1);
          Frame frame;frame.epoch=epoch.load();frame.length=inputSize;memcpy(frame.data,input,inputSize);frame.data[inputSize]=0;
          xQueueSend(requests,&frame,0); // A full queue drops a request; client retries the SAME transaction.
        }
        inputSize=0;
      }
    }
  }
};
void setup() {
  Serial.begin(115200);
  Serial1.setRxBufferSize(2048);
  Serial1.begin(115200,SERIAL_8N1,POMI_UART_RX,POMI_UART_TX);
  requests=xQueueCreate(2,sizeof(Frame));
  if(!requests){Serial.println("Pomi bridge queue allocation failed");return;}
  BLEDevice::init("Pomi");BLEDevice::setMTU(185);
  BLEServer *server=BLEDevice::createServer();server->setCallbacks(new ServerEvents());
  BLEService *service=server->createService(SERVICE);
  channel=service->createCharacteristic(CHANNEL,BLECharacteristic::PROPERTY_READ|BLECharacteristic::PROPERTY_WRITE|BLECharacteristic::PROPERTY_NOTIFY);
  channel->addDescriptor(new BLE2902());channel->setCallbacks(new ChannelEvents());channel->setValue("POMI BLE BRIDGE V2");service->start();
  BLEAdvertisementData data;data.setFlags(0x06);data.setCompleteServices(BLEUUID(SERVICE));data.setName("Pomi");
  BLEAdvertising *adv=server->getAdvertising();adv->setAdvertisementData(data);adv->start();
  Serial.println("Pomi BLE bridge v2 ready; UART RX4 TX5 115200");
}
void loop() {
  static Frame active;
  static bool waiting=false;
  static uint32_t since=0;
  static char response[1536],requestID[33];
  static size_t used=0;
  if(advertise.exchange(false)){BLEDevice::startAdvertising();}
  if(!requests || !channel){delay(10);return;}
  if(waiting && (!connected || active.epoch!=epoch.load() || (uint32_t)(millis()-since)>4000)){waiting=false;used=0;}
  if(!waiting && xQueueReceive(requests,&active,0)==pdTRUE){
    if(connected && active.epoch==epoch.load()){
      while(Serial1.available()){Serial1.read();}
      memcpy(requestID,active.data+1,32);requestID[32]=0;
      Serial1.write((const uint8_t *)active.data,active.length);
      used=0;since=millis();waiting=true;
    }
  }
  while(Serial1.available()){
    char c=(char)Serial1.read();
    uartBytes.fetch_add(1);
    if(!waiting){continue;}
    if(used>=sizeof(response)-1){used=0;waiting=false;continue;}
    response[used++]=c;
    if(c=='\n'){
      response[used]=0;
      if(valid(response,used) && strstr(response,requestID)){
        const uint32_t client=active.epoch;
        // 20-byte notifications work even if the peer keeps the default ATT MTU.
        for(size_t offset=0;offset<used && connected && client==epoch.load();offset+=20){
          size_t count=min((size_t)20,used-offset);
          channel->setValue((uint8_t *)response+offset,count);channel->notify();delay(6);
        }
        waiting=false;
      }
      used=0;
    }
  }
  static uint32_t lastLog=0;
  if((uint32_t)(millis()-lastLog)>1000){
    Serial.printf("BLE connected=%u bytes=%u frames=%u UARTrx=%u waiting=%u\n",(unsigned)connected.load(),bleBytes.load(),goodFrames.load(),uartBytes.load(),(unsigned)waiting);
    lastLog=millis();
  }
  delay(1);
}
