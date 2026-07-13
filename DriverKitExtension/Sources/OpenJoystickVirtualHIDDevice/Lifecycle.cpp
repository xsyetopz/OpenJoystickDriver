// DriverKit lifecycle for the virtual HID relay device.

#include <DriverKit/IOLib.h>
#include <DriverKit/IOService.h>
#include <os/log.h>

#include "Private.h"

auto OpenJoystickVirtualHIDDevice::init() -> bool {
    if (!super::init()) {
        return false;
    }

    ivars = IONewZero(OpenJoystickVirtualHIDDevice_IVars, 1);
    if (ivars == nullptr) {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: failed to allocate ivars");
        return false;
    }
    return true;
}

auto OpenJoystickVirtualHIDDevice::free() -> void {
    IOSafeDeleteNULL(ivars, OpenJoystickVirtualHIDDevice_IVars, 1);
    super::free();
}

auto OpenJoystickVirtualHIDDevice::handleStart(IOService* provider) -> bool {
    os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: handleStart ENTRY");
    if (!super::handleStart(provider)) {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: super::handleStart failed");
        return false;
    }

    os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: handleStart succeeded");
    return true;
}
