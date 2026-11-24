// Prints what an SDL 2 library reads from each joystick: identity, then every change of its axes,
// buttons, and hats. The library is opened at run time, so the probe tests the exact SDL 2 a game
// ships, such as the one CrossOver's Wine uses, and builds without SDL 2 installed.

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// SDL 2.30.12 include/SDL.h and include/SDL_events.h.
enum {
    SdlJoyDeviceAdded = 0x605,
    SdlJoyDeviceRemoved = 0x606,
    SdlEventSize = 56,
    SdlGuidSize = 16,
};

enum {
    MaxJoysticks = 8,
    StateCapacity = 512,
    TickMilliseconds = 25,
    MillisecondsPerSecond = 1000,
    NanosecondsPerMillisecond = 1000000,
    DefaultSeconds = 10,
    MaxSeconds = 3600,
    UsageExitCode = 2,
};

// SDL_INIT_JOYSTICK, SDL_INIT_GAMECONTROLLER, and SDL_INIT_EVENTS.
static const uint32_t SDL_INIT_FLAGS = 0x200U | 0x2000U | 0x4000U;

static const char DEFAULT_LIBRARY[] =
    "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/libSDL2-2.0.0.dylib";

typedef struct {
    uint8_t data[SdlGuidSize];
} SdlGuid;

// SDL_Event: the type, a timestamp, then the device index or instance ID of a device event.
typedef union {
    struct {
        uint32_t type;
        uint32_t timestamp;
        int32_t which;
    } device;
    uint8_t padding[SdlEventSize];
} SdlEvent;

typedef struct {
    int (*init)(uint32_t);
    void (*quit)(void);
    void (*get_version)(uint8_t*);
    const char* (*get_error)(void);
    int (*poll_event)(SdlEvent*);
    void* (*open)(int);
    void (*close)(void*);
    int32_t (*instance_id)(void*);
    const char* (*name)(void*);
    uint16_t (*vendor)(void*);
    uint16_t (*product)(void*);
    SdlGuid (*guid)(void*);
    int (*is_game_controller)(int);
    int (*num_axes)(void*);
    int (*num_buttons)(void*);
    int (*num_hats)(void*);
    int16_t (*axis)(void*, int);
    uint8_t (*button)(void*, int);
    uint8_t (*hat)(void*, int);
} SDL2;

typedef struct {
    void* handle;
    int32_t instance;
    char state[StateCapacity];
} Joystick;

static bool load(void* library, const char* symbol, void* slot) {
    void* address = dlsym(library, symbol);
    if (address == NULL) {
        (void)fprintf(stderr, "missing symbol %s\n", symbol);
        return false;
    }
    memcpy(slot, (const void*)&address, sizeof address);
    return true;
}

static bool load_sdl2(void* library, SDL2* sdl) {
    const struct {
        const char* symbol;
        void* slot;
    } symbols[] = {
        {"SDL_Init", (void*)&sdl->init},
        {"SDL_Quit", (void*)&sdl->quit},
        {"SDL_GetVersion", (void*)&sdl->get_version},
        {"SDL_GetError", (void*)&sdl->get_error},
        {"SDL_PollEvent", (void*)&sdl->poll_event},
        {"SDL_JoystickOpen", (void*)&sdl->open},
        {"SDL_JoystickClose", (void*)&sdl->close},
        {"SDL_JoystickInstanceID", (void*)&sdl->instance_id},
        {"SDL_JoystickName", (void*)&sdl->name},
        {"SDL_JoystickGetVendor", (void*)&sdl->vendor},
        {"SDL_JoystickGetProduct", (void*)&sdl->product},
        {"SDL_JoystickGetGUID", (void*)&sdl->guid},
        {"SDL_IsGameController", (void*)&sdl->is_game_controller},
        {"SDL_JoystickNumAxes", (void*)&sdl->num_axes},
        {"SDL_JoystickNumButtons", (void*)&sdl->num_buttons},
        {"SDL_JoystickNumHats", (void*)&sdl->num_hats},
        {"SDL_JoystickGetAxis", (void*)&sdl->axis},
        {"SDL_JoystickGetButton", (void*)&sdl->button},
        {"SDL_JoystickGetHat", (void*)&sdl->hat},
    };
    for (size_t index = 0; index < sizeof symbols / sizeof symbols[0]; index++) {
        if (!load(library, symbols[index].symbol, symbols[index].slot)) {
            return false;
        }
    }
    return true;
}

static void print_added(const SDL2* sdl, int index, void* handle) {
    const char* name = sdl->name(handle);
    SdlGuid guid = sdl->guid(handle);
    char hex[(2 * SdlGuidSize) + 1];
    for (size_t byte = 0; byte < SdlGuidSize; byte++) {
        (void)snprintf(&hex[2 * byte], 3, "%02x", guid.data[byte]);
    }
    (void)printf(
        "ADDED id=%d %04x:%04x \"%s\" gamecontroller=%d guid=%s axes=%d buttons=%d hats=%d\n",
        sdl->instance_id(handle),
        sdl->vendor(handle),
        sdl->product(handle),
        name != NULL ? name : "",
        sdl->is_game_controller(index),
        hex,
        sdl->num_axes(handle),
        sdl->num_buttons(handle),
        sdl->num_hats(handle));
}

