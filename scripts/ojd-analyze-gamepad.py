#!/usr/bin/env python3
"""Gamesir G7 SE / Xbox GIP raw USB packet analyzer."""

from __future__ import annotations

import struct
import sys
import time
from typing import Dict, Iterable, List, Optional, Tuple

try:
    import usb.backend.libusb1
    import usb.core
    import usb.util
except ImportError:
    usb = None  # type: ignore[assignment]

VID_GAMESIR = 0x3537
PID_G7SE = 0x1010

GIP_CMD: Dict[int, str] = {
    0x01: "ANNOUNCE",
    0x02: "STATUS",
    0x03: "KEEPALIVE",
    0x04: "RECONNECT",
    0x05: "POWER",
    0x06: "AUTHENTICATE",
    0x07: "VIRTUAL_KEY",
    0x09: "RUMBLE",
    0x0A: "LED",
    0x20: "INPUT",
}

BUTTON_BITS: Tuple[Tuple[int, int, str], ...] = (
    (0, 0x04, "Start"),
    (0, 0x08, "Back"),
    (0, 0x10, "A"),
    (0, 0x20, "B"),
    (0, 0x40, "X"),
    (0, 0x80, "Y"),
    (1, 0x01, "DUp"),
    (1, 0x02, "DDown"),
    (1, 0x04, "DLeft"),
    (1, 0x08, "DRight"),
    (1, 0x10, "LB"),
    (1, 0x20, "RB"),
    (1, 0x40, "LSB"),
    (1, 0x80, "RSB"),
)

KNOWN_VIRTUAL_KEYS = {0x5B: "Guide/Xbox"}
KEEPALIVE_INTERVAL_S = 4.0
READ_TIMEOUT_MS = 100
WRITE_TIMEOUT_MS = 1000
READ_PACKET_SIZE = 64
DEFAULT_IN_ENDPOINT = 0x82
DEFAULT_OUT_ENDPOINT = 0x02
TIMEOUT_ERRNOS = {None, 60, 110}

INVESTIGATE_PHASES: Tuple[Tuple[str, float], ...] = (
    ("BASELINE - all inputs at rest (sticks centred, no buttons)", 6.0),
    ("Press and HOLD  L4  (back left paddle)", 10.0),
    ("Release L4 - rest", 3.0),
    ("Press and HOLD  R4  (back right paddle)", 10.0),
    ("Release R4 - rest", 3.0),
    ("Press and HOLD  M   (mode button, centre back)", 10.0),
    ("Release M - rest", 3.0),
    ("Press and HOLD  Mic (microphone button, near headphone jack)", 10.0),
    ("Release Mic - rest", 3.0),
    ("REFERENCE - press  A,  LB,  Share,  Guide  (confirm known buttons appear)", 10.0),
)

class GIPSequencer:
    """Per-command sequence number counter."""

    def __init__(self):
        self._counters: Dict[int, int] = {}

    def next(self, cmd: int) -> int:
        sequence = self._counters.get(cmd, 0)
        self._counters[cmd] = (sequence + 1) & 0xFF
        return sequence

class CaptureState:
    def __init__(self):
        self.previous_input: Optional[bytes] = None
        self.command_counts: Dict[int, int] = {}
        self.total_packets = 0

    def record(self, cmd: int) -> None:
        self.command_counts[cmd] = self.command_counts.get(cmd, 0) + 1
        self.total_packets += 1

class CaptureConfig:
    def __init__(self, duration: Optional[float], diff_only: bool, label: str):
        self.duration = duration
        self.diff_only = diff_only
        self.label = label

def hex_str(data: bytes) -> str:
    return " ".join(f"{byte:02X}" for byte in data)

def diff_str(previous: bytes, current: bytes) -> str:
    parts = [
        f"[{byte:02X}]" if index >= len(previous) or previous[index] != byte else f"{byte:02X}"
        for index, byte in enumerate(current)
    ]
    return " ".join(parts)

