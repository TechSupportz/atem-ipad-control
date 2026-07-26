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

            VStack(spacing: 22) {
                header
                if let errorMessage = controller.errorMessage {
                    errorBanner(errorMessage)
                }
                SwitcherControlView(controller: controller)
            }
            .padding(32)
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ATEM Mini")
                    .font(.largeTitle.bold())
                Text(controller.host)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusLabel

            if controller.isBusy {
                ProgressView()
                    .controlSize(.large)
            }

            Button(controller.isConnected || controller.isBusy ? "Disconnect" : "Connect") {
                if controller.isConnected || controller.isBusy {
                    controller.disconnect()
                } else {
                    controller.connect()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("connectionButton")

            Button {
                presentedSheet = .settings
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settingsButton")
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.isConnected ? .green : .secondary)
                .frame(width: 12, height: 12)
            Text(controller.statusTitle)
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connectionStatus")
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
