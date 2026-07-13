#pragma once

#include <stdint.h>

#include "OpenJoystickVirtualHIDDevice.h"

struct OpenJoystickVirtualHIDDevice_IVars {
    uint64_t setReportCount = 0;
    uint64_t setReportFailCount = 0;
    uint64_t inputReportCount = 0;
    uint64_t lastPublishedSetReportCount = 0;
    uint64_t lastPublishedInputReportCount = 0;
};
