// DriverKit extension: virtual HID gamepad device (C++ implementation).
//
// Compiled against the DriverKit SDK (SDKROOT=driverkit).
// The HID report descriptor below is a vendor-defined relay endpoint.
// Consumer-facing gamepads are published by the user-space IOHIDUserDevice backend.
//
// DriverKit uses OpenJoystickDriver's generic HID identity. Xbox compatibility is
// provided by the user-space IOHIDUserDevice backend; SDL compatibility is provided
// by an SDL mapping for the OJD GUID.

#include "OpenJoystickVirtualHIDDevice.h"

#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryMap.h>
#include <DriverKit/IOService.h>
#include <DriverKit/OSCollections.h>
#include <HIDDriverKit/IOHIDDeviceKeys.h>
#include <HIDDriverKit/IOHIDUsageTables.h>
#include <HIDDriverKit/IOUserHIDDevice.h>
#include <os/log.h>

struct OpenJoystickVirtualHIDDevice_IVars {
    uint64_t setReportCount = 0;
    uint64_t setReportFailCount = 0;
    uint64_t inputReportCount = 0;
    uint64_t lastPublishedSetReportCount = 0;
    uint64_t lastPublishedInputReportCount = 0;
};

// clang-format off

/// HID report descriptor for the daemon-to-dext relay.
///
/// Keep this device off Generic Desktop/GamePad so SDL, browsers, and games do not
/// enumerate it as a stale controller. The daemon writes the output report, then
/// setReport() republishes it through the matching input report for diagnostics and
/// consumers that subscribe to the relay.
static const uint8_t HID_REPORT_DESCRIPTOR[] = {
    0x06, 0x00, 0xFF,  // Usage Page: Vendor Defined 0xFF00
    0x09, 0x01,  // Usage: Relay
    0xA1, 0x01,  // Collection: Application
    0x15, 0x00,  // Logical Minimum: 0
    0x26, 0xFF, 0x00,  // Logical Maximum: 255
    0x75, 0x08,  // Report Size: 8
    0x95, 0x0F,  // Report Count: 15
    0x09, 0x02,  // Usage: Output report
    0x91, 0x02,  // Output: Data, Variable, Absolute
    0x09, 0x03,  // Usage: Input report
    0x81, 0x02,  // Input: Data, Variable, Absolute
    0xC0,  // End Collection
};

// clang-format on

static constexpr uint32_t HID_REPORT_DESCRIPTOR_SIZE = sizeof(HID_REPORT_DESCRIPTOR);
static constexpr uint8_t OJD_RELAY_MAGIC_0 = 0x4F;  // 'O'
static constexpr uint8_t OJD_RELAY_MAGIC_1 = 0x4A;  // 'J'
static constexpr uint32_t OJD_RELAY_HEADER_SIZE = 3;

template<typename Value>
static inline auto
    setNumberValue(OSDictionary* dict, const char* key, Value value, uint32_t bitCount) -> void {
    if (auto* number = OSNumber::withNumber(value, bitCount)) {
        OSDictionarySetValue(dict, key, number);
        number->release();
    }
}

static inline auto setStringValue(OSDictionary* dict, const char* key, const char* value) -> void {
    if (auto* string = OSString::withCString(value)) {
        OSDictionarySetValue(dict, key, string);
        string->release();
    }
}

static inline auto publishDebugState(OpenJoystickVirtualHIDDevice* self) -> void {
    auto* ivars = self->ivars;
    if (ivars == nullptr) {
        return;
    }

    // Rate-limit publishing to IORegistry: update every 25 setReport calls, or on any failure.
    const auto shouldPublish =
        (ivars->setReportCount - ivars->lastPublishedSetReportCount) >= 25
        || (ivars->inputReportCount - ivars->lastPublishedInputReportCount) >= 25;
    if (!shouldPublish) {
        return;
    }

    auto* dict = OSDictionary::withCapacity(3);
    if (dict == nullptr) {
        return;
    }

    setNumberValue(dict, "SetReportCount", ivars->setReportCount, 64);
    setNumberValue(dict, "SetReportFailCount", ivars->setReportFailCount, 64);
    setNumberValue(dict, "InputReportCount", ivars->inputReportCount, 64);

    // Publish under "DebugState" so user-space can read it via ioreg.
    if (auto* key = OSSymbol::withCString("DebugState")) {
        (void)self->setProperty(key, dict);
        key->release();
    }
    dict->release();

    ivars->lastPublishedSetReportCount = ivars->setReportCount;
    ivars->lastPublishedInputReportCount = ivars->inputReportCount;
}

