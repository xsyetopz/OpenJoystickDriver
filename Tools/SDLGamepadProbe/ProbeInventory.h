#ifndef OJD_SDL_GAMEPAD_PROBE_INVENTORY_H
#define OJD_SDL_GAMEPAD_PROBE_INVENTORY_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

void OJDProbePrewarmGameController(void);
SDL_JoystickID* OJDProbeWaitForJoysticks(int wait_seconds, int* joy_count);
void OJDProbePrintJoystick(SDL_JoystickID id);
int OJDProbeCheckSingleNeutralOJD(SDL_JoystickID* joy_ids, int joy_count);

#ifdef __cplusplus
}
#endif

#endif
