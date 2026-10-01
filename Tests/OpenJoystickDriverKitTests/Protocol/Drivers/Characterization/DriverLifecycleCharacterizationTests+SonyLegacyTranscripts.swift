import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Transcripts captured from the current drivers; later slices must not change these values.
extension DriverLifecycleCharacterizationTests {
  @Test
  func sixaxisUSBTranscript() throws {
    #expect(
      try transcript(Self.sixaxisUSB) == [
        "capabilities rumble=[leftMain,rightMain] binary=[rightMain]",
        "capabilities lighting=[playerIndicator]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=0", "usb.keepAlive nil",
        "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[\"0xf2/17\", \"0xf5/8\"]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.featureReports[presence] reports=0",
        "hid.shutdownFeatureReports reports=0", "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=nil",
        "out[cold].hidRumble motors=[leftMain,rightMain] binary=[rightMain] minInterval=0",
        "  id=0x01 n=49", "    0101ff01ff400000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[off]", "  id=0x01 n=49",
        "    0101ff01ff400000000020ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player1]", "  id=0x01 n=49",
        "    0101ff01ff400000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player2]", "  id=0x01 n=49",
        "    0101ff01ff400000000004ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player3]", "  id=0x01 n=49",
        "    0101ff01ff400000000008ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player4]", "  id=0x01 n=49",
        "    0101ff01ff400000000010ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000",
      ]
    )
  }

  /// The Bluetooth enable report is a startup write in the Sixaxis records now;
  /// `sixaxisBluetoothStartupStepOrder` still sees it sent.
  @Test
  func sixaxisBluetoothTranscript() throws {
    #expect(
      try transcript(Self.sixaxisBluetooth) == [
        "capabilities rumble=[leftMain,rightMain] binary=[rightMain]",
        "capabilities lighting=[playerIndicator]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=0", "usb.keepAlive nil",
        "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=false requests=[\"0xf2/17\", \"0xf5/8\"]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.featureReports[presence] reports=0",
        "hid.shutdownFeatureReports reports=0", "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[Bluetooth] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=nil",
        "out[cold].hidRumble motors=[leftMain,rightMain] binary=[rightMain] minInterval=0",
        "  id=0x01 n=49", "    0101ff01ff400000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[off]", "  id=0x01 n=49",
        "    0101ff01ff400000000020ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player1]", "  id=0x01 n=49",
        "    0101ff01ff400000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player2]", "  id=0x01 n=49",
        "    0101ff01ff400000000004ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player3]", "  id=0x01 n=49",
        "    0101ff01ff400000000008ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "out[cold].hidPlayer[player4]", "  id=0x01 n=49",
        "    0101ff01ff400000000010ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000",
      ]
    )
  }

  @Test
  func dualShock4USBTranscript() throws {
    #expect(
      try transcript(Self.dualShock4USB) == [
        "capabilities rumble=[leftMain,rightMain] binary=[]",
        "capabilities lighting=[programmableColor]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=0", "usb.keepAlive nil",
        "usb.deferred inputs=2 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=true reports=0",
        "hid.featureReads[USB] validates=true requests=[\"0x02/37\"]",
        "hid.featureReplies[USB] accepts=true", "  0x02 valid=true invalid=false",
        "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=true beforeReads=true reports=1",
        "  id=0x11 n=78", "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89",
        "hid.featureReads[Bluetooth] validates=true requests=[\"0x05/41\"]",
        "hid.featureReplies[Bluetooth] accepts=true", "  0x05 valid=true invalid=false",
        "hid.featureReports[Bluetooth] reports=0", "hid.featureReports[presence] reports=0",
        "hid.shutdownFeatureReports reports=0", "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false",
        "presence input#0 change=nil", "presence input#1 change=nil", "liveness timeout=1000000000",
        "liveness observation=fresh=true", "liveness format=ds4-usb-0x01",
        "battery=0-9% discharging wired-power=no",
        "out[cold].hidRumble motors=[leftMain,rightMain] binary=[] minInterval=0", "  id=0x05 n=32",
        "    0501000080400000000000000000000000000000000000000000000000000000",
        "out[cold].color default=0,0,64", "  plan interval=0 reports=1", "  id=0x05 n=32",
        "    0502000000001122330000000000000000000000000000000000000000000000",
      ]
    )
  }

  @Test
  func dualShock4BluetoothTranscript() throws {
    #expect(
      try transcript(Self.dualShock4Bluetooth) == [
        "capabilities rumble=[leftMain,rightMain] binary=[]",
        "capabilities lighting=[programmableColor]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=0", "usb.keepAlive nil",
        "usb.deferred inputs=2 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=true reports=0",
        "hid.featureReads[USB] validates=true requests=[\"0x02/37\"]",
        "hid.featureReplies[USB] accepts=true", "  0x02 valid=true invalid=false",
        "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=true beforeReads=true reports=1",
        "  id=0x11 n=78", "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89",
        "hid.featureReads[Bluetooth] validates=true requests=[\"0x05/41\"]",
        "hid.featureReplies[Bluetooth] accepts=true", "  0x05 valid=true invalid=false",
        "hid.featureReports[Bluetooth] reports=0", "hid.featureReports[presence] reports=0",
        "hid.shutdownFeatureReports reports=0", "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[Bluetooth] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false",
        "presence input#0 change=nil", "presence input#1 change=nil", "liveness timeout=1000000000",
        "liveness observation=fresh=true", "liveness format=ds4-usb-0x01",
        "battery=0-9% discharging wired-power=no",
        "out[cold].hidRumble motors=[leftMain,rightMain] binary=[] minInterval=0", "  id=0x11 n=78",
        "    11c4000100008040000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000ecd24046", "out[cold].color default=0,0,64",
        "  plan interval=0 reports=1", "  id=0x11 n=78",
        "    11c4000200000000112233000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000684aea1e",
      ]
    )
  }
}
