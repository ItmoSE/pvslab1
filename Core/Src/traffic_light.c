#include "traffic_light.h"
#include "led.h"

typedef enum {
  TRAFFIC_RED,
  TRAFFIC_YELLOW,
  TRAFFIC_GREEN,
  TRAFFIC_BLINK_GREEN
} traffic_state_t;

static uint32_t init_time;
static uint32_t last_blink_green;
static traffic_state_t current_state;
static uint32_t time_to_shine_red;
static bool reduce_red_time = false;

void traffic_light_init(uint32_t now) {
  init_time = now;
  current_state = TRAFFIC_RED;
  time_to_shine_red = 12000u;
  reduce_red_time = false;

  led_set(LED_GREEN, false);
  led_set(LED_YELLOW, false);
  led_set(LED_RED, true);
}

void traffic_light_update(uint32_t now, bool button_pressed_event) {

  if (button_pressed_event && (current_state == TRAFFIC_BLINK_GREEN ||
                               current_state == TRAFFIC_YELLOW)) {
    reduce_red_time = true;
  }

  switch (current_state) {

  case TRAFFIC_RED:
    if (button_pressed_event && (now - init_time) < time_to_shine_red &&
        time_to_shine_red - (now - init_time) > 3000u) {
      time_to_shine_red = (now - init_time) + 3000u;
    }

    if ((now - init_time) >= time_to_shine_red) {
      led_set(LED_RED, false);
      led_set(LED_GREEN, true);

      current_state = TRAFFIC_GREEN;
      init_time = now;
    }
    break;

  case TRAFFIC_GREEN:
    if ((now - init_time) >= 3000u) {
      // green is already on, let it shine
      current_state = TRAFFIC_BLINK_GREEN;
      init_time = now;
      last_blink_green = now;
    }
    break;

  case TRAFFIC_BLINK_GREEN:
    if ((now - init_time) < 2000u && (now - last_blink_green) >= 300u) {
      led_toggle(LED_GREEN);
      last_blink_green = now;
    }
    if ((now - init_time) >= 2000u) {
      led_set(LED_GREEN, false);
      led_set(LED_YELLOW, true);
      current_state = TRAFFIC_YELLOW;
      init_time = now;
    }
    break;

  case TRAFFIC_YELLOW:
    if ((now - init_time) >= 3000u) {
      led_set(LED_YELLOW, false);
      led_set(LED_RED, true);

      time_to_shine_red = reduce_red_time ? 12000u / 4 : 12000u;
      reduce_red_time = false;
      current_state = TRAFFIC_RED;
      init_time = now;
    }
    break;

  default:
    break;
  }
}
