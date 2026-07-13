// Output-to-input relay and diagnostic counters for the virtual HID device.

#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IOMemoryMap.h>
#include <DriverKit/OSCollections.h>
#include <HIDDriverKit/IOUserHIDDevice.h>
#include <os/log.h>

#include "Private.h"

namespace {

    constexpr uint8_t kRelayMagic0 = 0x4F;  // O
    constexpr uint8_t kRelayMagic1 = 0x4A;  // J
    constexpr uint64_t kRelayHeaderSize = 3;
    constexpr uint64_t kDebugPublishInterval = 25;

    struct PreparedReport {
        IOBufferMemoryDescriptor* buffer = nullptr;
        IOMemoryMap* sourceMap = nullptr;
        IOMemoryMap* destinationMap = nullptr;
        uint32_t reportID = 0;
        uint64_t length = 0;

        ~PreparedReport() {
            if (sourceMap != nullptr) {
                sourceMap->release();
            }
            if (destinationMap != nullptr) {
                destinationMap->release();
            }
            if (buffer != nullptr) {
                buffer->release();
            }
        }
    };

    auto setCounter(OSDictionary* state, const char* key, uint64_t value) {
        auto* number = OSNumber::withNumber(value, 64);
        if (number == nullptr) {
            return;
        }
        OSDictionarySetValue(state, key, number);
        number->release();
    }

    auto shouldPublishDebugState(const OpenJoystickVirtualHIDDevice_IVars& state) -> bool {
        return (state.setReportCount - state.lastPublishedSetReportCount) >= kDebugPublishInterval
               || (state.inputReportCount - state.lastPublishedInputReportCount)
                      >= kDebugPublishInterval;
    }

    auto makeDebugState(const OpenJoystickVirtualHIDDevice_IVars& counters) -> OSDictionary* {
        auto* state = OSDictionary::withCapacity(3);
        if (state != nullptr) {
            setCounter(state, "SetReportCount", counters.setReportCount);
            setCounter(state, "SetReportFailCount", counters.setReportFailCount);
            setCounter(state, "InputReportCount", counters.inputReportCount);
        }
        return state;
    }

    auto publishDebugState(OpenJoystickVirtualHIDDevice* device) {
        auto* counters = device->ivars;
        if (counters == nullptr || !shouldPublishDebugState(*counters)) {
            return;
        }

        auto* state = makeDebugState(*counters);
        if (state == nullptr) {
            return;
        }

        auto* key = OSSymbol::withCString("DebugState");
        if (key != nullptr) {
            (void)device->setProperty(key, state);
            key->release();
        }
        state->release();

        counters->lastPublishedSetReportCount = counters->setReportCount;
        counters->lastPublishedInputReportCount = counters->inputReportCount;
    }

    auto recordRelayFailure(OpenJoystickVirtualHIDDevice* device) {
        if (device->ivars != nullptr) {
            device->ivars->setReportFailCount += 1;
        }
        publishDebugState(device);
    }