def changed_count(previous: bytes, current: bytes) -> int:
    return sum(1 for index, byte in enumerate(current) if index >= len(previous) or previous[index] != byte)

def unpack_input_axes(payload: bytes) -> Tuple[int, int, int, int, int, int]:
    return (
        struct.unpack_from("<H", payload, 2)[0],
        struct.unpack_from("<H", payload, 4)[0],
        struct.unpack_from("<h", payload, 6)[0],
        struct.unpack_from("<h", payload, 8)[0],
        struct.unpack_from("<h", payload, 10)[0],
        struct.unpack_from("<h", payload, 12)[0],
    )

def decode_button_bits(payload: bytes) -> List[str]:
    return [name for byte_index, mask, name in BUTTON_BITS if payload[byte_index] & mask]

def decode_extended_input(payload: bytes, buttons: List[str]) -> List[str]:
    notes: List[str] = []
    if len(payload) >= 15:
        ext14 = payload[14]
        if ext14 & 0x01:
            buttons.append("Share")
        unknown14 = ext14 & 0xFE
        if unknown14:
            notes.append(f"ext[14]=0x{ext14:02X} (unknown bits!)")

    if len(payload) > 15:
        nonzero = [(index + 15, value) for index, value in enumerate(payload[15:]) if value]
        if nonzero:
            fields = " ".join(f"[{index}]=0x{value:02X}" for index, value in nonzero)
            notes.append(f"NONZERO: {fields}")
    return notes

def decode_virtual_key(payload: bytes) -> str:
    if len(payload) < 2:
        return f"(short: {payload.hex()})"
    state = "PRESSED" if payload[0] else "released"
    code = payload[1]
    name = KNOWN_VIRTUAL_KEYS.get(code, f"UNKNOWN(0x{code:02X})")
    return f"{state}  key=0x{code:02X} ({name})  raw={payload.hex()}"

def decode_input(payload: bytes) -> str:
    if len(payload) < 14:
        return f"(short payload: {len(payload)} bytes)"

    buttons = decode_button_bits(payload)
    notes = decode_extended_input(payload, buttons)
    lt, rt, lsx, lsy, rsx, rsy = unpack_input_axes(payload)
    button_text = "+".join(buttons) if buttons else "idle"
    axes_text = f"LT={lt} RT={rt} LS=({lsx},{lsy}) RS=({rsx},{rsy})"
    if not notes:
        return f"{button_text}  |  {axes_text}"
    return f"{button_text}  |  {axes_text}  |  {'  '.join(notes)}"

def get_string(dev: usb.core.Device, index: int, default: str) -> str:
    try:
        return usb.util.get_string(dev, index) or default
    except Exception:
        return default

def find_named_vendor_device(devices: Iterable[usb.core.Device]) -> Optional[usb.core.Device]:
    names = ("xbox", "gamesir", "gamepad", "controller")
    for dev in devices:
        if getattr(dev, "bDeviceClass", None) != 0xFF:
            continue
        product = get_string(dev, dev.iProduct, "").lower()
        if any(name in product for name in names):
            return dev
    return None

def find_device() -> Optional[usb.core.Device]:
    dev = usb.core.find(idVendor=VID_GAMESIR, idProduct=PID_G7SE)
    if dev:
        return dev
    return find_named_vendor_device(usb.core.find(find_all=True))

def get_endpoints(dev: usb.core.Device) -> Tuple[int, int]:
    in_ep = out_ep = None
    try:
        cfg = dev.get_active_configuration()
    except usb.core.USBError:
        return DEFAULT_IN_ENDPOINT, DEFAULT_OUT_ENDPOINT

    for intf in cfg:
        for ep in intf:
            is_interrupt = (ep.bmAttributes & 0x03) == 0x03
            if not is_interrupt:
                continue
            if ep.bEndpointAddress & 0x80 and in_ep is None:
                in_ep = ep.bEndpointAddress
            elif not ep.bEndpointAddress & 0x80 and out_ep is None:
                out_ep = ep.bEndpointAddress
    return in_ep or DEFAULT_IN_ENDPOINT, out_ep or DEFAULT_OUT_ENDPOINT