auto OpenJoystickVirtualHIDDevice::init() -> bool {
    if (!super::init())
        return false;
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

auto OpenJoystickVirtualHIDDevice::newDeviceDescription() -> OSDictionary* {
    os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: newDeviceDescription called");

    auto* dict = OSDictionary::withCapacity(12);
    if (dict == nullptr) {
        return nullptr;
    }

    // Tell IOHIDDevice::start to call registerService on our behalf.
    OSDictionarySetValue(dict, "RegisterService", kOSBooleanTrue);
    OSDictionarySetValue(dict, "HIDDefaultBehavior", kOSBooleanTrue);

    // Publish an initial debug state snapshot so user-space can reliably read counters
    // even before the first report is sent.
    if (auto* dbg = OSDictionary::withCapacity(3)) {
        setNumberValue(dbg, "SetReportCount", static_cast<uint64_t>(0), 64);
        setNumberValue(dbg, "SetReportFailCount", static_cast<uint64_t>(0), 64);
        setNumberValue(dbg, "InputReportCount", static_cast<uint64_t>(0), 64);
        OSDictionarySetValue(dict, "DebugState", dbg);
        dbg->release();
    }

    // Important:
    // - SDL-based apps may enumerate DriverKit HID devices but not treat them as "real" gamepads.
    // - Our no-reboot Compatibility mode uses a user-space IOHIDUserDevice, which SDL *should*
    //   see as a normal controller.
    //
    // NOTE:
    // We intentionally present the DriverKit device as a "real" controller to SDL-based apps
    // that rely on stable HID transport semantics. This means Transport must NOT be "Virtual"
    // (SDL may filter/penalize it).
    setStringValue(dict, kIOHIDTransportKey, "USB");
    // Must match VirtualDeviceProfile.openJoystickDriver in the Swift layer.
    setNumberValue(dict, kIOHIDVendorIDKey, static_cast<uint32_t>(0x4F4A), 32);
    setNumberValue(dict, kIOHIDProductIDKey, static_cast<uint32_t>(0x4447), 32);
    // Some consumers treat LocationID=0 as "not a real device". Use a stable non-zero value.
    // Keep this value stable to avoid confusing HID consumers that cache devices by LocationID.
    setNumberValue(dict, kIOHIDLocationIDKey, static_cast<uint32_t>(0x4F4A4401), 32);
    // Stable (non-hardware) serial number used to disambiguate our virtual device from
    // real controllers that share VID/PID. Safe to expose to user-space.
    setStringValue(dict, kIOHIDSerialNumberKey, "OpenJoystickDriver-DriverKit");
    setStringValue(dict, kIOHIDProductKey, "OpenJoystickDriver DriverKit Relay");
    setStringValue(dict, kIOHIDManufacturerKey, "OpenJoystickDriver");
    setNumberValue(dict, kIOHIDPrimaryUsagePageKey, static_cast<uint32_t>(0xFF00), 32);
    setNumberValue(dict, kIOHIDPrimaryUsageKey, static_cast<uint32_t>(0x0001), 32);
    setNumberValue(dict, kIOHIDVersionNumberKey, static_cast<uint32_t>(0x0408), 32);
    setNumberValue(dict, kIOHIDCountryCodeKey, static_cast<uint32_t>(0), 32);

    // Explicitly publish the top-level usage pairs. IOHIDInterface usually derives this
    // from the report descriptor, but providing it here improves compatibility with some
    // user-space enumerators.
    if (auto* pairs = OSArray::withCapacity(1)) {
        if (auto* pair = OSDictionary::withCapacity(2)) {
            setNumberValue(pair, kIOHIDDeviceUsagePageKey, static_cast<uint32_t>(0xFF00), 32);
            setNumberValue(pair, kIOHIDDeviceUsageKey, static_cast<uint32_t>(0x0001), 32);
            pairs->setObject(pair);
            pair->release();
        }
        OSDictionarySetValue(dict, kIOHIDDeviceUsagePairsKey, pairs);
        pairs->release();
    }

    return dict;
}

auto OpenJoystickVirtualHIDDevice::newReportDescriptor() -> OSData* {
    os_log(
        OS_LOG_DEFAULT,
        "OpenJoystickVirtualHID: newReportDescriptor called, size=%u",
        HID_REPORT_DESCRIPTOR_SIZE);
    auto* data = OSData::withBytes(HID_REPORT_DESCRIPTOR, HID_REPORT_DESCRIPTOR_SIZE);
    if (data == nullptr) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: newReportDescriptor -- OSData::withBytes returned NULL");
    }
    return data;
}

