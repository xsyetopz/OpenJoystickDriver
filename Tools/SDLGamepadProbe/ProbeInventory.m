#import "ProbeInventory.h"

#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static const char *const OJDGUIDs[] = {
    "0300f88c091200004f4a000008040000",
};

static const char *display_string(const char *value) {
  return value ? value : "(null)";
}

static bool is_ojd_guid(const char *guid) {
  for (size_t index = 0; index < sizeof(OJDGUIDs) / sizeof(OJDGUIDs[0]);
       index++) {
    if (strcmp(guid, OJDGUIDs[index]) == 0)
      return true;
  }
  return false;
}

static void pump_platform_events(void) {
  @autoreleasepool {
    [[NSRunLoop mainRunLoop]
           runMode:NSDefaultRunLoopMode
        beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
}

static SDL_JoystickID *enumerate_joysticks(int *joy_count) {
  pump_platform_events();
  SDL_UpdateJoysticks();
  SDL_UpdateGamepads();
  SDL_PumpEvents();
  return SDL_GetJoysticks(joy_count);
}

void OJDProbePrewarmGameController(void) {
  if (@available(macOS 11.3, *)) {
    GCController.shouldMonitorBackgroundEvents = YES;
  }
}

SDL_JoystickID *OJDProbeWaitForJoysticks(int wait_seconds, int *joy_count) {
  SDL_JoystickID *joy_ids = enumerate_joysticks(joy_count);
  if (*joy_count > 0 || wait_seconds <= 0)
    return joy_ids;

  SDL_free(joy_ids);
  Uint64 start = SDL_GetTicks();
  while ((SDL_GetTicks() - start) < (Uint64)(wait_seconds * 1000)) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_JOYSTICK_ADDED ||
          event.type == SDL_EVENT_GAMEPAD_ADDED) {
        joy_ids = enumerate_joysticks(joy_count);
        if (*joy_count > 0)
          return joy_ids;
        SDL_free(joy_ids);
      }
    }
    SDL_Delay(50);
    joy_ids = enumerate_joysticks(joy_count);
    if (*joy_count > 0)
      return joy_ids;
    SDL_free(joy_ids);
  }
  return enumerate_joysticks(joy_count);
}

void OJDProbePrintJoystick(SDL_JoystickID id) {
  SDL_GUID guid = SDL_GetJoystickGUIDForID(id);
  char guid_string[64];
  SDL_GUIDToString(guid, guid_string, (int)sizeof(guid_string));
  printf("- id=%u vid=0x%04x pid=0x%04x ver=0x%04x guid=%s\n", (unsigned)id,
         SDL_GetJoystickVendorForID(id), SDL_GetJoystickProductForID(id),
         SDL_GetJoystickProductVersionForID(id), guid_string);
  printf("  joystick_name=%s\n", display_string(SDL_GetJoystickNameForID(id)));
  printf("  is_gamepad=%s gamepad_name=%s\n", SDL_IsGamepad(id) ? "yes" : "no",
         display_string(SDL_GetGamepadNameForID(id)));
  if (!SDL_IsGamepad(id))
    return;

  char *mapping = SDL_GetGamepadMappingForID(id);
  printf("  mapping=%s\n", mapping ? mapping : "(null)");
  SDL_free(mapping);
  SDL_Gamepad *gamepad = SDL_OpenGamepad(id);
  if (!gamepad) {
    printf("  open_gamepad_failed=%s\n", SDL_GetError());
    return;
  }
  printf("  gamepad_axes:");
  for (int axis = 0; axis < SDL_GAMEPAD_AXIS_COUNT; axis++)
    printf(" a%d=%d", axis, SDL_GetGamepadAxis(gamepad, (SDL_GamepadAxis)axis));
  printf("\n  gamepad_buttons:");
  for (int button = 0; button < SDL_GAMEPAD_BUTTON_COUNT; button++)
    printf(" b%d=%d", button,
           SDL_GetGamepadButton(gamepad, (SDL_GamepadButton)button));
  printf("\n");
  SDL_CloseGamepad(gamepad);
}

int OJDProbeCheckSingleNeutralOJD(SDL_JoystickID *joy_ids, int joy_count) {
  int ojd_count = 0;
  int failures = 0;
  for (int index = 0; index < joy_count; index++) {
    SDL_GUID guid = SDL_GetJoystickGUIDForID(joy_ids[index]);
    char guid_string[64];
    SDL_GUIDToString(guid, guid_string, (int)sizeof(guid_string));
    if (!is_ojd_guid(guid_string))
      continue;
    ojd_count++;
    if (!SDL_IsGamepad(joy_ids[index])) {
      printf("EXPECT_FAIL: OJD device is not classified as a gamepad\n");
      failures++;
      continue;
    }
    SDL_Gamepad *gamepad = SDL_OpenGamepad(joy_ids[index]);
    if (!gamepad) {
      printf("EXPECT_FAIL: OJD gamepad open failed: %s\n", SDL_GetError());
      failures++;
      continue;
    }
    for (int axis = 0; axis < SDL_GAMEPAD_AXIS_COUNT; axis++) {
      if (SDL_GetGamepadAxis(gamepad, (SDL_GamepadAxis)axis) != 0) {
        printf("EXPECT_FAIL: OJD idle axis %d is not neutral\n", axis);
        failures++;
      }
    }
    for (int button = 0; button < SDL_GAMEPAD_BUTTON_COUNT; button++) {
      if (SDL_GetGamepadButton(gamepad, (SDL_GamepadButton)button)) {
        printf("EXPECT_FAIL: OJD idle button %d is pressed\n", button);
        failures++;
      }
    }
    SDL_CloseGamepad(gamepad);
  }
  if (ojd_count != 1) {
    printf("EXPECT_FAIL: found %d OJD gamepad(s), expected 1\n", ojd_count);
    failures++;
  }
  if (failures == 0)
    printf("EXPECT_PASS: exactly one neutral OJD gamepad\n");
  return failures == 0 ? 0 : 3;
}
