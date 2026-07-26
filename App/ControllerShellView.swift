import ATEMKit
import SwiftUI
import UIKit

private enum SheetDestination: String, Identifiable {
    case settings

    var id: String { rawValue }
}

@MainActor
struct ControllerShellView: View {
    let controller: ATEMController

    @State private var presentedSheet: SheetDestination?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        if let errorMessage = controller.errorMessage {
                            errorBanner(errorMessage)
                        }
                        SwitcherControlView(controller: controller)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(
                        maxWidth: 1180,
                        minHeight: max(geometry.size.height - 44, 0)
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
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

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ATEM Mini")
                    .font(.title.bold())
                Text(controller.host)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            statusLabel

            if controller.isBusy {
                ProgressView()
                    .controlSize(.large)
            }

            connectionButton

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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var connectionButton: some View {
        if controller.isConnected || controller.isBusy {
            Button {
                controller.disconnect()
            } label: {
                Label(
                    controller.isBusy ? "Cancel" : "Disconnect",
                    systemImage: "stop.fill"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("connectionButton")
        } else {
            Button {
                controller.connect()
            } label: {
                Label("Connect", systemImage: "bolt.horizontal.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("connectionButton")
        }
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