def claim_interface(dev: usb.core.Device) -> bool:
    try:
        prepare_interface(dev)
        usb.util.claim_interface(dev, 0)
        return True
    except usb.core.USBError as error:
        print(f"[ERROR] Cannot claim interface: {error}")
        if is_permission_or_busy_error(error):
            print("  → Run with sudo")
            print("  → Or stop the daemon first:")
            print("      .build/debug/OpenJoystickDriver --headless stop")
        return False

def prepare_interface(dev: usb.core.Device) -> None:
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except (usb.core.USBError, NotImplementedError):
        pass

    try:
        dev.set_configuration()
    except usb.core.USBError:
        pass

def is_permission_or_busy_error(error: usb.core.USBError) -> bool:
    text = str(error).lower()
    return "13" in text or "access denied" in text or "busy" in text

def send_init(dev: usb.core.Device, out_ep: int, seq: GIPSequencer) -> None:
    packets = (
        bytes([0x05, 0x20, seq.next(0x05), 0x01, 0x00]),
        bytes([0x0A, 0x20, seq.next(0x0A), 0x03, 0x00, 0x01, 0x14]),
        bytes([0x06, 0x20, seq.next(0x06), 0x02, 0x01, 0x00]),
    )
    print("[INIT] Sending GIP handshake...")
    for index, packet in enumerate(packets, 1):
        try:
            dev.write(out_ep, packet, timeout=WRITE_TIMEOUT_MS)
            print(f"  → ({index}/3) {hex_str(packet)}")
            time.sleep(0.05)
        except usb.core.USBError as error:
            print(f"  → ({index}/3) FAILED: {error}")

def send_keepalive(dev: usb.core.Device, out_ep: int, seq: GIPSequencer) -> bool:
    packet = bytes([0x03, 0x20, seq.next(0x03), 0x03, 0x00, 0x00, 0x00])
    try:
        dev.write(out_ep, packet, timeout=WRITE_TIMEOUT_MS)
        return True
    except usb.core.USBError:
        return False

def print_capture_header(label: str) -> None:
    if not label:
        return
    print(f"\n{'-' * 60}")
    print(f"  {label}")
    print(f"{'-' * 60}")

def read_packet(dev: usb.core.Device, in_ep: int) -> Optional[bytes]:
    try:
        return bytes(dev.read(in_ep, READ_PACKET_SIZE, timeout=READ_TIMEOUT_MS))
    except usb.core.USBError as error:
        if getattr(error, "errno", None) in TIMEOUT_ERRNOS:
            return None
        raise

def packet_payload(data: bytes) -> bytes:
    declared_len = int(data[3])
    end = 4 + declared_len
    return data[4:end] if len(data) >= end else data[4:]

def print_input_packet(elapsed: float, payload: bytes, previous: Optional[bytes]) -> None:
    if previous is not None and payload != previous:
        count = changed_count(previous, payload)
        print(f"[{elapsed:8.3f}s] INPUT  Δ{count:2d}  {diff_str(previous, payload)}")
    else:
        print(f"[{elapsed:8.3f}s] INPUT       {hex_str(payload)}")
    print(f"             ↳  {decode_input(payload)}")

def print_packet(elapsed: float, cmd: int, data: bytes, payload: bytes) -> None:
    name = GIP_CMD.get(cmd, f"0x{cmd:02X}")
    print(f"[{elapsed:8.3f}s] {name:<12} {hex_str(data)}")
    if cmd == 0x07:
        print(f"             ↳  {decode_virtual_key(payload)}")