    auto readReportLength(IOMemoryDescriptor* report, uint64_t* length) -> bool {
        const auto result = report->GetLength(length);
        if (result == kIOReturnSuccess && *length > 0) {
            return true;
        }

        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport GetLength failed (kr=%d, len=%llu)",
            static_cast<int>(result),
            *length);
        return false;
    }

    auto allocateRelayBuffer(uint64_t length, PreparedReport* prepared) -> bool {
        const auto result =
            IOBufferMemoryDescriptor::Create(kIOMemoryDirectionIn, length, 0, &prepared->buffer);
        if (result != kIOReturnSuccess || prepared->buffer == nullptr) {
            os_log(
                OS_LOG_DEFAULT,
                "OpenJoystickVirtualHID: setReport failed to allocate buffer (kr=%d, len=%llu)",
                static_cast<int>(result),
                length);
            return false;
        }

        (void)prepared->buffer->SetLength(length);
        prepared->length = length;
        return true;
    }

    auto mapReport(IOMemoryDescriptor* report, uint64_t length, PreparedReport* prepared) -> bool {
        const auto sourceResult =
            report->CreateMapping(kIOMemoryMapReadOnly, 0, 0, length, 0, &prepared->sourceMap);
        const auto destinationResult =
            prepared->buffer->CreateMapping(0, 0, 0, length, 0, &prepared->destinationMap);
        if (sourceResult == kIOReturnSuccess && prepared->sourceMap != nullptr
            && destinationResult == kIOReturnSuccess && prepared->destinationMap != nullptr) {
            return true;
        }

        os_log(
            OS_LOG_DEFAULT,
            "OpenJoystickVirtualHID: setReport mapping failed (inKr=%d outKr=%d)",
            static_cast<int>(sourceResult),
            static_cast<int>(destinationResult));
        return false;
    }

    auto copyReportData(PreparedReport* prepared) -> bool {
        const auto sourceAddress = prepared->sourceMap->GetAddress();
        const auto destinationAddress = prepared->destinationMap->GetAddress();
        if (sourceAddress == 0 || destinationAddress == 0) {
            os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: setReport map returned NULL address");
            return false;
        }

        auto* source = reinterpret_cast<const void*>(static_cast<uintptr_t>(sourceAddress));
        auto* destination = reinterpret_cast<void*>(static_cast<uintptr_t>(destinationAddress));
        memcpy(destination, source, static_cast<size_t>(prepared->length));
        return true;
    }

    auto removeRelayHeader(PreparedReport* prepared) {
        if (prepared->length < kRelayHeaderSize) {
            return;
        }

        auto* bytes = reinterpret_cast<uint8_t*>(
            static_cast<uintptr_t>(prepared->destinationMap->GetAddress()));
        if (bytes[0] != kRelayMagic0 || bytes[1] != kRelayMagic1) {
            return;
        }

        prepared->reportID = bytes[2];
        prepared->length -= kRelayHeaderSize;
        memmove(bytes, bytes + kRelayHeaderSize, static_cast<size_t>(prepared->length));
        (void)prepared->buffer->SetLength(prepared->length);
    }

    auto prepareReport(IOMemoryDescriptor* report, uint64_t length, PreparedReport* prepared)
        -> bool {
        if (!allocateRelayBuffer(length, prepared) || !mapReport(report, length, prepared)
            || !copyReportData(prepared)) {
            return false;
        }

        removeRelayHeader(prepared);
        return true;
    }

    auto relayReport(OpenJoystickVirtualHIDDevice* device, PreparedReport* prepared) {
        const auto length =
            prepared->length > UINT32_MAX ? UINT32_MAX : static_cast<uint32_t>(prepared->length);
        const auto result = device->handleReport(
            prepared->reportID,
            prepared->buffer,
            length,
            kIOHIDReportTypeInput,
            0);
        if (result != kIOReturnSuccess) {
            os_log(
                OS_LOG_DEFAULT,
                "OpenJoystickVirtualHID: setReport relay failed (kr=%d, len=%u)",
                static_cast<int>(result),
                length);
            recordRelayFailure(device);
            return;
        }

        if (device->ivars != nullptr) {
            device->ivars->inputReportCount += 1;
        }
        publishDebugState(device);
    }

}  // namespace

auto OpenJoystickVirtualHIDDevice::setReport(
    IOMemoryDescriptor* report,
    IOHIDReportType reportType,
    IOOptionBits /* options */,
    uint32_t /* completionTimeout */,
    OSAction* /* action */) -> kern_return_t {
    if (reportType != kIOHIDReportTypeOutput) {
        return kIOReturnUnsupported;
    }
    if (ivars != nullptr) {
        ivars->setReportCount += 1;
    }
    if (report == nullptr) {
        os_log(OS_LOG_DEFAULT, "OpenJoystickVirtualHID: setReport called with NULL report");
        publishDebugState(this);
        return kIOReturnSuccess;
    }

    uint64_t length = 0;
    if (!readReportLength(report, &length)) {
        recordRelayFailure(this);
        return kIOReturnSuccess;
    }

    PreparedReport prepared;
    if (!prepareReport(report, length, &prepared)) {
        recordRelayFailure(this);
        return kIOReturnSuccess;
    }

    relayReport(this, &prepared);
    return kIOReturnSuccess;
}
