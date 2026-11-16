#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension AccessAreaView {
    /// The lists of programs, tokens, refused clients and open connections; a list with nothing
    /// in it is left out.
    @ViewBuilder
    func listSections(_ status: AccessStatusPayload) -> some View {
      let layout = AccessLayout(status)
      if layout.showsGrants { grantsSection(status) }
      if layout.showsTokens { tokensSection(status) }
      if layout.showsRefused { refusedSection(status) }
      if layout.showsConnections { connectionsSection(status) }
    }

    /// Returns the section of programs that are granted access, each with a Revoke control.
    private func grantsSection(_ status: AccessStatusPayload) -> some View {
      Section(header: Text(OJDLocalized.string("ui.access.grants"))) {
        ForEach(status.grants, id: \.id) { grant in
          row(
            title: grant.identifier,
            detail: OJDLocalized.formatted(
              "ui.access.detail.pair",
              AccessPresentation.signer(grant.publisher.kind, grant.publisher.id),
              AccessPresentation.scopes(grant.scopes)
            ),
            help: AccessPresentation.location(grant.path)
          ) {
            revokeControl(
              scopes: grant.scopes,
              label: OJDLocalized.formatted("a11y.access.revokeGrant", grant.identifier),
            ) { model.requestRevoke(grant, scope: $0) }
          }
        }
      }
    }

    /// Returns the section of tokens, each with a Revoke control.
    private func tokensSection(_ status: AccessStatusPayload) -> some View {
      Section(header: Text(OJDLocalized.string("ui.access.tokens"))) {
        ForEach(status.tokens, id: \.id) { token in
          row(
            title: token.name,
            detail: token.origins.isEmpty
              ? AccessPresentation.scopes(token.scopes)
              : OJDLocalized.formatted(
                "ui.access.detail.pair",
                AccessPresentation.scopes(token.scopes),
                token.origins.joined(separator: ", ")
              ),
            help: nil
          ) {
            revokeControl(
              scopes: token.scopes,
              label: OJDLocalized.formatted("a11y.access.revokeToken", token.name),
            ) { model.requestRevoke(token, scope: $0) }
          }
        }
      }
    }

    /// Returns the section of clients and tokens that the service refused, where a client can be
    /// granted.
    private func refusedSection(_ status: AccessStatusPayload) -> some View {
      Section(
        header: Text(OJDLocalized.string("ui.access.refused")),
        footer: Text(OJDLocalized.string("ui.access.refused.message"))
      ) {
        ForEach(status.refused, id: \.id) { client in
          row(
            title: client.identifier,
            detail: OJDLocalized.formatted(
              "ui.access.detail.triple",
              AccessPresentation.signer(client.publisher.kind, client.publisher.id),
              AccessPresentation.scopes(client.scopes),
              client.reason
            ),
            help: client.path.map(AccessPresentation.location)
          ) {
            Button(OJDLocalized.string("ui.access.grant")) { model.requestRefusedGrant(client) }
              .disabled(model.busy).ojdAccessibilityLabel(
                OJDLocalized.formatted("a11y.access.grantRefused", client.identifier)
              ).help(OJDLocalized.string("ui.help.grantRefused"))
          }
        }
        ForEach(Array(status.refusedTokens.enumerated()), id: \.offset) { _, token in
          row(
            title: token.name.map { OJDLocalized.formatted("ui.access.token.named", $0) }
              ?? OJDLocalized.string("ui.access.token.unknown"),
            detail: [
              OJDLocalized.formatted(
                "ui.access.detail.triple",
                AccessPresentation.transport(token.transport),
                AccessPresentation.scopes(token.scopes),
                token.reason
              ), token.origin,
            ].compactMap { $0 }.joined(separator: " · "),
            help: nil
          ) {}
        }
      }
    }

    /// Returns the section of the connections that are open.
    private func connectionsSection(_ status: AccessStatusPayload) -> some View {
      Section(header: Text(OJDLocalized.string("ui.access.connections"))) {
        ForEach(status.connections, id: \.id) { connection in
          row(
            title: connection.identifier,
            detail: OJDLocalized.formatted(
              "ui.access.detail.pair",
              AccessPresentation.transport(connection.transport),
              AccessPresentation.scopes(connection.scopes)
            ),
            help: nil
          ) {}
        }
      }
    }

    /// A title with its detail line and a trailing control. `help` is the tooltip: a path or
    /// origin that is not shown in the row.
    private func row<Trailing: View>(
      title: String,
      detail: String,
      help: String?,
      @ViewBuilder trailing: () -> Trailing
    ) -> some View {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
          Text(title)
          Text(detail).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }.textSelection(.enabled).accessibilityElement(children: .combine)
          .ojdAccessibilityLabel(title).ojdAccessibilityValue(detail)
        Spacer(minLength: 8)
        trailing()
      }.help(help ?? "")
    }

    /// Revoke for a grant or token: a button for the whole grant, or a menu of the whole grant
    /// and each scope when it has several.
    @ViewBuilder
    private func revokeControl(
      scopes: [EndpointScope],
      label: String,
      revoke: @escaping (EndpointScope?) -> Void
    ) -> some View {
      let choices = AccessViewModel.scopeChoices(of: scopes)
      if choices.isEmpty {
        Button(OJDLocalized.string("ui.access.revoke")) { revoke(nil) }.disabled(model.busy)
          .ojdAccessibilityLabel(label).help(OJDLocalized.string("ui.help.revoke"))
      } else {
        Menu(OJDLocalized.string("ui.access.revoke")) {
          Button(OJDLocalized.string("ui.access.revoke.all")) { revoke(nil) }
          ForEach(choices, id: \.self) { scope in
            Button(AccessPresentation.scope(scope)) { revoke(scope) }
          }
        }.fixedSize().disabled(model.busy).ojdAccessibilityLabel(label)
          .help(OJDLocalized.string("ui.help.revoke"))
      }
    }
  }

#endif