auto OpenJoystickVirtualHIDDevice::setReport(
    IOMemoryDescriptor* report,
    IOHIDReportType reportType,
    IOOptionBits /* options */,
    uint32_t /* completionTimeout */,
    OSAction* /* action */) -> kern_return_t {
    if (reportType != kIOHIDReportTypeOutput)
        return kIOReturnUnsupported;

    if (ivars != nullptr) {
        ivars->setReportCount += 1;
    }

    // SDL (and some other consumers) will treat repeated setReport failures as a broken device
    // and ignore its input events. Our output path is a daemon → dext relay; we should accept
    // the report, translate it to an input report, and return success even if the relay fails.
    if (report == nullptr) {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: setReport called with NULL report");
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    auto len = 0U;
    const auto lenKr = report->GetLength(&len);
    if (lenKr != kIOReturnSuccess || len == 0) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport GetLength failed (kr=%d, len=%llu)",
            static_cast<int>(lenKr),
            len);
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    IOBufferMemoryDescriptor* buffer = nullptr;
    const auto bufKr = IOBufferMemoryDescriptor::Create(
        kIOMemoryDirectionIn,
        len,
        /* alignment */ 0,
        &buffer);
    if (bufKr != kIOReturnSuccess || buffer == nullptr) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport failed to allocate buffer (kr=%d, len=%llu)",
            static_cast<int>(bufKr),
            len);
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    (void)buffer->SetLength(len);

    IOMemoryMap* reportMap = nullptr;
    IOMemoryMap* bufferMap = nullptr;

    const auto mapInKr = report->CreateMapping(kIOMemoryMapReadOnly, 0, 0, len, 0, &reportMap);
    const auto mapOutKr = buffer->CreateMapping(0, 0, 0, len, 0, &bufferMap);

    if (mapInKr != kIOReturnSuccess || reportMap == nullptr || mapOutKr != kIOReturnSuccess
        || bufferMap == nullptr) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport mapping failed (inKr=%d outKr=%d)",
            static_cast<int>(mapInKr),
            static_cast<int>(mapOutKr));
        if (reportMap != nullptr)
            reportMap->release();
        if (bufferMap != nullptr)
            bufferMap->release();
        buffer->release();
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    auto* const src = reinterpret_cast<void*>(static_cast<uintptr_t>(reportMap->GetAddress()));
    auto* const dst = reinterpret_cast<void*>(static_cast<uintptr_t>(bufferMap->GetAddress()));
    if (src != nullptr && dst != nullptr) {
        memcpy(dst, src, static_cast<size_t>(len));
    } else {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: setReport map returned NULL address");
        reportMap->release();
        bufferMap->release();
        buffer->release();
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    auto targetReportID = 0U;
    auto relayLen = len;
    if (dst != nullptr && len >= OJD_RELAY_HEADER_SIZE) {
        const auto* bytes = reinterpret_cast<const uint8_t*>(dst);
        if (bytes[0] == OJD_RELAY_MAGIC_0 && bytes[1] == OJD_RELAY_MAGIC_1) {
            targetReportID = bytes[2];
            relayLen = len - OJD_RELAY_HEADER_SIZE;
            memmove(dst, bytes + OJD_RELAY_HEADER_SIZE, static_cast<size_t>(relayLen));
            (void)buffer->SetLength(relayLen);
        }
    }

    // The generic DriverKit descriptor has no report IDs. Unframed daemon reports
    // are primary gamepad payloads; framed reports can still carry the relay header
    // so the Swift side can share one path with report-ID-based descriptors.
    const auto reportLen32 = (relayLen > UINT32_MAX) ? UINT32_MAX : static_cast<uint32_t>(relayLen);
    const auto relayKr =
        handleReport(targetReportID, buffer, reportLen32, kIOHIDReportTypeInput, 0);
    if (relayKr != kIOReturnSuccess) {
        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport relay failed (kr=%d, len=%u)",
            static_cast<int>(relayKr),
            reportLen32);
        if (ivars != nullptr) {
            ivars->setReportFailCount += 1;
        }
    } else {
        if (ivars != nullptr) {
            ivars->inputReportCount += 1;
        }
    }

    reportMap->release();
    bufferMap->release();
    buffer->release();
    publishDebugState(this);
    return kIOReturnSuccess;
}
