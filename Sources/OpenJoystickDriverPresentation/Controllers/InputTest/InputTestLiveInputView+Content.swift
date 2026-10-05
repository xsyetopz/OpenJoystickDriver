#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension InputTestLiveInputView {
    @ViewBuilder
    var body: some View {
      if embedded {
        content
      } else {
        GroupBox {
          content
        } label: {
          Text(OJDLocalized.string("inputTest.controls")).font(.headline)
        }
      }
    }

    var content: some View {
      let snapshot = liveState.snapshot
      let labels = liveState.labels
      let pressed = snapshot.pressed
      let presentation = publishedProfile.presentation
      let symbols = InputTestControllerSymbolSet.resolve(for: presentation.glyphFamily)
      return VStack(spacing: 10) {
        shoulderRow(snapshot: snapshot, symbols: symbols)
        Divider()
        HStack(alignment: .center, spacing: 18) {
          dpadCluster(hat: snapshot.hat).frame(maxWidth: .infinity)
          systemCluster(pressed: pressed, labels: labels, symbols: symbols).frame(
            maxWidth: .infinity
          )
          faceButtonCluster(pressed: pressed, symbols: symbols).frame(maxWidth: .infinity)
        }
        Divider()
        HStack(alignment: .top, spacing: 24) {
          InputTestStickView(
            title: OJDLocalized.string("inputTest.leftStick"),
            x: snapshot.leftStick.x.normalized,
            y: -snapshot.leftStick.y.normalized,
            clickPresentation: symbols.leftStickClick,
            clickActive: pressed.contains(.leftStickClick)
          )
          InputTestStickView(
            title: OJDLocalized.string("inputTest.rightStick"),
            x: snapshot.rightStick.x.normalized,
            y: -snapshot.rightStick.y.normalized,
            clickPresentation: symbols.rightStickClick,
            clickActive: pressed.contains(.rightStickClick)
          )
        }
        let additionalButtons = InputTestButtonPresentation.additionalControls(
          in: snapshot,
          labels: labels
        )
        if !additionalButtons.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 8) {
            Text(OJDLocalized.string("inputTest.additionalButtons"))
              .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
              ForEach(additionalButtons, id: \.self) { control in
                InputTestIndicator(
                  title: InputTestButtonPresentation.localizedTitle(for: control, labels: labels),
                  active: true
                )
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }.padding(6)
    }

    private func shoulderRow(
      snapshot: ControllerState,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      HStack(spacing: 10) {
        indicator(symbols.leftShoulder, active: snapshot.pressed.contains(.leftShoulder))
        indicator(
          symbols.leftTrigger,
          active: snapshot.leftTrigger.normalized > 0.05
            || snapshot.pressed.contains(.leftTriggerButton)
        )
        indicator(
          symbols.rightTrigger,
          active: snapshot.rightTrigger.normalized > 0.05
            || snapshot.pressed.contains(.rightTriggerButton)
        )
        indicator(symbols.rightShoulder, active: snapshot.pressed.contains(.rightShoulder))
      }
    }

    private func dpadCluster(hat: HatDirection) -> some View {
      let directions = RuntimePresentation.dpadDirections(hat)
      return VStack(spacing: 6) {
        indicator(
          OJDLocalized.string("inputTest.dpadUp"),
          symbol: "dpad.up.filled",
          fallbackSymbol: "arrowtriangle.up.fill",
          active: directions.contains(.up)
        )
        HStack(spacing: 6) {
          indicator(
            OJDLocalized.string("inputTest.dpadLeft"),
            symbol: "dpad.left.filled",
            fallbackSymbol: "arrowtriangle.left.fill",
            active: directions.contains(.left)
          )
          indicator(
            OJDLocalized.string("inputTest.dpadRight"),
            symbol: "dpad.right.filled",
            fallbackSymbol: "arrowtriangle.right.fill",
            active: directions.contains(.right)
          )
        }
        indicator(
          OJDLocalized.string("inputTest.dpadDown"),
          symbol: "dpad.down.filled",
          fallbackSymbol: "arrowtriangle.down.fill",
          active: directions.contains(.down)
        )
      }
    }

    @ViewBuilder
    private func systemCluster(
      pressed: Set<ControlID>,
      labels: ControllerButtonLabels,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      HStack(spacing: 6) {
        indicator(
          symbols.view,
          active: !pressed.isDisjoint(
            with: InputTestSystemClusterLayout.viewControls(labels: labels)
          )
        )
        indicator(symbols.guide, active: pressed.contains(.guide))
        indicator(symbols.menu, active: pressed.contains(.menu))
      }
    }

    private func faceButtonCluster(
      pressed: Set<ControlID>,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      VStack(spacing: 6) {
        indicator(symbols.northFace, active: pressed.contains(.faceNorth))
        HStack(spacing: 6) {
          indicator(symbols.westFace, active: pressed.contains(.faceWest))
          indicator(symbols.eastFace, active: pressed.contains(.faceEast))
        }
        indicator(symbols.southFace, active: pressed.contains(.faceSouth))
      }
    }

    func indicator(
      _ title: String,
      symbol: String,
      fallbackSymbol: String? = nil,
      active: Bool
    ) -> some View {
      InputTestIndicator(
        title: title,
        symbol: symbol,
        fallbackSymbol: fallbackSymbol,
        active: active
      )
    }

    func indicator(_ presentation: InputTestControllerSymbolSet.Control, active: Bool) -> some View
    {
      InputTestIndicator(
        title: presentation.title,
        symbol: presentation.symbol,
        fallbackSymbol: presentation.fallbackSymbol,
        fallbackText: presentation.fallbackText,
        active: active
      )
    }
  }

#endif
