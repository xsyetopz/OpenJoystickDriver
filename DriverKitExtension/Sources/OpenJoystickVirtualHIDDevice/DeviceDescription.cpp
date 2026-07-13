// HID identity and report descriptor for the virtual relay device.

#include <DriverKit/OSCollections.h>
#include <HIDDriverKit/IOHIDDeviceKeys.h>
#include <os/log.h>

#include "OpenJoystickVirtualHIDDevice.h"

namespace {

    // Keep the relay off Generic Desktop/GamePad. Consumer-facing gamepads are
    // published by the user-space IOHIDUserDevice backend.
    constexpr uint8_t kHIDReportDescriptor[] = {
        0x06, 0x00, 0xFF,  // Usage Page: Vendor Defined 0xFF00
        0x09, 0x01,        // Usage: Relay
        0xA1, 0x01,        // Collection: Application
        0x15, 0x00,        // Logical Minimum: 0
        0x26, 0xFF, 0x00,  // Logical Maximum: 255
        0x75, 0x08,        // Report Size: 8
        0x95, 0x0F,        // Report Count: 15
        0x09, 0x02,        // Usage: Output report
        0x91, 0x02,        // Output: Data, Variable, Absolute
        0x09, 0x03,        // Usage: Input report
        0x81, 0x02,        // Input: Data, Variable, Absolute
        0xC0,              // End Collection
    };

    auto setNumber(OSDictionary* dictionary, const char* key, uint32_t value) {
        auto* number = OSNumber::withNumber(value, 32);
        if (number == nullptr) {
            return;
        }
        OSDictionarySetValue(dictionary, key, number);
        number->release();
    }

    auto setCounter(OSDictionary* dictionary, const char* key, uint64_t value) {
        auto* number = OSNumber::withNumber(value, 64);
        if (number == nullptr) {
            return;
        }
        OSDictionarySetValue(dictionary, key, number);
        number->release();
    }

    auto setString(OSDictionary* dictionary, const char* key, const char* value) {
        auto* string = OSString::withCString(value);
        if (string == nullptr) {
            return;
        }
        OSDictionarySetValue(dictionary, key, string);
        string->release();
    }

    auto makeDebugState() -> OSDictionary* {
        auto* state = OSDictionary::withCapacity(3);
        if (state != nullptr) {
            setCounter(state, "SetReportCount", 0);
            setCounter(state, "SetReportFailCount", 0);
            setCounter(state, "InputReportCount", 0);
        }
        return state;
    }

    auto addServiceProperties(OSDictionary* description) {
        OSDictionarySetValue(description, "RegisterService", kOSBooleanTrue);
        OSDictionarySetValue(description, "HIDDefaultBehavior", kOSBooleanTrue);

        auto* debugState = makeDebugState();
        if (debugState != nullptr) {
            OSDictionarySetValue(description, "DebugState", debugState);
            debugState->release();
        }
    }

    auto addIdentityProperties(OSDictionary* description) {
        setString(description, kIOHIDTransportKey, "USB");
        setNumber(description, kIOHIDVendorIDKey, 0x4F4A);
        setNumber(description, kIOHIDProductIDKey, 0x4447);
        setNumber(description, kIOHIDLocationIDKey, 0x4F4A4401);
        setString(description, kIOHIDSerialNumberKey, "OpenJoystickDriver-DriverKit");
        setString(description, kIOHIDProductKey, "OpenJoystickDriver DriverKit Relay");
        setString(description, kIOHIDManufacturerKey, "OpenJoystickDriver");
        setNumber(description, kIOHIDVersionNumberKey, 0x0408);
        setNumber(description, kIOHIDCountryCodeKey, 0);
    }

    auto makeUsagePair() -> OSDictionary* {
        auto* pair = OSDictionary::withCapacity(2);
        if (pair != nullptr) {
            setNumber(pair, kIOHIDDeviceUsagePageKey, 0xFF00);
            setNumber(pair, kIOHIDDeviceUsageKey, 0x0001);
        }
        return pair;
    }

    auto addUsageProperties(OSDictionary* description) {
        setNumber(description, kIOHIDPrimaryUsagePageKey, 0xFF00);
        setNumber(description, kIOHIDPrimaryUsageKey, 0x0001);

        auto* pairs = OSArray::withCapacity(1);
        auto* pair = makeUsagePair();
        if (pairs != nullptr) {
            if (pair != nullptr) {
                pairs->setObject(pair);
            }
            OSDictionarySetValue(description, kIOHIDDeviceUsagePairsKey, pairs);
        }
        if (pair != nullptr) {
            pair->release();
        }
        if (pairs != nullptr) {
            pairs->release();
        }
    }

}  // namespace

auto OpenJoystickVirtualHIDDevice::newDeviceDescription() -> OSDictionary* {
    os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: newDeviceDescription called");
    auto* description = OSDictionary::withCapacity(12);
    if (description == nullptr) {
        return nullptr;
    }

    addServiceProperties(description);
    addIdentityProperties(description);
    addUsageProperties(description);
    return description;
}

auto OpenJoystickVirtualHIDDevice::newReportDescriptor() -> OSData* {
    constexpr uint32_t descriptorSize = sizeof(kHIDReportDescriptor);
    os_log(
        OS_LOG_DEFAULT,
        "OpenJoystickVirtualHID: newReportDescriptor called, size=%u",
        descriptorSize);

    auto* descriptor = OSData::withBytes(kHIDReportDescriptor, descriptorSize);
    if (descriptor == nullptr) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: newReportDescriptor — OSData::withBytes returned NULL");
    }
    return descriptor;
}
