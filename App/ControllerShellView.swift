import ATEMKit
import SwiftUI
import UIKit

private enum SheetDestination: String, Identifiable {
    case settings

    var id: String { rawValue }
}

@MainActor
struct ControllerShellView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let controller: ATEMController

    @State private var presentedSheet: SheetDestination?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            GeometryReader { geometry in
                let usesCompactLayout = geometry.size.width < 700
                    || dynamicTypeSize.isAccessibilitySize

                ScrollView {
                    VStack(spacing: usesCompactLayout ? 12 : 18) {
                        header(usesCompactLayout: usesCompactLayout)
                        if let errorMessage = controller.errorMessage {
                            errorBanner(errorMessage)
                        }
                        SwitcherControlView(
                            controller: controller,
                            usesCompactLayout: usesCompactLayout
                        )
                            .frame(maxHeight: .infinity)
                    }
                    .frame(
                        maxWidth: 1180,
                        minHeight: max(
                            geometry.size.height - (usesCompactLayout ? 24 : 44),
                            0
                        )
                    )
                    .padding(.horizontal, usesCompactLayout ? 12 : 24)
                    .padding(.vertical, usesCompactLayout ? 12 : 22)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .settings:
                ATEMSettingsView(controller: controller)
            }
        }
        .onChange(of: controller.isConnected, initial: true) { _, isConnected in
            UIApplication.shared.isIdleTimerDisabled = isConnected
        }
    }

    private func header(usesCompactLayout: Bool) -> some View {
        Group {
            if usesCompactLayout {
                compactHeader
            } else {
                regularHeader
            }
        }
        .padding(.horizontal, usesCompactLayout ? 16 : 20)
        .padding(.vertical, usesCompactLayout ? 14 : 16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var regularHeader: some View {
        HStack(spacing: 14) {
            controllerIdentity

            Spacer(minLength: 12)

            statusLabel

            if controller.isBusy {
                ProgressView()
                    .controlSize(.large)
            }

            connectionButton(expands: false)

            settingsButton
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                controllerIdentity

                Spacer(minLength: 8)

                settingsButton
            }

            HStack(spacing: 12) {
                statusLabel

                if controller.isBusy {
                    ProgressView()
                        .controlSize(.large)
                }

                Spacer(minLength: 0)
            }

            connectionButton(expands: true)
        }
    }

    private var controllerIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ATEM Mini")
                .font(.title.bold())
            Text(controller.host)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func connectionButton(expands: Bool) -> some View {
        if controller.isConnected || controller.isBusy {
            Button {
                controller.disconnect()
            } label: {
                Label(
                    controller.isBusy ? "Cancel" : "Disconnect",
                    systemImage: "stop.fill"
                )
                .frame(maxWidth: expands ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("connectionButton")
        } else {
            Button {
                controller.connect()
            } label: {
                Label("Connect", systemImage: "bolt.horizontal.fill")
                    .frame(maxWidth: expands ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("connectionButton")
        }
    }

    private var settingsButton: some View {
        Button {
            presentedSheet = .settings
        } label: {
            Label("Settings", systemImage: "gearshape.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier("settingsButton")
    }

    private var statusLabel: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            Text(controller.statusTitle)
                .font(.headline)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            statusColor.opacity(controller.isConnected ? 0.13 : 0.08),
            in: Capsule()
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connectionStatus")
    }

    private var statusColor: Color {
        if controller.isConnected {
            return .green
        }
        if controller.isBusy {
            return .orange
        }
        return .secondary
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.red, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("connectionError")
    }
}

#Preview("Disconnected") {
    ControllerShellView(
        controller: ATEMController(
            host: ATEMController.defaultHost,
            connection: ATEMConnection(
                configuration: .init(automaticallyReconnects: false)
            )
        )
    )
}

#Preview("Connected") {
    ControllerShellView(
        controller: ATEMController(
            host: "192.168.18.240",
            connection: ATEMConnection(
                configuration: .init(automaticallyReconnects: false)
            ),
            initialConnectionState: .connected,
            initialSnapshot: ATEMStateSnapshot(
                programInput: 1,
                previewInput: 4,
                isInitialSyncComplete: true
            )
        )
    )
}