def handle_packet(data: bytes, elapsed: float, config: CaptureConfig, state: CaptureState) -> None:
    if len(data) < 4:
        return

    cmd = data[0]
    payload = packet_payload(data)
    state.record(cmd)

    if cmd == 0x20:
        if config.diff_only and state.previous_input is not None and payload == state.previous_input:
            return
        print_input_packet(elapsed, payload, state.previous_input)
        state.previous_input = payload
        return

    print_packet(elapsed, cmd, data, payload)

def print_capture_summary(state: CaptureState, start: float) -> None:
    elapsed_total = time.time() - start
    print(f"\n  {state.total_packets} distinct packets in {elapsed_total:.1f}s")
    if not state.command_counts:
        return
    summary = "  CMDs seen: " + "  ".join(
        f"{GIP_CMD.get(cmd, f'0x{cmd:02X}')}×{count}"
        for cmd, count in sorted(state.command_counts.items())
    )
    print(summary)

def capture(
    dev: usb.core.Device,
    in_ep: int,
    out_ep: int,
    seq: GIPSequencer,
    duration: Optional[float] = None,
    diff_only: bool = True,
    label: str = "",
) -> Dict[int, int]:
    config = CaptureConfig(duration, diff_only, label)
    state = CaptureState()
    print_capture_header(config.label)
    start = last_keepalive = time.time()

    try:
        while True:
            now = time.time()
            if config.duration is not None and now - start >= config.duration:
                break
            if now - last_keepalive >= KEEPALIVE_INTERVAL_S:
                send_keepalive(dev, out_ep, seq)
                last_keepalive = time.time()

            try:
                data = read_packet(dev, in_ep)
            except usb.core.USBError as error:
                print(f"\n[ERROR] Read error: {error}")
                break
            if data is None:
                continue
            handle_packet(data, now - start, config, state)
    except KeyboardInterrupt:
        pass

    print_capture_summary(state, start)
    return state.command_counts

def investigate(dev: usb.core.Device, in_ep: int, out_ep: int, seq: GIPSequencer) -> None:
    print("\n[INVESTIGATE] Guided button investigation")
    print("Keep sticks centred and no buttons held unless instructed.\n")
    input("Press Enter to begin...")

    all_commands: Dict[int, int] = {}
    for label, duration in INVESTIGATE_PHASES:
        input(f"\n→  {label}  ({duration:.0f}s - press Enter then act)")
        counts = capture(dev, in_ep, out_ep, seq, duration=duration, diff_only=False, label=label)
        for cmd, count in counts.items():
            all_commands[cmd] = all_commands.get(cmd, 0) + count

    print_investigation_summary(all_commands)

def print_investigation_summary(command_counts: Dict[int, int]) -> None:
    print("\n" + "═" * 60)
    print("INVESTIGATION COMPLETE")
    print("═" * 60)
    print("All CMD bytes observed across all phases:")
    for cmd in sorted(command_counts):
        print(f"  0x{cmd:02X}  {GIP_CMD.get(cmd, '(unknown)'):<14}  ×{command_counts[cmd]}")
    print("\nIf L4/R4/M/Mic produced any packet, it appears above.")
    print("If no new CMDs appeared during those phases, the buttons")
    print("are handled entirely in firmware with no USB traffic.")

def print_usage() -> None:
    print(
        """Usage:
  sudo ./scripts/ojd analyze gamepad
  sudo ./scripts/ojd analyze gamepad --capture
  sudo ./scripts/ojd analyze gamepad --investigate
  sudo ./scripts/ojd analyze gamepad --capture --all

Options:
  --capture      Capture until Ctrl+C instead of the default 30s capture.
  --investigate  Guided L4/R4/M/Mic button investigation.
  --all          Print idle input packets too.
  -h, --help     Show this help.
"""
    )

def parse_mode(args: set[str]) -> str:
    if "--capture" in args:
        return "capture"
    if "--investigate" in args:
        return "investigate"
    return "default"

