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
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.4 [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.5 [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.6 [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b9.7 [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.0 [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.1 [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.2 [LeftTrigger] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.3 [RightTrigger] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.4 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.5 [Start] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.6 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b10.7 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.0 [Auxiliary1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.1 [Auxiliary2] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.2 [LeftPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.3 [LeftPaddle2] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.4 [RightPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.5 [RightPaddle2] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.6 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b11.7 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.1 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.2 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.4 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.5 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.6 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b12.7 [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=North ls=0,0 rs=0,0 lt=0 rt=0", "h2 [] hat=NorthEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=East ls=0,0 rs=0,0 lt=0 rt=0", "h4 [] hat=SouthEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h5 [] hat=South ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=SouthWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h7 [] hat=West ls=0,0 rs=0,0 lt=0 rt=0", "h8 [] hat=NorthWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h9 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s1=80 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s1=81 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s1=ff [] hat=Neutral ls=-258,0 rs=0,0 lt=0 rt=0",
        "s1=7f [] hat=Neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s1=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s2=80 [] hat=Neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s2=81 [] hat=Neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s2=ff [] hat=Neutral ls=0,-258 rs=0,0 lt=0 rt=0",
        "s2=7f [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s2=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s3=80 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s3=81 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s3=ff [] hat=Neutral ls=0,0 rs=-258,0 lt=0 rt=0",
        "s3=7f [] hat=Neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s3=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s4=80 [] hat=Neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s4=81 [] hat=Neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s4=ff [] hat=Neutral ls=0,0 rs=0,-258 lt=0 rt=0",
        "s4=7f [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s4=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t13=80 [] hat=Neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t13=ff [] hat=Neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t13=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t14=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t14=ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t14=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "repeat [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// GameSir wired XUSB reports and 0x10 telemetry.
  @Test
  func gameSirUSB() throws {
    let lines = try transcript(Subjects.gameSirUSB, Self.gameSirUSBSteps)
    #expect(
      lines == [
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.4 [Start] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.5 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.6 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.7 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.0 [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.1 [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.2 [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.4 [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.5 [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.6 [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.7 [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=North ls=0,0 rs=0,0 lt=0 rt=0", "h9 [] hat=NorthEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h8 [] hat=East ls=0,0 rs=0,0 lt=0 rt=0", "ha [] hat=SouthEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h2 [] hat=South ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=SouthWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h4 [] hat=West ls=0,0 rs=0,0 lt=0 rt=0", "h5 [] hat=NorthWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t4=80 [] hat=Neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t4=ff [] hat=Neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t4=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t5=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t5=ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t5=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s6=8000 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s6=8001 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s6=7fff [] hat=Neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s6=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s8=8000 [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s8=8001 [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s8=7fff [] hat=Neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s8=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s10=8000 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s10=8001 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s10=7fff [] hat=Neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s10=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s12=8000 [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s12=8001 [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s12=7fff [] hat=Neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s12=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "xusb-up [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "telemetry [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 73% Discharging wired-power=unknown",
        "b60.0 [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.1 [Capture] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.2 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.3 [LeftPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.4 [RightPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.5 [Auxiliary1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.6 [LeftPaddle2] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.7 [RightPaddle2] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "charging [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 100% Charging wired-power=yes", "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// GameSir enhanced-HID 0x12 reports, advancing the motion counter except on the repeat.
  @Test
  func gameSirEnhancedHID() throws {
    let lines = try transcript(Subjects.gameSirEnhancedHID, Self.gameSirEnhancedSteps)
    #expect(
      lines == [
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 84% Discharging wired-power=unknown",
        "b5.4 [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b5.5 [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b5.6 [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b5.7 [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.0 [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.1 [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.2 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.4 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.5 [Start] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.6 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b6.7 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.0 [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.1 [Capture] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.2 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.3 [LeftPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.4 [RightPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.5 [Auxiliary1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.6 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.7 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=North ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=NorthEast ls=0,0 rs=0,0 lt=0 rt=0", "h2 [] hat=East ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=SouthEast ls=0,0 rs=0,0 lt=0 rt=0", "h4 [] hat=South ls=0,0 rs=0,0 lt=0 rt=0",
        "h5 [] hat=SouthWest ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=West ls=0,0 rs=0,0 lt=0 rt=0",
        "h7 [] hat=NorthWest ls=0,0 rs=0,0 lt=0 rt=0", "hf [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h8 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s1=0 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s1=7f [] hat=Neutral ls=-255,0 rs=0,0 lt=0 rt=0",
        "s1=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s1=81 [] hat=Neutral ls=258,0 rs=0,0 lt=0 rt=0",
        "s1=ff [] hat=Neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s2=0 [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s2=7f [] hat=Neutral ls=0,255 rs=0,0 lt=0 rt=0",
        "s2=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s2=81 [] hat=Neutral ls=0,-258 rs=0,0 lt=0 rt=0",
        "s2=ff [] hat=Neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s3=0 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s3=7f [] hat=Neutral ls=0,0 rs=-255,0 lt=0 rt=0",
        "s3=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s3=81 [] hat=Neutral ls=0,0 rs=258,0 lt=0 rt=0",
        "s3=ff [] hat=Neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s4=0 [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s4=7f [] hat=Neutral ls=0,0 rs=0,255 lt=0 rt=0",
        "s4=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s4=81 [] hat=Neutral ls=0,0 rs=0,-258 lt=0 rt=0",
        "s4=ff [] hat=Neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "t8=80 [] hat=Neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t8=ff [] hat=Neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t8=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t9=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t9=ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t9=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "charge=1 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0", "  battery 84% Charging wired-power=yes",
        "repeat [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
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
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "  battery 84% Discharging wired-power=unknown",
        "b60.0 [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.1 [Capture] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.2 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.3 [LeftPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.4 [RightPaddle1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.5 [Auxiliary1] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.6 [LeftPaddle2] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b60.7 [RightPaddle2] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }
}
