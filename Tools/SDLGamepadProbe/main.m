#import "ProbeInventory.h"

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *env_or_unset(const char *key) {
    // The probe reads the environment on its only thread, before it starts SDL.
    // NOLINTNEXTLINE(concurrency-mt-unsafe)
    const char *value = getenv(key);
    return value ? value : "(unset)";
}

static bool has_flag(int argc, char **argv, const char *flag) {
    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], flag) == 0) {
            return true;
        }
    }
    return false;
}

enum {
    MaxSeconds = 3600,
    MaxWaitSeconds = 30,
    AxisLeaveRest = 8000,
    AxisReturnRest = 2000,
    MaxTrackedGamepads = 32,
    ErrorBufferSize = 128,
};

typedef struct {
    bool active;
    int peak;
} AxisState;

typedef struct {
    bool used;
    SDL_JoystickID which;
    AxisState axes[SDL_GAMEPAD_AXIS_COUNT];
} GamepadAxisState;

static GamepadAxisState axis_states[MaxTrackedGamepads];

static GamepadAxisState *axis_state_for(SDL_JoystickID which, bool create) {
    GamepadAxisState *free_slot = NULL;
    for (int index = 0; index < MaxTrackedGamepads; index++) {
        if (axis_states[index].used && axis_states[index].which == which) {
            return &axis_states[index];
        }
        if (!axis_states[index].used && !free_slot) {
            free_slot = &axis_states[index];
        }
    }
    if (!create || !free_slot) {
        return NULL;
    }
    memset(free_slot, 0, sizeof(*free_slot));
    free_slot->used = true;
    free_slot->which = which;
    return free_slot;
}

static void clear_axis_state(SDL_JoystickID which) {
    GamepadAxisState *state = axis_state_for(which, false);
    if (state) {
        memset(state, 0, sizeof(*state));
    }
}

static void handle_axis_motion(const SDL_GamepadAxisEvent *event) {
    if (event->axis >= SDL_GAMEPAD_AXIS_COUNT) {
        return;
    }
    GamepadAxisState *state = axis_state_for(event->which, true);
    if (!state) {
        fprintf(stderr, "WARN: too many gamepads to track axis state (which=%u)\n",
                (unsigned)event->which);
        return;
    }
    AxisState *axis = &state->axes[event->axis];
    int value = (int)event->value;
    if (!axis->active) {
        if (abs(value) > AxisLeaveRest) {
            axis->active = true;
            axis->peak = value;
            printf("GAMEPAD_AXIS which=%u axis=%d left-rest value=%d\n", (unsigned)event->which,
                   (int)event->axis, value);
        }
        return;
    }
    if (abs(value) > abs(axis->peak)) {
        axis->peak = value;
    }
    if (abs(value) < AxisReturnRest) {
        printf("GAMEPAD_AXIS which=%u axis=%d rest value=%d peak=%d\n", (unsigned)event->which,
               (int)event->axis, value, axis->peak);
        axis->active = false;
        axis->peak = 0;
    }
}

static void print_usage(FILE *stream) {
    fprintf(stream,
            "Usage: SDLGamepadProbe [--seconds N] [--wait-devices N] [--rumble] [--expect-rumble]\n"
            "                       [--expect-single-neutral-ojd] [--gc-prewarm] [--video]\n"
            "                       [--mappings-file PATH] [--help]\n"
            "\n"
            "  --seconds N         Listen for events for N seconds, 1 to %d (default 10).\n"
            "  --wait-devices N    Wait up to N seconds for joysticks, 0 to %d (default 0).\n"
            "  --help              Show this help.\n",
            MaxSeconds, MaxWaitSeconds);
}

/* Returns false when the option is present with a missing or invalid value. */
static bool parse_int_arg(int argc, char **argv, const char *name, int minimum, int maximum,
                          int *value) {
    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], name) != 0) {
            continue;
        }
        if (index + 1 >= argc) {
            fprintf(stderr, "ERROR: %s requires a value\n", name);
            return false;
        }
        char *end = NULL;
        errno = 0;
        long parsed = strtol(argv[index + 1], &end, 10);
        if (errno != 0 || end == argv[index + 1] || *end != '\0' || parsed < minimum ||
            parsed > maximum) {
            fprintf(stderr, "ERROR: %s must be an integer from %d to %d, got '%s'\n", name, minimum,
                    maximum, argv[index + 1]);
            return false;
        }
        *value = (int)parsed;
        return true;
    }
    return true;
}

static const char *parse_mappings_file(int argc, char **argv) {
    for (int index = 1; index + 1 < argc; index++) {
        if (strcmp(argv[index], "--mappings-file") == 0) {
            return argv[index + 1];
        }
    }
    return NULL;
}

static void print_environment(void) {
    int version = SDL_GetVersion();
    printf("SDL linked version: %d.%d.%d (raw=%d)\n", SDL_VERSIONNUM_MAJOR(version),
           SDL_VERSIONNUM_MINOR(version), SDL_VERSIONNUM_MICRO(version), version);
    printf("SDL platform: %s\n", SDL_GetPlatform());
    printf("SDL_JOYSTICK_MFI=%s\n", env_or_unset("SDL_JOYSTICK_MFI"));
    printf("SDL_JOYSTICK_IOKIT=%s\n", env_or_unset("SDL_JOYSTICK_IOKIT"));
    printf("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=%s\n",
           env_or_unset("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"));
    printf("SDL_JOYSTICK_HIDAPI_XBOX=%s\n", env_or_unset("SDL_JOYSTICK_HIDAPI_XBOX"));
    printf("SDL_JOYSTICK_HIDAPI_XBOX_ONE=%s\n", env_or_unset("SDL_JOYSTICK_HIDAPI_XBOX_ONE"));
}

