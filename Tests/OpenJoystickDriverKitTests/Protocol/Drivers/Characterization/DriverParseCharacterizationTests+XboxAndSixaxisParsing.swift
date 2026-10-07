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
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.1 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.2 [menu] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.3 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.4 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.5 [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.6 [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b0.7 [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.4 [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.5 [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.6 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b1.7 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.0 [share] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.1 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.4 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.5 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.6 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b14.7 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "h1 [] hat=north ls=0,0 rs=0,0 lt=0 rt=0",
        "h9 [] hat=northEast ls=0,0 rs=0,0 lt=0 rt=0", "h8 [] hat=east ls=0,0 rs=0,0 lt=0 rt=0",
        "ha [] hat=southEast ls=0,0 rs=0,0 lt=0 rt=0", "h2 [] hat=south ls=0,0 rs=0,0 lt=0 rt=0",
        "h6 [] hat=southWest ls=0,0 rs=0,0 lt=0 rt=0", "h4 [] hat=west ls=0,0 rs=0,0 lt=0 rt=0",
        "h5 [] hat=northWest ls=0,0 rs=0,0 lt=0 rt=0", "h3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "lt=1ff [] hat=neutral ls=0,0 rs=0,0 lt=32735 rt=0",
        "lt=3ff [] hat=neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "lt=400 [] hat=neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "lt=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "rt=1ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=32735",
        "rt=3ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "rt=400 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "rt=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
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
        "repeat [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "guide [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "guide-up [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "ack-req [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "ack [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "chunk [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "status [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// A GIP frame split across two transfers is reassembled on the second.
  @Test
  func gipSplitFrame() throws {
    let lines = try transcript(Subjects.gipUSB, Self.gipSplitSteps)
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "head [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "tail [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Xbox 360 wired reports.
  @Test
  func xusbWired() throws {
    let lines = try transcript(Subjects.xusbWired, Self.xusbWiredSteps)
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
        "repeat [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "len=13 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Receiver pad data gated on presence; a disconnect releases nothing today.
  @Test
  func xusbReceiver() throws {
    let lines = try transcript(Subjects.xusbReceiver, Self.xusbReceiverSteps)
    #expect(
      lines == [
        "early-a [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "connect [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "a [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "lsx=max [] hat=neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "a+up [face-south] hat=north ls=0,0 rs=0,0 lt=0 rt=0",
        "disconnect [face-south] hat=north ls=0,0 rs=0,0 lt=0 rt=0",
        "late-b [face-south] hat=north ls=0,0 rs=0,0 lt=0 rt=0",
        "short [face-south] hat=north ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Original Xbox XID reports; analog face and shoulder keys press at any nonzero value.
  @Test
  func xid() throws {
    let lines = try transcript(Subjects.xidGamepad, Self.xidSteps)
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.4 [menu] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.5 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.6 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.7 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "h1 [] hat=north ls=0,0 rs=0,0 lt=0 rt=0", "h9 [] hat=northEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h8 [] hat=east ls=0,0 rs=0,0 lt=0 rt=0", "ha [] hat=southEast ls=0,0 rs=0,0 lt=0 rt=0",
        "h2 [] hat=south ls=0,0 rs=0,0 lt=0 rt=0", "h6 [] hat=southWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h4 [] hat=west ls=0,0 rs=0,0 lt=0 rt=0", "h5 [] hat=northWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k4=1 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k4=ff [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k4=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k5=1 [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k5=ff [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k5=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k6=1 [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k6=ff [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k6=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k7=1 [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k7=ff [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k7=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k8=1 [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k8=ff [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k8=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k9=1 [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k9=ff [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "k9=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t10=80 [] hat=neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t10=ff [] hat=neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t10=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t11=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t11=ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t11=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s12=8000 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s12=8001 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s12=7fff [] hat=neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s12=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s14=8000 [] hat=neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s14=8001 [] hat=neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s14=7fff [] hat=neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s14=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s16=8000 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s16=8001 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s16=7fff [] hat=neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s16=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s18=8000 [] hat=neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s18=8001 [] hat=neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "s18=7fff [] hat=neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s18=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "repeat [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// Sixaxis reports; a 0xFF second byte drops the report.
  @Test
  func sixaxisUSB() throws {
    let lines = try transcript(Subjects.sixaxisUSB, Self.sixaxisSteps)
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.0 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.1 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.2 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.3 [menu] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.0 [left-trigger-button] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.1 [right-trigger-button] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.2 [left-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.3 [right-shoulder] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.4 [face-north] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.5 [face-east] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.6 [face-south] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b3.7 [face-west] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.0 [guide] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.1 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.2 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.3 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.4 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.5 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.6 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b4.7 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "h10 [] hat=north ls=0,0 rs=0,0 lt=0 rt=0",
        "h30 [] hat=northEast ls=0,0 rs=0,0 lt=0 rt=0", "h20 [] hat=east ls=0,0 rs=0,0 lt=0 rt=0",
        "h60 [] hat=southEast ls=0,0 rs=0,0 lt=0 rt=0", "h40 [] hat=south ls=0,0 rs=0,0 lt=0 rt=0",
        "hc0 [] hat=southWest ls=0,0 rs=0,0 lt=0 rt=0", "h80 [] hat=west ls=0,0 rs=0,0 lt=0 rt=0",
        "h90 [] hat=northWest ls=0,0 rs=0,0 lt=0 rt=0",
        "h50 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0", "h0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s6=0 [] hat=neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
        "s6=7f [] hat=neutral ls=-255,0 rs=0,0 lt=0 rt=0",
        "s6=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s6=81 [] hat=neutral ls=258,0 rs=0,0 lt=0 rt=0",
        "s6=ff [] hat=neutral ls=32767,0 rs=0,0 lt=0 rt=0",
        "s7=0 [] hat=neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
        "s7=7f [] hat=neutral ls=0,-255 rs=0,0 lt=0 rt=0",
        "s7=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s7=81 [] hat=neutral ls=0,258 rs=0,0 lt=0 rt=0",
        "s7=ff [] hat=neutral ls=0,32767 rs=0,0 lt=0 rt=0",
        "s8=0 [] hat=neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
        "s8=7f [] hat=neutral ls=0,0 rs=-255,0 lt=0 rt=0",
        "s8=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s8=81 [] hat=neutral ls=0,0 rs=258,0 lt=0 rt=0",
        "s8=ff [] hat=neutral ls=0,0 rs=32767,0 lt=0 rt=0",
        "s9=0 [] hat=neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
        "s9=7f [] hat=neutral ls=0,0 rs=0,-255 lt=0 rt=0",
        "s9=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "s9=81 [] hat=neutral ls=0,0 rs=0,258 lt=0 rt=0",
        "s9=ff [] hat=neutral ls=0,0 rs=0,32767 lt=0 rt=0",
        "t18=80 [] hat=neutral ls=0,0 rs=0,0 lt=32896 rt=0",
        "t18=ff [] hat=neutral ls=0,0 rs=0,0 lt=65535 rt=0",
        "t18=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "t19=80 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=32896",
        "t19=ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=65535",
        "t19=0 [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "repeat [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "byte1=ff [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "short [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }

  /// The Bluetooth-bound Sixaxis decodes the same frames.
  @Test
  func sixaxisBluetooth() throws {
    let lines = try transcript(Subjects.sixaxisBluetooth, Array(Self.sixaxisSteps.prefix(4)))
    #expect(
      lines == [
        "neutral [] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.0 [view] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.1 [left-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "b2.2 [right-stick-click] hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
      ]
    )
  }
}
