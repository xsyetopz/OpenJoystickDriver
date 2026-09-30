import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Transcripts captured from the current drivers; later slices must not change these values.
extension DriverLifecycleCharacterizationTests {
  @Test
  func gipUSBTranscript() throws {
    #expect(
      try transcript(Self.gipUSB) == [
        "capabilities rumble=[leftMain,leftTrigger,rightMain,rightTrigger] binary=[]",
        "capabilities lighting=[]", "capabilities triggers=[]",
        "usb.startup interval=50000000 retries=[1000000000, 2000000000] packets=3", "  n=5",
        "    0520000100", "  n=7", "    0a200003000114", "  n=6", "    062000020100",
        "usb.keepAlive interval=4000000000", "  ep=0x01 timeout=2000 n=7", "    03200003000000",
        "usb.deferred inputs=1 packets=4", "  n=13", "    012001090002201c0000000000", "  n=5",
        "    0520000100", "  n=7", "    0a200003000114", "  n=6", "    062000020100",
        "usb.deferred drained=0", "usb.connection[connected] packets=0",
        "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.startupOutput[BLE] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[BLE] validates=false requests=[]",
        "hid.featureReplies[BLE] accepts=false", "hid.featureReports[BLE] reports=0",
        "hid.startupOutput[nil] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[nil] validates=false requests=[]",
        "hid.featureReplies[nil] accepts=false", "hid.featureReports[nil] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false",
        "presence input#0 change=nil", "liveness timeout=nil", "liveness observation=nil",
        "liveness format=nil", "battery=nil",
        "out[cold].usbRumble motors=[leftMain,rightMain,leftTrigger,rightTrigger]",
        "  ep=0x01 timeout=2000 n=13", "    09000009000f20104080ff00ff",
      ]
    )
  }

  @Test
  func gipKeepAliveDisabledTranscript() throws {
    #expect(
      try transcript(Self.gipKeepAliveDisabled) == [
        "capabilities rumble=[leftMain,leftTrigger,rightMain,rightTrigger] binary=[]",
        "capabilities lighting=[]", "capabilities triggers=[]",
        "usb.startup interval=50000000 retries=[1000000000, 2000000000] packets=3", "  n=5",
        "    0520000100", "  n=7", "    0a200003000114", "  n=6", "    062000020100",
        "usb.keepAlive nil", "usb.deferred inputs=1 packets=4", "  n=13",
        "    012001090002201c0000000000", "  n=5", "    0520000100", "  n=7", "    0a200003000114",
        "  n=6", "    062000020100", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.startupOutput[BLE] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[BLE] validates=false requests=[]",
        "hid.featureReplies[BLE] accepts=false", "hid.featureReports[BLE] reports=0",
        "hid.startupOutput[nil] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[nil] validates=false requests=[]",
        "hid.featureReplies[nil] accepts=false", "hid.featureReports[nil] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false",
        "presence input#0 change=nil", "liveness timeout=nil", "liveness observation=nil",
        "liveness format=nil", "battery=nil",
        "out[cold].usbRumble motors=[leftMain,rightMain,leftTrigger,rightTrigger]",
        "  ep=0x07 timeout=2000 n=13", "    09000009000f20104080ff00ff",
      ]
    )
  }

  @Test
  func xidGamepadTranscript() throws {
    #expect(
      try transcript(Self.xidGamepad) == [
        "capabilities rumble=[leftMain,rightMain] binary=[]", "capabilities lighting=[]",
        "capabilities triggers=[]", "usb.startup interval=0 retries=[] packets=0",
        "usb.keepAlive nil", "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.startupOutput[BLE] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[BLE] validates=false requests=[]",
        "hid.featureReplies[BLE] accepts=false", "hid.featureReports[BLE] reports=0",
        "hid.startupOutput[nil] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[nil] validates=false requests=[]",
        "hid.featureReplies[nil] accepts=false", "hid.featureReports[nil] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=nil",
        "out[cold].usbRumble motors=[leftMain,rightMain]", "  ep=0x02 timeout=2000 n=6",
        "    000640408080",
      ]
    )
  }

  @Test
  func xusbWiredTranscript() throws {
    #expect(
      try transcript(Self.xusbWired) == [
        "capabilities rumble=[leftMain,rightMain] binary=[]",
        "capabilities lighting=[playerIndicator]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=0", "usb.startup playerSlot",
        "usb.keepAlive nil", "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.startupOutput[BLE] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[BLE] validates=false requests=[]",
        "hid.featureReplies[BLE] accepts=false", "hid.featureReports[BLE] reports=0",
        "hid.startupOutput[nil] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[nil] validates=false requests=[]",
        "hid.featureReplies[nil] accepts=false", "hid.featureReports[nil] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=nil",
        "out[cold].usbRumble motors=[leftMain,rightMain]", "  ep=0x01 timeout=2000 n=8",
        "    0008004080000000", "out[cold].usbPlayer[off]", "  ep=0x01 timeout=2000 n=3",
        "    010300", "out[cold].usbPlayer[player1]", "  ep=0x01 timeout=2000 n=3", "    010306",
        "out[cold].usbPlayer[player2]", "  ep=0x01 timeout=2000 n=3", "    010307",
        "out[cold].usbPlayer[player3]", "  ep=0x01 timeout=2000 n=3", "    010308",
        "out[cold].usbPlayer[player4]", "  ep=0x01 timeout=2000 n=3", "    010309",
      ]
    )
  }

  @Test
  func xusbReceiverTranscript() throws {
    #expect(
      try transcript(Self.xusbReceiver) == [
        "capabilities rumble=[leftMain,rightMain] binary=[]",
        "capabilities lighting=[playerIndicator]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=1", "  n=12", "    08000fc00000000000000000",
        "usb.keepAlive nil", "usb.deferred inputs=3 packets=1", "  n=12",
        "    08000fc00000000000000000", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection playerSlot",
        "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.startupOutput[BLE] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[BLE] validates=false requests=[]",
        "hid.featureReplies[BLE] accepts=false", "hid.featureReports[BLE] reports=0",
        "hid.startupOutput[nil] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[nil] validates=false requests=[]",
        "hid.featureReplies[nil] accepts=false", "hid.featureReports[nil] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=true",
        "presence input#0 change=nil", "presence input#1 change=connected",
        "presence input#2 change=disconnected", "liveness timeout=nil", "liveness observation=nil",
        "liveness format=nil", "battery=nil", "out[cold].usbRumble motors=[leftMain,rightMain]",
        "  ep=0x01 timeout=2000 n=12", "    00010fc00040800000000000", "out[cold].usbPlayer[off]",
        "  ep=0x01 timeout=2000 n=12", "    000008400000000000000000",
        "out[cold].usbPlayer[player1]", "  ep=0x01 timeout=2000 n=12",
        "    000008460000000000000000", "out[cold].usbPlayer[player2]",
        "  ep=0x01 timeout=2000 n=12", "    000008470000000000000000",
        "out[cold].usbPlayer[player3]", "  ep=0x01 timeout=2000 n=12",
        "    000008480000000000000000", "out[cold].usbPlayer[player4]",
        "  ep=0x01 timeout=2000 n=12", "    000008490000000000000000",
      ]
    )
  }
}
