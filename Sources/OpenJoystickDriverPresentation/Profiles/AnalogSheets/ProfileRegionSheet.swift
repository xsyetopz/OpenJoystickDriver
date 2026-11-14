#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that adds a stick ring, trigger band or touch area as an assignment source, with
  /// the live position of the input it watches.
  struct ProfileRegionSheet: View {
    /// The model whose service gateway and connected controllers the live view reads.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The stick mappings of the profile, whose dead zones the live stick position applies.
    let stickMappings: [RemappingStickMapping]
    /// Receives the source and destination when the person chooses Add Assignment.
    let onAdd: (RemappingSource, RemappingDestination) throws -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The region being edited.
    @State
    private var draft = ProfileRegionDraft()
    /// The destination of the assignment.
    @State
    private var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])
    /// Whether the keyboard destination lost its key.
    @State
    private var keyboardDestinationCleared = false
    /// Whether the keyboard destination waits for a key press.
    @State
    private var keyboardCaptureActive = false
    /// The latest input state of the first connected controller, or nil.
    @State
    private var state: ControllerState?
    /// The message of the failed validation, or nil.
    @State
    private var errorMessage: String?

    /// The title, the kind and input pickers, the fields, the live view and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(label("title")).font(.headline)
        Picker(label("kind"), selection: $draft.kind) {
          ForEach(ProfileRegionDraft.Kind.allCases, id: \.self) { kind in
            Text(kindLabel(kind)).tag(kind)
          }
        }.help(tooltip("kind")).pickerStyle(SegmentedPickerStyle())
        ScrollView {
          VStack(alignment: .leading, spacing: OJDSpacing.medium) {
            inputPicker
            fields
            liveView
            Picker(OJDLocalized.string("term.destination"), selection: $destination) {
              ForEach(
                DestinationOption.options(for: sourceOrDefault, including: destination),
                id: \.destination
              ) { option in Text(option.title).tag(option.destination) }
            }.help(OJDLocalized.string("ui.capture.destinationHelp"))
            if case .keyboard = destination {
              KeyboardDestinationCaptureView(
                destination: $destination,
                isCleared: $keyboardDestinationCleared,
                isCapturing: $keyboardCaptureActive
              )
            }
          }.padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { presentationMode.wrappedValue.dismiss() }
            .help(OJDLocalized.string("ui.help.cancel"))
          Button(OJDLocalized.string("action.addAssignment")) { add() }.help(
            OJDLocalized.string("ui.profiles.addAssignmentHelp")
          )
          .disabled(keyboardDestinationCleared)
        }
      }.ojdSheet(.regular).frame(height: 640).task { await poll() }
    }

    /// The source of the draft, or the first stick ring while a number cannot be read.
    private var sourceOrDefault: RemappingSource {
      (try? draft.source(decimalSeparator: separator))
        ?? .stickRegion(RemappingStickRegionSource(stick: .left, innerRadius: 0, outerRadius: 1))
    }

    /// The separator the person types in the numbers.
    private var separator: String { Locale.current.decimalSeparator ?? "." }

    /// The picker of the stick, trigger or surface that the region reads.
    @ViewBuilder
    private var inputPicker: some View {
      switch draft.kind {
      case .stick:
        Picker(label("input"), selection: $draft.stick) {
          Text(OJDLocalized.string("ui.profiles.gyro.leftStick")).tag(RemappingStickSource.left)
          Text(OJDLocalized.string("ui.profiles.gyro.rightStick")).tag(RemappingStickSource.right)
        }.help(tooltip("input"))
      case .trigger:
        Picker(label("input"), selection: $draft.trigger) {
          Text(OJDLocalized.string("ui.profiles.trigger.left")).tag(RemappingTriggerSource.left)
          Text(OJDLocalized.string("ui.profiles.trigger.right")).tag(RemappingTriggerSource.right)
        }.help(tooltip("input"))
      case .touch:
        Picker(label("input"), selection: $draft.surface) {
          ForEach(RemappingTouchSurface.allCases, id: \.self) { surface in
            Text(RuntimePresentation.touchSurfaceLabel(surface)).tag(surface)
          }
        }.help(tooltip("input"))
      }
    }

    /// The number fields of the kind.
    @ViewBuilder
    private var fields: some View {
      switch draft.kind {
      case .stick:
        field(label("innerRadius"), help: tooltip("innerRadius"), $draft.innerRadius)
        field(label("outerRadius"), help: tooltip("outerRadius"), $draft.outerRadius)
        field(label("fromDegrees"), help: tooltip("fromDegrees"), $draft.fromDegrees)
        field(label("toDegrees"), help: tooltip("toDegrees"), $draft.toDegrees)
        field(
          OJDLocalized.string("ui.profiles.trigger.hysteresis"),
          help: OJDLocalized.string("ui.profiles.trigger.hysteresisHelp"),
          $draft.hysteresis
        )
      case .trigger:
        field(label("from"), help: tooltip("from"), $draft.from)
        field(label("to"), help: tooltip("to"), $draft.to)
        field(
          OJDLocalized.string("ui.profiles.trigger.hysteresis"),
          help: OJDLocalized.string("ui.profiles.trigger.hysteresisHelp"),
          $draft.hysteresis
        )
      case .touch:
        field(label("x"), help: tooltip("x"), $draft.x)
        field(label("y"), help: tooltip("y"), $draft.y)
        field(label("width"), help: tooltip("width"), $draft.width)
        field(label("height"), help: tooltip("height"), $draft.height)
      }
    }

    /// The live position of the input, or a note that no controller is connected.
    @ViewBuilder
    private var liveView: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Text(label("live")).font(.subheadline)
        if let state {
          let reading = draft.reading(of: state, tuning: tuning)
          ProfileRegionLiveView(draft: draft, reading: reading, decimalSeparator: separator)
            .frame(height: draft.kind == .trigger ? 24 : 160)
          Text(readingText(reading)).font(.body)
        } else {
          Text(label("noController")).font(.caption).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
      }
    }

    /// The tuning of the mapping of the chosen stick, or the default.
    private var tuning: RemappingStickTuning {
      stickMappings.first { $0.source == draft.stick }?.tuning ?? .default
    }

    /// The text of a reading.
    private func readingText(_ reading: ProfileRegionDraft.Reading) -> String {
      switch reading {
      case .stick(_, _, let deflection, let degrees):
        return OJDLocalized.formatted("ui.profiles.region.liveStick", deflection, degrees)
      case .trigger(let value):
        return OJDLocalized.formatted("ui.profiles.region.liveTrigger", value)
      case .touch(let x, let y): return OJDLocalized.formatted("ui.profiles.region.liveTouch", x, y)
      case .noContact: return label("noContact")
      }
    }

    /// A text field titled `title`.
    private func field(_ title: String, help: String, _ value: Binding<String>) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        Text(title)
        TextField(title, text: value).textFieldStyle(RoundedBorderTextFieldStyle())
          .ojdAccessibilityLabel(title).help(help)
      }
    }

    /// Returns the text of the region string called `key`.
    private func label(_ key: String) -> String { OJDLocalized.string("ui.profiles.region." + key) }

    /// Returns the tooltip of the region field called `key`.
    private func tooltip(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.region." + key + "Help")
    }

    /// Returns the name of a region kind.
    private func kindLabel(_ kind: ProfileRegionDraft.Kind) -> String {
      switch kind {
      case .stick: label("stick")
      case .trigger: label("trigger")
      case .touch: label("touch")
      }
    }

    /// Adds the assignment and closes the sheet, or shows why it cannot.
    private func add() {
      do {
        try onAdd(try draft.source(decimalSeparator: separator), destination)
        presentationMode.wrappedValue.dismiss()
      } catch { errorMessage = RuntimePresentation.userFacingError(error) }
    }

    /// Reads the input state of the first connected controller until the sheet closes.
    private func poll() async {
      while !Task.isCancelled {
        if case .available(let status) = viewModel.statusState,
          let device = status.devices.first
        {
          state = try? await viewModel.gateway.controllerState(
            for: .session(device.sessionToken)
          )
        } else {
          state = nil
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
    }
  }

  /// The drawing of a region and the live position inside it.
  private struct ProfileRegionLiveView: View {
    /// The region being edited.
    let draft: ProfileRegionDraft
    /// The live position.
    let reading: ProfileRegionDraft.Reading
    /// The separator the person types in the numbers.
    let decimalSeparator: String

    /// The region shaded behind a dot at the live position.
    var body: some View {
      Canvas { context, size in
        let frame = CGRect(origin: .zero, size: size)
        context.stroke(Path(frame), with: .color(.secondary))
        guard let source = try? draft.source(decimalSeparator: decimalSeparator) else { return }
        let shade = GraphicsContext.Shading.color(.accentColor.opacity(0.35))
        switch (source, reading) {
        case (.stickRegion(let region), .stick(let x, let y, _, _)):
          let side = min(size.width, size.height)
          let center = CGPoint(x: size.width / 2, y: size.height / 2)
          let radius = side / 2
          context.stroke(
            Path(
              ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: side,
                height: side
              )
            ),
            with: .color(.secondary)
          )
          let start = region.fromDegrees ?? 0
          let end = region.fromDegrees == nil ? 360 : (region.toDegrees ?? 360)
          let sweep = end > start ? end - start : end + 360 - start
          var wedge = Path()
          for step in 0...48 {
            let angle = (start + sweep * Double(step) / 48 - 90) * .pi / 180
            let point = CGPoint(
              x: center.x + cos(angle) * radius * region.outerRadius,
              y: center.y + sin(angle) * radius * region.outerRadius
            )
            if step == 0 {
              wedge.move(to: point)
            } else {
              wedge.addLine(to: point)
            }
          }
          for step in (0...48).reversed() {
            let angle = (start + sweep * Double(step) / 48 - 90) * .pi / 180
            wedge.addLine(
              to: CGPoint(
                x: center.x + cos(angle) * radius * region.innerRadius,
                y: center.y + sin(angle) * radius * region.innerRadius
              )
            )
          }
          context.fill(wedge, with: shade)
          dot(context, CGPoint(x: center.x + x * radius, y: center.y + y * radius))
        case (.triggerBand(let band), .trigger(let value)):
          context.fill(
            Path(
              CGRect(
                x: size.width * band.from,
                y: 0,
                width: size.width * (band.to - band.from),
                height: size.height
              )
            ),
            with: shade
          )
          dot(context, CGPoint(x: size.width * value, y: size.height / 2))
        case (.touchArea(let area), .touch(let x, let y)):
          context.fill(Path(areaRect(area, size)), with: shade)
          dot(context, CGPoint(x: size.width * x, y: size.height * y))
        case (.touchArea(let area), .noContact):
          context.fill(Path(areaRect(area, size)), with: shade)
        default: break
        }
      }
    }

    /// The rectangle of a touch area in a canvas of `size`.
    private func areaRect(_ area: RemappingTouchAreaSource, _ size: CGSize) -> CGRect {
      CGRect(
        x: size.width * area.x,
        y: size.height * area.y,
        width: size.width * area.width,
        height: size.height * area.height
      )
    }

    /// Draws the live position.
    private func dot(_ context: GraphicsContext, _ point: CGPoint) {
      context.fill(
        Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
        with: .color(.primary)
      )
    }
  }
#endif
