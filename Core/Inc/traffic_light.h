#ifndef TRAFFIC_LIGHT_H
#define TRAFFIC_LIGHT_H

#include <stdbool.h>
#include <stdint.h>

void traffic_light_init(uint32_t now);
void traffic_light_update(uint32_t now, bool button_pressed_event);

#endif // !TRAFFIC_LIGHT_H
