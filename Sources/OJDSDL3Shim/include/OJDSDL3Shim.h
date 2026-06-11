#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *OJDSDL3GamepadRef;

typedef struct OJDSDL3DeviceIdentity {
    int32_t instance_id;
    uint16_t vendor_id;
    uint16_t product_id;
    uint16_t version;
    char name[128];
    char serial[128];
    char guid[64];
    bool is_gamepad;
} OJDSDL3DeviceIdentity;

typedef struct OJDSDL3GamepadSnapshotRaw {
    int16_t axes[6];
    uint8_t buttons[26];
} OJDSDL3GamepadSnapshotRaw;

bool ojd_sdl3_init(void);
void ojd_sdl3_quit(void);
void ojd_sdl3_pump(void);
int ojd_sdl3_get_gamepad_ids(int32_t *buffer, int capacity);
bool ojd_sdl3_get_identity(int32_t instance_id, OJDSDL3DeviceIdentity *identity);
OJDSDL3GamepadRef ojd_sdl3_open_gamepad(int32_t instance_id);
void ojd_sdl3_close_gamepad(OJDSDL3GamepadRef gamepad);
bool ojd_sdl3_read_snapshot(OJDSDL3GamepadRef gamepad, OJDSDL3GamepadSnapshotRaw *snapshot);
bool ojd_sdl3_rumble_gamepad(
    OJDSDL3GamepadRef gamepad,
    uint16_t low,
    uint16_t high,
    uint32_t duration_ms);
bool ojd_sdl3_rumble_gamepad_triggers(
    OJDSDL3GamepadRef gamepad,
    uint16_t left,
    uint16_t right,
    uint32_t duration_ms);
const char *ojd_sdl3_error(void);
int ojd_sdl3_linked_version(void);

#ifdef __cplusplus
}
#endif
