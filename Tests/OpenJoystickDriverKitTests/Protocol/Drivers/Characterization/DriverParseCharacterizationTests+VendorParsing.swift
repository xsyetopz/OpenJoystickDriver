import Testing

@testable import OpenJoystickDriverKit

// Pinned parse transcripts; the rendering rules are on `DriverParseCharacterizationTests`.
extension DriverParseCharacterizationTests {
  /// Flydigi 0x01 reports.
  @Test
  func flydigi() throws {
    let lines = try transcript(Subjects.flydigi, Self.flydigiSteps)
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.4 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.5 [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.6 [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.7 [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.0 [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.1 [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.2 [left-trigger-button] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.3 [right-trigger-button] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.4 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.5 [menu] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.6 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.7 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.1 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.4 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.5 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.6 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.7 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.1 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.4 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.5 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.6 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.7 [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=north ls=0,0 rs=0,0 lt=0 rt=0", "h2 [] hat=northEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=east ls=0,0 rs=0,0 lt=0 rt=0", "h4 [] hat=southEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h5 [] hat=south ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=southWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h7 [] hat=west ls=0,0 rs=0,0 lt=0 rt=0", "h8 [] hat=northWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h9 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s1=80 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s1=81 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s1=ff [] hat=neutral ls=-258,0 rs=0,0 lt=0 rt=0",
        "s1=7f [] hat=neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s1=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s2=80 [] hat=neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s2=81 [] hat=neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s2=ff [] hat=neutral ls=0,-258 rs=0,0 lt=0 rt=0",
        "s2=7f [] hat=neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s2=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s3=80 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s3=81 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s3=ff [] hat=neutral ls=0,0 rs=-258,0 lt=0 rt=0",
        "s3=7f [] hat=neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s3=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s4=80 [] hat=neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s4=81 [] hat=neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s4=ff [] hat=neutral ls=0,0 rs=0,-258 lt=0 rt=0",
        "s4=7f [] hat=neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s4=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t13=80 [] hat=neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t13=ff [] hat=neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t13=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t14=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t14=ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t14=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "repeat [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// GameSir wired XUSB reports and 0x10 telemetry.
  @Test
  func gameSirUSB() throws {
    let lines = try transcript(Subjects.gameSirUSB, Self.gameSirUSBSteps)
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.4 [menu] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.5 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.6 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.7 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.0 [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.1 [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.2 [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.4 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.5 [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.6 [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.7 [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=north ls=0,0 rs=0,0 lt=0 rt=0", "h9 [] hat=northEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h8 [] hat=east ls=0,0 rs=0,0 lt=0 rt=0", "ha [] hat=southEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h2 [] hat=south ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=southWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h4 [] hat=west ls=0,0 rs=0,0 lt=0 rt=0", "h5 [] hat=northWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t4=80 [] hat=neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t4=ff [] hat=neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t4=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t5=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t5=ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t5=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s6=8000 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s6=8001 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s6=7fff [] hat=neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s6=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s8=8000 [] hat=neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s8=8001 [] hat=neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s8=7fff [] hat=neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s8=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s10=8000 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s10=8001 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s10=7fff [] hat=neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s10=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s12=8000 [] hat=neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s12=8001 [] hat=neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s12=7fff [] hat=neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s12=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "xusb-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "telemetry [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 73% discharging wired-power=unknown",
        "b60.0 [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.1 [share] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.3 [paddle-left-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.4 [paddle-right-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.5 [auxiliary-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.6 [paddle-left-2] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.7 [paddle-right-2] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "charging [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 100% charging wired-power=yes", "short [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// GameSir enhanced-HID 0x12 reports, advancing the motion counter except on the repeat.
  @Test
  func gameSirEnhancedHID() throws {
    let lines = try transcript(Subjects.gameSirEnhancedHID, Self.gameSirEnhancedSteps)
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 84% discharging wired-power=unknown",
        "b5.4 [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b5.5 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b5.6 [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b5.7 [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.0 [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.1 [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.4 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.5 [menu] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.6 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.7 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.0 [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.1 [share] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.3 [paddle-left-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.4 [paddle-right-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.5 [auxiliary-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.6 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.7 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=north ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=northEast ls=0,0 rs=0,0 lt=0 rt=0", "h2 [] hat=east ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=southEast ls=0,0 rs=0,0 lt=0 rt=0", "h4 [] hat=south ls=0,0 rs=0,0 lt=0 rt=0",
        "h5 [] hat=southWest ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=west ls=0,0 rs=0,0 lt=0 rt=0",
        "h7 [] hat=northWest ls=0,0 rs=0,0 lt=0 rt=0", "hf [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h8 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s1=0 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s1=7f [] hat=neutral ls=-255,0 rs=0,0 lt=0 rt=0",
        "s1=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s1=81 [] hat=neutral ls=258,0 rs=0,0 lt=0 rt=0",
        "s1=ff [] hat=neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s2=0 [] hat=neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s2=7f [] hat=neutral ls=0,255 rs=0,0 lt=0 rt=0",
        "s2=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s2=81 [] hat=neutral ls=0,-258 rs=0,0 lt=0 rt=0",
        "s2=ff [] hat=neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s3=0 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s3=7f [] hat=neutral ls=0,0 rs=-255,0 lt=0 rt=0",
        "s3=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s3=81 [] hat=neutral ls=0,0 rs=258,0 lt=0 rt=0",
        "s3=ff [] hat=neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s4=0 [] hat=neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s4=7f [] hat=neutral ls=0,0 rs=0,255 lt=0 rt=0",
        "s4=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s4=81 [] hat=neutral ls=0,0 rs=0,-258 lt=0 rt=0",
        "s4=ff [] hat=neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "t8=80 [] hat=neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t8=ff [] hat=neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t8=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t9=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t9=ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t9=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "charge=1 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "  battery 84% charging wired-power=yes",
        "repeat [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// The inner-grip enhanced-HID model maps extras 0x40 and 0x80.
  @Test
  func gameSirEnhancedHIDInnerGrips() throws {
    let lines = try transcript(
      Subjects.gameSirEnhancedHID8K,
      Self.gameSirEnhancedSteps.filter { $0.label == "neutral" || $0.label.hasPrefix("b60") }
    )
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 84% discharging wired-power=unknown",
        "b60.0 [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.1 [share] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.3 [paddle-left-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.4 [paddle-right-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.5 [auxiliary-1] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.6 [paddle-left-2] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.7 [paddle-right-2] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }
}
