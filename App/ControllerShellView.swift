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

            VStack(spacing: 28) {
                header
                connectionCard
                stateCard
                Spacer(minLength: 0)
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
                Text("Direct local control")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusLabel

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

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Switcher address")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(controller.host)
                        .font(.title2.monospaced())
                }

                Spacer()

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
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .accessibilityIdentifier("connectionError")
            }
        }
        .padding(24)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Handshake verification")
                .font(.title3.bold())

            HStack(spacing: 16) {
                StateValue(
                    title: "Program",
                    value: controller.snapshot.programSource?.displayName ?? "—",
                    color: .red
                )
                StateValue(
                    title: "Preview",
                    value: controller.snapshot.previewSource?.displayName ?? "—",
                    color: .green
                )
                StateValue(
                    title: "Initial commands",
                    value: String(controller.initialStateCommandCount),
                    color: .blue
                )
            }

            Text(
                controller.snapshot.isInitialSyncComplete
                    ? "Initial state synchronization completed."
                    : "Connect to verify the iPad receives the ATEM initial state."
            )
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct StateValue: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
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
