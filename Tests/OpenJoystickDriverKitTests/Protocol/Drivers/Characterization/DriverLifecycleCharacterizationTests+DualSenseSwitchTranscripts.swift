import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Transcripts captured from the drivers; these values must not change.
extension DriverLifecycleCharacterizationTests {
  @Test
  func dualSenseUSBTranscript() throws {
    #expect(
      try transcript(Self.dualSenseUSB) == [
        "capabilities rumble=[LowFrequency,HighFrequency] binary=[]",
        "capabilities lighting=[PlayerIndicator,ProgrammableColor]",
        "capabilities triggers=[Left,Right]", "usb.startup interval=0 retries=[] packets=0",
        "usb.keepAlive nil", "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=true requests=[\"0x05/41\"]",
        "hid.featureReplies[USB] accepts=true", "  0x05 valid=true invalid=false",
        "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=true requests=[\"0x05/41\"]",
        "hid.featureReplies[Bluetooth] accepts=true", "  0x05 valid=true invalid=false",
        "hid.featureReports[Bluetooth] reports=0", "hid.featureReports[presence] reports=0",
        "hid.shutdownFeatureReports reports=0", "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=nil",
        "out[cold].hidRumble motors=[LowFrequency,HighFrequency] binary=[] minInterval=0",
        "  id=0x02 n=63",
        "    0203008040000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000",
        "out[cold].color default=0,0,255", "  plan interval=0 reports=1", "  id=0x02 n=63",
        "    0200040000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000112233000000000000000000000000000000",
        "out[cold].hidPlayer[off]", "  id=0x02 n=63",
        "    0200100000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000",
        "out[cold].hidPlayer[player1]", "  id=0x02 n=63",
        "    0200100000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000004000000000000000000000000000000000000",
        "out[cold].hidPlayer[player2]", "  id=0x02 n=63",
        "    0200100000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000a000000000000000000000000000000000000",
        "out[cold].hidPlayer[player3]", "  id=0x02 n=63",
        "    0200100000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000015000000000000000000000000000000000000",
        "out[cold].hidPlayer[player4]", "  id=0x02 n=63",
        "    0200100000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000001b000000000000000000000000000000000000",
        "out[cold].trigger[Left] resistance(0.25,0.75)", "  id=0x02 n=63",
        "    0208000000000000000000000000000000000000000001020600000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000",
        "out[cold].trigger[Right] off", "  id=0x02 n=63",
        "    0204000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  @Test
  func dualSenseBluetoothTranscript() throws {
    #expect(
      try transcript(Self.dualSenseBluetooth) == [
        "capabilities rumble=[LowFrequency,HighFrequency] binary=[]",
        "capabilities lighting=[PlayerIndicator,ProgrammableColor]",
        "capabilities triggers=[Left,Right]", "usb.startup interval=0 retries=[] packets=0",
        "usb.keepAlive nil", "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[USB] validates=true requests=[\"0x05/41\"]",
        "hid.featureReplies[USB] accepts=true", "  0x05 valid=true invalid=false",
        "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=0 required=false beforeReads=false reports=0",
        "hid.featureReads[Bluetooth] validates=true requests=[\"0x05/41\"]",
        "hid.featureReplies[Bluetooth] accepts=true", "  0x05 valid=true invalid=false",
        "hid.featureReports[Bluetooth] reports=0", "hid.featureReports[presence] reports=0",
        "hid.shutdownFeatureReports reports=0", "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[Bluetooth] supported=false beforeStartup=0 afterStartup=0",
        "hid.recovery afterExpiry=0", "presence requiresConnection=false", "liveness timeout=nil",
        "liveness observation=nil", "liveness format=nil", "battery=nil",
        "out[cold].hidRumble motors=[LowFrequency,HighFrequency] binary=[] minInterval=0",
        "  id=0x31 n=78",
        "    3100100300804000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000cbd1e087", "out[cold].color default=0,0,255",
        "  plan interval=0 reports=1", "  id=0x31 n=78",
        "    3110100004000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000001122330000000000000000000000000000",
        "    00000000000000000000da867396", "out[cold].hidPlayer[off]", "  id=0x31 n=78",
        "    3120100010000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000907d584d", "out[cold].hidPlayer[player1]", "  id=0x31 n=78",
        "    3130100010000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000040000000000000000000000000000000000",
        "    000000000000000000004d7db337", "out[cold].hidPlayer[player2]", "  id=0x31 n=78",
        "    3140100010000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000a0000000000000000000000000000000000",
        "    00000000000000000000f5526790", "out[cold].hidPlayer[player3]", "  id=0x31 n=78",
        "    3150100010000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000150000000000000000000000000000000000",
        "    00000000000000000000376ca2fe", "out[cold].hidPlayer[player4]", "  id=0x31 n=78",
        "    3160100010000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000001b0000000000000000000000000000000000",
        "    000000000000000000006a97f472", "out[cold].trigger[Left] resistance(0.25,0.75)",
        "  id=0x31 n=78", "    3170100800000000000000000000000000000000000000000102060000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000f00bfd27", "out[cold].trigger[Right] off", "  id=0x31 n=78",
        "    3180100400000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000005ddf15aa",
      ]
    )
  }

  @Test
  func switchUSBTranscript() throws {
    #expect(
      try transcript(Self.switchUSB) == [
        "capabilities rumble=[LowFrequency,HighFrequency] binary=[]",
        "capabilities lighting=[PlayerIndicator]", "capabilities triggers=[]",
        "usb.startup interval=0 retries=[] packets=0", "usb.keepAlive nil",
        "usb.deferred inputs=0 packets=0", "usb.deferred drained=0",
        "usb.connection[connected] packets=0", "usb.connection[disconnected] packets=0",
        "hid.startupOutput[USB] interval=20000000 required=false beforeReads=false reports=9",
        "  id=0x80 n=2", "    8002", "  id=0x80 n=2", "    8003", "  id=0x80 n=2", "    8002",
        "  id=0x80 n=2", "    8004", "  id=0x01 n=12", "    010000014040000140400330",
        "  id=0x01 n=12", "    010100014040000140404001", "  id=0x01 n=12",
        "    010200014040000140404801", "  id=0x01 n=16", "    01030001404000014040102060000018",
        "  id=0x01 n=16", "    01040001404000014040102680000014",
        "hid.featureReads[USB] validates=false requests=[]",
        "hid.featureReplies[USB] accepts=false", "hid.featureReports[USB] reports=0",
        "hid.startupOutput[Bluetooth] interval=60000000 required=false beforeReads=false reports=5",
        "  id=0x01 n=12", "    010000014040000140400330", "  id=0x01 n=12",
        "    010100014040000140404001", "  id=0x01 n=12", "    010200014040000140404801",
        "  id=0x01 n=16", "    01030001404000014040102060000018", "  id=0x01 n=16",
        "    01040001404000014040102680000014",
        "hid.featureReads[Bluetooth] validates=false requests=[]",
        "hid.featureReplies[Bluetooth] accepts=false", "hid.featureReports[Bluetooth] reports=0",
        "hid.featureReports[presence] reports=0", "hid.shutdownFeatureReports reports=0",
        "hid.periodic nil", "hid.statusRequest nil",
        "hid.recovery[USB] supported=true beforeStartup=0 afterStartup=2", "  id=0x01 n=16",
        "    01050001404000014040102060000018", "  id=0x01 n=16",
        "    01060001404000014040102680000014", "hid.recovery afterExpiry=0",
        "presence requiresConnection=false", "liveness timeout=nil", "liveness observation=nil",
        "liveness format=nil", "battery=nil",
        "out[cold].hidRumble motors=[LowFrequency,HighFrequency] binary=[] minInterval=50000000",
        "  id=0x10 n=10", "    100000494052008bc063", "out[cold].hidPlayer[off]", "  id=0x01 n=12",
        "    010100494052008bc0633000", "out[cold].hidPlayer[player1]", "  id=0x01 n=12",
        "    010200494052008bc0633001", "out[cold].hidPlayer[player2]", "  id=0x01 n=12",
        "    010300494052008bc0633003", "out[cold].hidPlayer[player3]", "  id=0x01 n=12",
        "    010400494052008bc0633007", "out[cold].hidPlayer[player4]", "  id=0x01 n=12",
        "    010500494052008bc063300f",
      ]
    )
  }
}