static void print_events(int seconds, const SDL_JoystickID *joy_ids, int joy_count,
                         SDL_Gamepad **gamepads) {
    printf("\nListening for %ds (press buttons now) ...\n", seconds);
    Uint64 start = SDL_GetTicks();
    while ((SDL_GetTicks() - start) < (Uint64)seconds * 1000) {
        SDL_UpdateGamepads();
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
                case SDL_EVENT_GAMEPAD_BUTTON_UP:
                    printf("GAMEPAD_BUTTON %s which=%u button=%d\n",
                           event.type == SDL_EVENT_GAMEPAD_BUTTON_DOWN ? "down" : "up",
                           (unsigned)event.gbutton.which, (int)event.gbutton.button);
                    break;
                case SDL_EVENT_GAMEPAD_AXIS_MOTION:
                    handle_axis_motion(&event.gaxis);
                    break;
                case SDL_EVENT_GAMEPAD_REMOVED:
                    clear_axis_state(event.gdevice.which);
                    break;
                default:
                    break;
            }
        }
        for (int index = 0; index < joy_count; index++) {
            if (gamepads[index]) {
                SDL_UpdateGamepads();
            }
        }
        SDL_Delay(1);
    }
    (void)joy_ids;
}

static int rumble_gamepads(SDL_JoystickID *joy_ids, int joy_count, SDL_Gamepad **gamepads) {
    int attempts = 0;
    int failures = 0;
    printf("\nMain-motor rumble probe:\n");
    for (int index = 0; index < joy_count; index++) {
        if (!gamepads[index]) {
            continue;
        }
        attempts++;
        bool ok = SDL_RumbleGamepad(gamepads[index], 0x9000, 0x6000, 300);
        failures += !ok;
        printf("- id=%u SDL_RumbleGamepad=%s%s%s\n", (unsigned)joy_ids[index], ok ? "ok" : "failed",
               ok ? "" : " error=", ok ? "" : SDL_GetError());
    }
    return attempts == 0 || failures > 0 ? 4 : 0;
}

static void report_errno(const char *what, int error) {
    char message[ErrorBufferSize];
    if (strerror_r(error, message, sizeof(message)) != 0) {
        snprintf(message, sizeof(message), "errno %d", error);
    }
    fprintf(stderr, "ERROR: %s: %s\n", what, message);
}

int main(int argc, char **argv) {
    if (has_flag(argc, argv, "--help") || has_flag(argc, argv, "-h")) {
        print_usage(stdout);
        return 0;
    }
    int seconds = 10;
    int wait_seconds = 0;
    if (!parse_int_arg(argc, argv, "--seconds", 1, MaxSeconds, &seconds) ||
        !parse_int_arg(argc, argv, "--wait-devices", 0, MaxWaitSeconds, &wait_seconds)) {
        print_usage(stderr);
        return 2;
    }
    bool rumble = has_flag(argc, argv, "--rumble");
    bool expect_rumble = has_flag(argc, argv, "--expect-rumble");
    bool expect_neutral = has_flag(argc, argv, "--expect-single-neutral-ojd");
    print_environment();
    if (has_flag(argc, argv, "--gc-prewarm")) {
        OJDProbePrewarmGameController();
    }

    SDL_InitFlags flags = SDL_INIT_GAMEPAD | SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC | SDL_INIT_EVENTS;
    if (has_flag(argc, argv, "--video")) {
        flags |= SDL_INIT_VIDEO;
    }
    if (!SDL_Init(flags)) {
        fprintf(stderr, "ERROR: SDL_Init failed: %s\n", SDL_GetError());
        return 2;
    }
    SDL_SetGamepadEventsEnabled(true);
    const char *mappings_file = parse_mappings_file(argc, argv);
    if (mappings_file) {
        printf("Loaded mappings: %d (%s)\n", SDL_AddGamepadMappingsFromFile(mappings_file),
               mappings_file);
    }

    int joy_count = 0;
    SDL_JoystickID *joy_ids = OJDProbeWaitForJoysticks(wait_seconds, &joy_count);
    printf("\nFound %d joystick(s)\n", joy_count);
    SDL_Gamepad **gamepads = (SDL_Gamepad **)calloc((size_t)joy_count, sizeof(*gamepads));
    if (joy_count > 0 && !gamepads) {
        report_errno("calloc failed", errno);
        SDL_free(joy_ids);
        SDL_Quit();
        return 2;
    }
    for (int index = 0; index < joy_count; index++) {
        OJDProbePrintJoystick(joy_ids[index]);
        if (SDL_IsGamepad(joy_ids[index])) {
            gamepads[index] = SDL_OpenGamepad(joy_ids[index]);
        }
    }
    int result = expect_neutral ? OJDProbeCheckSingleNeutralOJD(joy_ids, joy_count) : 0;
    int rumble_result = 0;
    if (rumble) {
        rumble_result = rumble_gamepads(joy_ids, joy_count, gamepads);
    }
    if (expect_rumble && rumble_result == 0 && !rumble) {
        rumble_result = 4;
    }
    if (expect_rumble && rumble_result) {
        result = rumble_result;
    }
    print_events(seconds, joy_ids, joy_count, gamepads);
    for (int index = 0; index < joy_count; index++) {
        if (gamepads[index]) {
            if (rumble) {
                SDL_RumbleGamepad(gamepads[index], 0, 0, 0);
            }
            SDL_CloseGamepad(gamepads[index]);
        }
    }
    free((void *)gamepads);
    SDL_free(joy_ids);
    SDL_Quit();
    return result;
}
