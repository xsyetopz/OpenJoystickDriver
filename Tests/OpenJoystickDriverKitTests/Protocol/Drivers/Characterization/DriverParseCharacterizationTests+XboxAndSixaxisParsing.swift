import Testing

@testable import OpenJoystickDriverKit

// Pinned parse transcripts; the rendering rules are on `DriverParseCharacterizationTests`.
extension DriverParseCharacterizationTests {
  /// GIP input, guide, short, ack-requesting, ack, chunk and status frames.
  @Test
  func gipUSB() throws {
    let lines = try transcript(Subjects.gipUSB, Self.gipSteps)
    #expect(
      lines == [
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.1 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.2 [Start] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.3 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.4 [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.5 [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.6 [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.7 [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.4 [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.5 [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.6 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.7 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.1 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.2 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.4 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.5 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.6 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.7 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0", "h1 [] hat=North ls=0,0 rs=0,0 lt=0 rt=0",
        "h9 [] hat=NorthEast ls=0,0 rs=0,0 lt=0 rt=0", "h8 [] hat=East ls=0,0 rs=0,0 lt=0 rt=0",
        "ha [] hat=SouthEast ls=0,0 rs=0,0 lt=0 rt=0", "h2 [] hat=South ls=0,0 rs=0,0 lt=0 rt=0",
        "h6 [] hat=SouthWest ls=0,0 rs=0,0 lt=0 rt=0", "h4 [] hat=West ls=0,0 rs=0,0 lt=0 rt=0",
        "h5 [] hat=NorthWest ls=0,0 rs=0,0 lt=0 rt=0", "h3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "lt=1ff [] hat=Neutral ls=0,0 rs=0,0 lt=32735 rt=0",
        "lt=3ff [] hat=Neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "lt=400 [] hat=Neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "lt=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "rt=1ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=32735",
        "rt=3ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "rt=400 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "rt=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
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
        "repeat [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "guide [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "guide-up [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "ack-req [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "ack [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "chunk [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "status [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// A GIP frame split across two transfers is reassembled on the second.
  @Test
  func gipSplitFrame() throws {
    let lines = try transcript(Subjects.gipUSB, Self.gipSplitSteps)
    #expect(
      lines == [
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "head [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "tail [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Xbox 360 wired reports.
  @Test
  func xusbWired() throws {
    let lines = try transcript(Subjects.xusbWired, Self.xusbWiredSteps)
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
        "repeat [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "len=13 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Receiver input establishes presence; the pipeline handles disconnect neutralization.
  @Test
  func xusbReceiver() throws {
    let lines = try transcript(Subjects.xusbReceiver, Self.xusbReceiverSteps)
    #expect(
      lines == [
        "early-a [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "connect [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "a [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "lsx=max [] hat=Neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "a+up [South] hat=North ls=0,0 rs=0,0 lt=0 rt=0",
        "disconnect [South] hat=North ls=0,0 rs=0,0 lt=0 rt=0",
        "late-b [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Original Xbox XID reports; analog face and shoulder keys press at any nonzero value.
  @Test
  func xid() throws {
    let lines = try transcript(Subjects.xidGamepad, Self.xidSteps)
    #expect(
      lines == [
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.4 [Start] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.5 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.6 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.7 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=North ls=0,0 rs=0,0 lt=0 rt=0", "h9 [] hat=NorthEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h8 [] hat=East ls=0,0 rs=0,0 lt=0 rt=0", "ha [] hat=SouthEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h2 [] hat=South ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=SouthWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h4 [] hat=West ls=0,0 rs=0,0 lt=0 rt=0", "h5 [] hat=NorthWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k4=1 [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k4=ff [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k4=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k5=1 [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k5=ff [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k5=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k6=1 [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k6=ff [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k6=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k7=1 [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k7=ff [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k7=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k8=1 [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k8=ff [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k8=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k9=1 [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k9=ff [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k9=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t10=80 [] hat=Neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t10=ff [] hat=Neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t10=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t11=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t11=ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t11=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s12=8000 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s12=8001 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s12=7fff [] hat=Neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s12=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s14=8000 [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s14=8001 [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s14=7fff [] hat=Neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s14=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s16=8000 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s16=8001 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s16=7fff [] hat=Neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s16=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s18=8000 [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s18=8001 [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s18=7fff [] hat=Neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s18=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "repeat [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Sixaxis reports; a 0xFF second byte drops the report.
  @Test
  func sixaxisUSB() throws {
    let lines = try transcript(Subjects.sixaxisUSB, Self.sixaxisSteps)
    #expect(
      lines == [
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b2.0 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b2.1 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b2.2 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b2.3 [Start] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.0 [LeftTrigger] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.1 [RightTrigger] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.2 [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.3 [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.4 [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.5 [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.6 [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b3.7 [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.0 [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.1 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.2 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.3 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.4 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.5 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.6 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "b4.7 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h10 [] hat=North ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h30 [] hat=NorthEast ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h20 [] hat=East ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h60 [] hat=SouthEast ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h40 [] hat=South ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "hc0 [] hat=SouthWest ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h80 [] hat=West ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h90 [] hat=NorthWest ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h50 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "h0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "s6=0 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0 fresh",
        "s6=7f [] hat=Neutral ls=-255,0 rs=0,0 lt=0 rt=0 fresh",
        "s6=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "s6=81 [] hat=Neutral ls=258,0 rs=0,0 lt=0 rt=0 fresh",
        "s6=ff [] hat=Neutral ls=32767,0 rs=0,0 lt=0 rt=0 fresh",
        "s7=0 [] hat=Neutral ls=0,-32767 rs=0,0 lt=0 rt=0 fresh",
        "s7=7f [] hat=Neutral ls=0,-255 rs=0,0 lt=0 rt=0 fresh",
        "s7=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "s7=81 [] hat=Neutral ls=0,258 rs=0,0 lt=0 rt=0 fresh",
        "s7=ff [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0 fresh",
        "s8=0 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0 fresh",
        "s8=7f [] hat=Neutral ls=0,0 rs=-255,0 lt=0 rt=0 fresh",
        "s8=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "s8=81 [] hat=Neutral ls=0,0 rs=258,0 lt=0 rt=0 fresh",
        "s8=ff [] hat=Neutral ls=0,0 rs=32767,0 lt=0 rt=0 fresh",
        "s9=0 [] hat=Neutral ls=0,0 rs=0,-32767 lt=0 rt=0 fresh",
        "s9=7f [] hat=Neutral ls=0,0 rs=0,-255 lt=0 rt=0 fresh",
        "s9=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "s9=81 [] hat=Neutral ls=0,0 rs=0,258 lt=0 rt=0 fresh",
        "s9=ff [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0 fresh",
        "t18=80 [] hat=Neutral ls=0,0 rs=0,0 lt=32896 rt=0 fresh",
        "t18=ff [] hat=Neutral ls=0,0 rs=0,0 lt=65535 rt=0 fresh",
        "t18=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "t19=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=32896 fresh",
        "t19=ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=65535 fresh",
        "t19=0 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "repeat [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "byte1=ff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
        "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0 fresh",
      ]
    )
  }

  /// The Bluetooth-bound Sixaxis decodes the same frames.
  @Test
  func sixaxisBluetooth() throws {
    let lines = try transcript(Subjects.sixaxisBluetooth, Array(Self.sixaxisSteps.prefix(4)))
    #expect(
      lines == [
        "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.0 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.1 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.2 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }
}
