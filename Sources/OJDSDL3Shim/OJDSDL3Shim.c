#include "OJDSDL3Shim.h"

#include <SDL3/SDL.h>
#include <stddef.h>
#include <string.h>

static void copy_c_string(char *dst, size_t capacity, const char *src) {
    if (!dst || capacity == 0) {
        return;
    }
    if (!src) {
        dst[0] = '\0';
        return;
    }
    SDL_strlcpy(dst, src, capacity);
}

bool ojd_sdl3_init(void) {
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_XBOX, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_XBOX_360, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_XBOX_360_WIRELESS, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_XBOX_ONE, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_GIP, "1");
    SDL_SetHint(SDL_HINT_HIDAPI_LIBUSB, "1");
    return SDL_Init(SDL_INIT_GAMEPAD | SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC | SDL_INIT_EVENTS);
}

void ojd_sdl3_quit(void) {
    SDL_Quit();
}

void ojd_sdl3_pump(void) {
    SDL_UpdateJoysticks();
    SDL_UpdateGamepads();
    SDL_PumpEvents();
}

int ojd_sdl3_get_gamepad_ids(int32_t *buffer, int capacity) {
    if (!buffer || capacity <= 0) {
        return 0;
    }

    int count = 0;
    SDL_JoystickID *ids = SDL_GetGamepads(&count);
    if (!ids || count <= 0) {
        SDL_free(ids);
        return 0;
    }
    int copied = count < capacity ? count : capacity;
    for (int i = 0; i < copied; i++) {
        buffer[i] = (int32_t)ids[i];
    }
    SDL_free(ids);
    return copied;
}

bool ojd_sdl3_get_identity(int32_t instance_id, OJDSDL3DeviceIdentity *identity) {
    if (!identity) {
        return false;
    }
    SDL_JoystickID id = (SDL_JoystickID)instance_id;
    memset(identity, 0, sizeof(*identity));
    identity->instance_id = instance_id;
    identity->vendor_id = SDL_GetJoystickVendorForID(id);
    identity->product_id = SDL_GetJoystickProductForID(id);
    identity->version = SDL_GetJoystickProductVersionForID(id);
    identity->is_gamepad = SDL_IsGamepad(id);
    copy_c_string(identity->name, sizeof(identity->name), SDL_GetGamepadNameForID(id));
    if (identity->name[0] == '\0') {
        copy_c_string(identity->name, sizeof(identity->name), SDL_GetJoystickNameForID(id));
    }
    SDL_GUID guid = SDL_GetJoystickGUIDForID(id);
    SDL_GUIDToString(guid, identity->guid, (int)sizeof(identity->guid));
    SDL_Joystick *joy = SDL_OpenJoystick(id);
    if (joy) {
        copy_c_string(identity->serial, sizeof(identity->serial), SDL_GetJoystickSerial(joy));
        SDL_CloseJoystick(joy);
    }
    return true;
}

OJDSDL3GamepadRef ojd_sdl3_open_gamepad(int32_t instance_id) {
    return (OJDSDL3GamepadRef)SDL_OpenGamepad((SDL_JoystickID)instance_id);
}

void ojd_sdl3_close_gamepad(OJDSDL3GamepadRef gamepad) {
    if (gamepad) {
        SDL_CloseGamepad((SDL_Gamepad *)gamepad);
    }
}

bool ojd_sdl3_read_snapshot(OJDSDL3GamepadRef gamepad, OJDSDL3GamepadSnapshotRaw *snapshot) {
    if (!gamepad || !snapshot) {
        return false;
    }
    SDL_Gamepad *gp = (SDL_Gamepad *)gamepad;
    for (int axis = 0; axis < 6; axis++) {
        snapshot->axes[axis] = SDL_GetGamepadAxis(gp, (SDL_GamepadAxis)axis);
    }
    for (int button = 0; button < 26; button++) {
        snapshot->buttons[button] = SDL_GetGamepadButton(gp, (SDL_GamepadButton)button) ? 1 : 0;
    }
    return true;
}

bool ojd_sdl3_rumble_gamepad(
    OJDSDL3GamepadRef gamepad,
    uint16_t low,
    uint16_t high,
    uint32_t duration_ms) {
    if (!gamepad) {
        return false;
    }
    return SDL_RumbleGamepad((SDL_Gamepad *)gamepad, low, high, duration_ms);
}

bool ojd_sdl3_rumble_gamepad_triggers(
    OJDSDL3GamepadRef gamepad,
    uint16_t left,
    uint16_t right,
    uint32_t duration_ms) {
    if (!gamepad) {
        return false;
    }
    return SDL_RumbleGamepadTriggers((SDL_Gamepad *)gamepad, left, right, duration_ms);
}

const char *ojd_sdl3_error(void) {
    return SDL_GetError();
}

int ojd_sdl3_linked_version(void) {
    return SDL_GetVersion();
}