static void add_joystick(const SDL2* sdl, Joystick* joysticks, int index) {
    for (int slot = 0; slot < MaxJoysticks; slot++) {
        if (joysticks[slot].handle == NULL) {
            void* handle = sdl->open(index);
            if (handle == NULL) {
                (void)printf("OPEN FAILED index=%d: %s\n", index, sdl->get_error());
                return;
            }
            joysticks[slot] = (Joystick) {.handle = handle, .instance = sdl->instance_id(handle)};
            print_added(sdl, index, handle);
            return;
        }
    }
    (void)printf("SKIPPED index=%d: %d joysticks already open\n", index, MaxJoysticks);
}

static void remove_joystick(const SDL2* sdl, Joystick* joysticks, int32_t instance) {
    for (int slot = 0; slot < MaxJoysticks; slot++) {
        if (joysticks[slot].handle != NULL && joysticks[slot].instance == instance) {
            sdl->close(joysticks[slot].handle);
            joysticks[slot] = (Joystick) {0};
            (void)printf("REMOVED id=%d\n", instance);
        }
    }
}

// Writes "axes | buttons hats", such as "0 -32768 | 0100 h0", which changes when any input does.
static void describe_state(const SDL2* sdl, void* handle, char* state) {
    size_t used = 0;
    for (int index = 0; index < sdl->num_axes(handle) && used < StateCapacity; index++) {
        used +=
            (size_t)snprintf(&state[used], StateCapacity - used, "%d ", sdl->axis(handle, index));
    }
    if (used < StateCapacity) {
        used += (size_t)snprintf(&state[used], StateCapacity - used, "|");
    }
    for (int index = 0; index < sdl->num_buttons(handle) && used < StateCapacity; index++) {
        used += (size_t)snprintf(
            &state[used],
            StateCapacity - used,
            "%s%u",
            index == 0 ? " " : "",
            sdl->button(handle, index));
    }
    for (int index = 0; index < sdl->num_hats(handle) && used < StateCapacity; index++) {
        used +=
            (size_t)snprintf(&state[used], StateCapacity - used, " h%u", sdl->hat(handle, index));
    }
}

static void print_changes(const SDL2* sdl, Joystick* joysticks, double elapsed) {
    for (int slot = 0; slot < MaxJoysticks; slot++) {
        if (joysticks[slot].handle == NULL) {
            continue;
        }
        char state[StateCapacity] = {0};
        describe_state(sdl, joysticks[slot].handle, state);
        if (strcmp(state, joysticks[slot].state) != 0) {
            (void)printf("%.3f id=%d %s\n", elapsed, joysticks[slot].instance, state);
            memcpy(joysticks[slot].state, state, StateCapacity);
        }
    }
}

static void pump_events(const SDL2* sdl, Joystick* joysticks) {
    SdlEvent event;
    while (sdl->poll_event(&event) != 0) {
        if (event.device.type == SdlJoyDeviceAdded) {
            add_joystick(sdl, joysticks, event.device.which);
        } else if (event.device.type == SdlJoyDeviceRemoved) {
            remove_joystick(sdl, joysticks, event.device.which);
        }
    }
}

static void run(const SDL2* sdl, int seconds) {
    Joystick joysticks[MaxJoysticks] = {0};
    const struct timespec tick = {.tv_nsec = (long)TickMilliseconds * NanosecondsPerMillisecond};
    const int ticks = seconds * (MillisecondsPerSecond / TickMilliseconds);
    for (int count = 0; count < ticks; count++) {
        pump_events(sdl, joysticks);
        print_changes(sdl, joysticks, (double)count * TickMilliseconds / MillisecondsPerSecond);
        (void)fflush(stdout);
        (void)nanosleep(&tick, NULL);
    }
    for (int slot = 0; slot < MaxJoysticks; slot++) {
        if (joysticks[slot].handle != NULL) {
            sdl->close(joysticks[slot].handle);
        }
    }
}

static int usage(const char* program) {
    (void)fprintf(stderr, "usage: %s [--seconds 1-%d] [--library PATH]\n", program, MaxSeconds);
    return UsageExitCode;
}

int main(int argc, char** argv) {
    const char* library_path = DEFAULT_LIBRARY;
    long seconds = DefaultSeconds;
    for (int index = 1; index < argc; index += 2) {
        if (index + 1 >= argc) {
            return usage(argv[0]);
        }
        if (strcmp(argv[index], "--library") == 0) {
            library_path = argv[index + 1];
        } else if (strcmp(argv[index], "--seconds") == 0) {
            char* end = NULL;
            seconds = strtol(argv[index + 1], &end, 10);
            if (*end != '\0' || seconds < 1 || seconds > MaxSeconds) {
                return usage(argv[0]);
            }
        } else {
            return usage(argv[0]);
        }
    }

    void* library = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) {
        // The probe loads the library before it starts any thread.
        // NOLINTNEXTLINE(concurrency-mt-unsafe)
        (void)fprintf(stderr, "%s\n", dlerror());
        return EXIT_FAILURE;
    }
    SDL2 sdl;
    if (!load_sdl2(library, &sdl)) {
        return EXIT_FAILURE;
    }
    uint8_t version[3] = {0};
    sdl.get_version(version);
    (void)printf(
        "SDL %u.%u.%u from %s for %lds\n",
        version[0],
        version[1],
        version[2],
        library_path,
        seconds);
    if (sdl.init(SDL_INIT_FLAGS) != 0) {
        (void)fprintf(stderr, "SDL_Init: %s\n", sdl.get_error());
        return EXIT_FAILURE;
    }
    run(&sdl, (int)seconds);
    sdl.quit();
    return EXIT_SUCCESS;
}
