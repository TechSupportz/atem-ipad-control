import SwiftUI

@MainActor
struct SwitcherControlView: View {
    let controller: ATEMController

    var body: some View {
        VStack(spacing: 22) {
            InputBusRow(
                title: "Program",
                activeSourceName: controller.snapshot.programSource?.displayName ?? "—",
                selectedInput: controller.snapshot.programInput,
                pendingInput: controller.pendingProgramInput,
                tint: .red,
                isEnabled: controller.isConnected,
                accessibilityPrefix: "program"
            ) { input in
                controller.selectProgramInput(input)
            }

            InputBusRow(
                title: "Preview",
                activeSourceName: controller.snapshot.previewSource?.displayName ?? "—",
                selectedInput: controller.snapshot.previewInput,
                pendingInput: controller.pendingPreviewInput,
                tint: .green,
                isEnabled: controller.isConnected,
                accessibilityPrefix: "preview"
            ) { input in
                controller.selectPreviewInput(input)
            }

            HStack(spacing: 18) {
                Spacer()
                TransitionButton(
                    title: "CUT",
                    isPending: controller.pendingTransition == .cut,
                    isEnabled: controller.isConnected && controller.pendingTransition == nil,
                    tint: .primary,
                    accessibilityIdentifier: "cutButton"
                ) {
                    controller.performTransition(.cut)
                }
                TransitionButton(
                    title: "AUTO",
                    isPending: controller.pendingTransition == .auto,
                    isEnabled: controller.isConnected && controller.pendingTransition == nil,
                    tint: .blue,
                    accessibilityIdentifier: "autoButton"
                ) {
                    controller.performTransition(.auto)
                }
                Spacer()
            }
        }
        .padding(24)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct InputBusRow: View {
    let title: String
    let activeSourceName: String
    let selectedInput: UInt16?
    let pendingInput: UInt16?
    let tint: Color
    let isEnabled: Bool
    let accessibilityPrefix: String
    let action: (UInt16) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .textCase(.uppercase)
                Spacer()
                Text(activeSourceName)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 14) {
                ForEach(UInt16(1)...UInt16(4), id: \.self) { input in
                    InputButton(
                        busTitle: title,
                        input: input,
                        isSelected: selectedInput == input,
                        isPending: pendingInput == input,
                        tint: tint,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "\(accessibilityPrefix)Input\(input)"
                    ) {
                        action(input)
                    }
                }
            }
        }
    }
}

private struct InputButton: View {
    let busTitle: String
    let input: UInt16
    let isSelected: Bool
    let isPending: Bool
    let tint: Color
    let isEnabled: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button {
            guard !isSelected else {
                return
            }
            action()
        } label: {
            Text(String(input))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 76)
                .foregroundStyle(foregroundStyle)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    if isPending {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                tint,
                                style: StrokeStyle(lineWidth: 4, dash: [9, 6])
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("\(busTitle) Input \(input)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var foregroundStyle: Color {
        isSelected ? .white : .primary
    }

    private var backgroundStyle: Color {
        if isSelected {
            return tint
        }
        if isPending {
            return tint.opacity(0.24)
        }
        return Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var accessibilityValue: String {
        if isSelected {
            return "Selected"
        }
        if isPending {
            return "Pending"
        }
        return "Not selected"
    }
}

private struct TransitionButton: View {
    let title: String
    let isPending: Bool
    let isEnabled: Bool
    let tint: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isPending {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.title2.bold())
            }
            .frame(width: 170, height: 62)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
