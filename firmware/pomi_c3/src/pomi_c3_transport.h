#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void pomi_transport_init(uint32_t identity[4]);
bool pomi_transport_receive(char *frame, size_t capacity);
void pomi_transport_send(const char *bytes, size_t size);
#ifdef __cplusplus
}
#endif
