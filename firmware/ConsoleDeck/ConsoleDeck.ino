#include <Arduino.h>

const uint8_t clockwiseLead = 4;
const uint8_t otherPhase = 3;
const unsigned long debounceMs = 25;

struct Button {
  uint8_t pin;
  const char *event;
  bool raw;
  bool stable;
  unsigned long changedAt;
};

Button buttons[] = {
  {12, "BUTTON_1"}, {A1, "BUTTON_2"}, {11, "BUTTON_3"},
  {A0, "BUTTON_4"}, {9, "BUTTON_5"}, {10, "BUTTON_6"},
  {5, "BUTTON_7"}, {6, "BUTTON_8"}, {7, "BUTTON_9"},
  {8, "MEDIA"}, {2, "MUTE"},
};

uint8_t previousPhase;
int8_t rotation = 0;

uint8_t readPhase() {
  return (digitalRead(clockwiseLead) == LOW)
         | ((digitalRead(otherPhase) == LOW) << 1);
}

void readEncoder() {
  const uint8_t phase = readPhase();
  if (phase == previousPhase) return;

  // A clockwise cycle runs through 00, 01, 11, 10, then 00.
  const int8_t steps[4][4] = {
    {0, 1, -1, 0},
    {-1, 0, 0, 1},
    {1, 0, 0, -1},
    {0, -1, 1, 0},
  };
  const int8_t step = steps[previousPhase][phase];
  previousPhase = phase;
  rotation = step == 0 ? 0 : rotation + step;

  // This encoder rests at both 00 and 11. A detent spans two valid edges.
  if (phase == 0 || phase == 3) {
    if (rotation == 2) Serial.println(F("VOLUME_UP"));
    if (rotation == -2) Serial.println(F("VOLUME_DOWN"));
    rotation = 0;
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(clockwiseLead, INPUT_PULLUP);
  pinMode(otherPhase, INPUT_PULLUP);
  previousPhase = readPhase();
  for (Button &button : buttons) {
    pinMode(button.pin, INPUT_PULLUP);
    button.raw = button.stable = digitalRead(button.pin) == LOW;
  }
  Serial.println(F("READY CONSOLEDECK_V1"));
}

void loop() {
  readEncoder();
  if (Serial.available() && Serial.read() == '?') {
    Serial.println(F("READY CONSOLEDECK_V1"));
  }

  const unsigned long now = millis();
  for (Button &button : buttons) {
    const bool pressed = digitalRead(button.pin) == LOW;
    if (pressed != button.raw) {
      button.raw = pressed;
      button.changedAt = now;
    }
    if (pressed != button.stable && now - button.changedAt >= debounceMs) {
      button.stable = pressed;
      if (pressed) Serial.println(button.event);
    }
  }
}