def require_usb() -> None:
    if usb is None:
        print("Error: pyusb not found. Install it with: python3 -m pip install pyusb")
        sys.exit(1)
    if not usb.backend.libusb1.get_backend():
        print("Error: libusb not found. Install it with: brew install libusb")
        sys.exit(1)

def print_device_info(dev: usb.core.Device) -> None:
    product = get_string(dev, dev.iProduct, "Controller")
    serial = get_string(dev, dev.iSerialNumber, "N/A")
    print(f"\n[DEVICE] {product}")
    print(f"  VID:PID = {dev.idVendor:04X}:{dev.idProduct:04X}  Serial: {serial}")
    print(f"  Class   = 0x{dev.bDeviceClass:02X}")
    print_interfaces(dev)

def print_interfaces(dev: usb.core.Device) -> None:
    try:
        cfg = dev.get_active_configuration()
        print(f"  Configuration: {cfg.bConfigurationValue}, {cfg.bNumInterfaces} interface(s)")
        for intf in cfg:
            print_interface(intf)
    except Exception as error:
        print(f"  (descriptor enumeration failed: {error})")

def print_interface(intf) -> None:
    class_name = {0x03: "HID", 0xFF: "Vendor"}.get(intf.bInterfaceClass, f"0x{intf.bInterfaceClass:02X}")
    print(
        f"    Interface {intf.bInterfaceNumber} alt={intf.bAlternateSetting}: "
        f"class={class_name} sub=0x{intf.bInterfaceSubClass:02X}"
    )
    for ep in intf:
        print_endpoint(ep)

def print_endpoint(ep) -> None:
    direction = "IN " if ep.bEndpointAddress & 0x80 else "OUT"
    transfer = {0x00: "Control", 0x01: "Isoch", 0x02: "Bulk", 0x03: "Interrupt"}.get(
        ep.bmAttributes & 0x03, "?"
    )
    print(f"      EP 0x{ep.bEndpointAddress:02X} {direction} {transfer}  maxPkt={ep.wMaxPacketSize}")

def setup_device() -> Tuple[usb.core.Device, int, int, GIPSequencer]:
    dev = find_device()
    if dev is None:
        print(f"Device {VID_GAMESIR:04X}:{PID_G7SE:04X} not found. Is the G7 SE connected?")
        sys.exit(1)

    print_device_info(dev)
    if not claim_interface(dev):
        sys.exit(1)
    print("  Interface 0 claimed")

    in_ep, out_ep = get_endpoints(dev)
    print(f"  Endpoints: IN=0x{in_ep:02X}  OUT=0x{out_ep:02X}")

    seq = GIPSequencer()
    send_init(dev, out_ep, seq)
    time.sleep(0.2)
    return dev, in_ep, out_ep, seq

def run_capture_mode(mode: str, dev: usb.core.Device, in_ep: int, out_ep: int, seq: GIPSequencer, diff_only: bool) -> None:
    if mode == "investigate":
        investigate(dev, in_ep, out_ep, seq)
        return

    if mode == "capture":
        print("\n[CAPTURE] Running until Ctrl+C.")
        duration = None
    else:
        print("\n[CAPTURE] 30s capture - press buttons to investigate.")
        duration = 30.0

    if diff_only:
        print("  Idle INPUT packets suppressed. Changed bytes in [brackets].\n")
    capture(dev, in_ep, out_ep, seq, duration=duration, diff_only=diff_only)

def main() -> None:
    args = set(sys.argv[1:])
    if args & {"-h", "--help", "help"}:
        print_usage()
        return

    require_usb()
    dev, in_ep, out_ep, seq = setup_device()
    try:
        run_capture_mode(parse_mode(args), dev, in_ep, out_ep, seq, "--all" not in args)
    finally:
        usb.util.dispose_resources(dev)

if __name__ == "__main__":
    main()
