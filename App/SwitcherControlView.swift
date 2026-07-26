import ATEMKit
import SwiftUI

@MainActor
struct SwitcherControlView: View {
    let controller: ATEMController

    var body: some View {
        VStack(spacing: 24) {
            busHeader

            HStack(spacing: 18) {
                ForEach(UInt16(1)...UInt16(4), id: \.self) { input in
                    SourceButton(
                        title: String(input),
                        height: 94,
                        light: light(for: input),
                        isPending: controller.pendingPreviewInput == input,
                        isEnabled: controller.isConnected,
                        accessibilityLabel: "Input \(input)",
                        accessibilityIdentifier: "input\(input)Button"
                    ) {
                        controller.selectPreviewInput(input)
                    }
                }
            }

            HStack(spacing: 16) {
                SourceButton(
                    title: "BLACK",
                    height: 66,
                    light: light(for: ATEMVideoSource.black.rawValue),
                    isPending: controller.pendingPreviewInput
                        == ATEMVideoSource.black.rawValue,
                    isEnabled: controller.isConnected,
                    accessibilityLabel: "Black",
                    accessibilityIdentifier: "blackButton"
                ) {
                    controller.selectPreviewInput(ATEMVideoSource.black.rawValue)
                }
                .frame(width: 170)

                Spacer(minLength: 20)

                ControlButton(
                    title: "CUT",
                    isPending: controller.pendingTransition == .cut,
                    isEnabled: transitionsAreEnabled,
                    background: Color(uiColor: .tertiarySystemFill),
                    foreground: .primary,
                    blinks: false,
                    accessibilityIdentifier: "cutButton"
                ) {
                    controller.performTransition(.cut)
                }
                ControlButton(
                    title: "AUTO",
                    isPending: controller.pendingTransition == .auto
                        || controller.snapshot.transition.isInTransition,
                    isEnabled: transitionsAreEnabled,
                    background: .blue,
                    foreground: .white,
                    blinks: false,
                    accessibilityIdentifier: "autoButton"
                ) {
                    controller.performTransition(.auto)
                }
                ControlButton(
                    title: "FTB",
                    isPending: controller.isFadeToBlackPending
                        || controller.snapshot.fadeToBlack.isInTransition,
                    isEnabled: controller.isConnected
                        && !controller.isFadeToBlackPending
                        && !controller.snapshot.fadeToBlack.isInTransition,
                    background: controller.snapshot.fadeToBlack.isFullyBlack
                        || controller.snapshot.fadeToBlack.isInTransition
                        ? .red
                        : Color(uiColor: .tertiarySystemFill),
                    foreground: controller.snapshot.fadeToBlack.isFullyBlack
                        || controller.snapshot.fadeToBlack.isInTransition
                        ? .white
                        : .primary,
                    blinks: controller.snapshot.fadeToBlack.isFullyBlack,
                    accessibilityIdentifier: "fadeToBlackButton"
                ) {
                    controller.performFadeToBlack()
                }
            }
        }
        .padding(24)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var busHeader: some View {
        HStack(spacing: 20) {
            Text("Sources")
                .font(.headline)
                .textCase(.uppercase)

            Spacer()

            SourceStatus(
                title: "Program",
                sourceName: controller.snapshot.programSource?.displayName ?? "—",
                color: .red
            )
            SourceStatus(
                title: controller.snapshot.transition.isInTransition
                    ? "Transition"
                    : "Preview",
                sourceName: controller.snapshot.previewSource?.displayName ?? "—",
                color: controller.snapshot.transition.isInTransition ? .red : .green
            )
        }
    }

    private var transitionsAreEnabled: Bool {
        controller.isConnected
            && controller.pendingTransition == nil
            && !controller.snapshot.transition.isInTransition
    }

    private func light(for input: UInt16) -> SourceLight {
        if controller.snapshot.transition.isInTransition,
           input == controller.snapshot.programInput
            || input == controller.snapshot.previewInput {
            return .program
        }

        if input == controller.snapshot.programInput {
            return .program
        }
        if input == controller.snapshot.previewInput {
            return .preview
        }
        return .none
    }
}

private enum SourceLight: Equatable {
    case none
    case program
    case preview

    var color: Color? {
        switch self {
        case .none:
            return nil
        case .program:
            return .red
        case .preview:
            return .green
        }
    }

    var accessibilityValue: String {
        switch self {
        case .none:
            return "Not selected"
        case .program:
            return "Program"
        case .preview:
            return "Preview"
        }
    }
}

private struct SourceStatus: View {
    let title: String
    let sourceName: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
            Text("\(title): \(sourceName)")
                .font(.headline)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SourceButton: View {
    let title: String
    let height: CGFloat
    let light: SourceLight
    let isPending: Bool
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: title == "BLACK" ? 20 : 36, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .foregroundStyle(foregroundStyle)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    if isPending {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                .green,
                                style: StrokeStyle(lineWidth: 4, dash: [9, 6])
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(light == .none ? [] : .isSelected)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var foregroundStyle: Color {
        if !isEnabled {
            return Color(uiColor: .secondaryLabel)
        }
        return light == .none ? .primary : .white
    }

    private var backgroundStyle: Color {
        if let color = light.color {
            return color
        }
        if isPending {
            return Color.green.opacity(0.24)
        }
        return Color(
            uiColor: isEnabled
                ? .secondarySystemGroupedBackground
                : .tertiarySystemFill
        )
    }

    private var accessibilityValue: String {
        if isPending {
            return "\(light.accessibilityValue), pending Preview"
        }
        return light.accessibilityValue
    }
}

private struct ControlButton: View {
    let title: String
    let isPending: Bool
    let isEnabled: Bool
    let background: Color
    let foreground: Color
    let blinks: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    @State private var isDimmed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isPending {
                    ProgressView()
                        .tint(foreground)
                }
                Text(title)
                    .font(.title2.bold())
            }
            .frame(width: 150, height: 66)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? (isDimmed ? 0.38 : 1) : 0.68)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(blinks ? "Fade to Black active" : "")
        .task(id: blinks) {
            isDimmed = false
            guard blinks else {
                return
            }

            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.35)) {
                    isDimmed.toggle()
                }
                do {
                    try await Task.sleep(for: .milliseconds(450))
                } catch {
                    return
                }
            }
        }
    }
}
