import ATEMKit
import SwiftUI

@MainActor
struct SwitcherControlView: View {
    let controller: ATEMController
    let usesCompactLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactLayout ? 18 : 22) {
            busHeader

            ViewThatFits(in: .horizontal) {
                wideControlLayout
                    .frame(minWidth: 820)
                compactControlLayout
            }
            .frame(maxHeight: .infinity)
        }
        .padding(usesCompactLayout ? 16 : 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            .background,
            in: RoundedRectangle(cornerRadius: usesCompactLayout ? 20 : 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: usesCompactLayout ? 20 : 24)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var busHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                switcherTitle

                Spacer(minLength: 16)

                tallyStatuses
            }
            .frame(minWidth: 620)

            VStack(alignment: .leading, spacing: 14) {
                switcherTitle
                tallyStatuses
            }
        }
    }

    private var switcherTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Switcher")
                .font(.title2.bold())
            Text("Tap a source to stage it")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var tallyStatuses: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                programTally
                previewTally
            }

            VStack(alignment: .leading, spacing: 10) {
                programTally
                previewTally
            }
        }
    }

    private var programTally: some View {
        TallyStatus(
            title: "Program",
            sourceName: controller.snapshot.programSource?.displayName ?? "—",
            color: .red
        )
    }

    private var previewTally: some View {
        TallyStatus(
            title: controller.snapshot.transition.isInTransition
                ? "Transition"
                : "Preview",
            sourceName: controller.snapshot.previewSource?.displayName ?? "—",
            color: controller.snapshot.transition.isInTransition ? .red : .green
        )
    }

    private var wideControlLayout: some View {
        HStack(spacing: 16) {
            sourceControls

            Divider()

            takeControls(axis: .vertical)
                .frame(width: 188)
        }
        .frame(maxHeight: .infinity)
    }

    private var compactControlLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            sourceControls
            Divider()
            ViewThatFits(in: .horizontal) {
                takeControls(axis: .horizontal)
                    .frame(minWidth: 440)
                takeControls(axis: .vertical)
            }
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Stage")

            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ForEach(UInt16(1)...UInt16(4), id: \.self) { input in
                            inputButton(input)
                        }
                    }

                    blackButton(isCompact: true)
                        .frame(maxWidth: 196)
                }
                .frame(minWidth: 560)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible())
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(UInt16(1)...UInt16(4), id: \.self) { input in
                        inputButton(input)
                    }

                    blackButton(isCompact: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func inputButton(_ input: UInt16) -> some View {
        SourceButton(
            title: String(input),
            neutralLabel: "Input",
            light: light(for: input),
            isPending: controller.pendingPreviewInput == input,
            isEnabled: controller.isConnected,
            accessibilityLabel: "Input \(input)",
            accessibilityIdentifier: "input\(input)Button"
        ) {
            controller.selectPreviewInput(input)
        }
    }

    private func blackButton(isCompact: Bool) -> some View {
        SourceButton(
            title: "Black",
            neutralLabel: "Source",
            light: light(for: ATEMVideoSource.black.rawValue),
            isPending: controller.pendingPreviewInput
                == ATEMVideoSource.black.rawValue,
            isEnabled: controller.isConnected,
            isCompact: isCompact,
            accessibilityLabel: "Black",
            accessibilityIdentifier: "blackButton"
        ) {
            controller.selectPreviewInput(ATEMVideoSource.black.rawValue)
        }
    }

    @ViewBuilder
    private func takeControls(axis: Axis) -> some View {
        let cut = ControlButton(
            title: "CUT",
            detail: "Take now",
            isPending: controller.pendingTransition == .cut,
            isEnabled: transitionsAreEnabled,
            background: Color(red: 0.25, green: 0.27, blue: 0.30),
            foreground: .white,
            blinks: false,
            accessibilityValue: controller.pendingTransition == .cut
                ? "Cut pending"
                : "Take Preview immediately",
            accessibilityIdentifier: "cutButton"
        ) {
            controller.performTransition(.cut)
        }

        let auto = ControlButton(
            title: "AUTO",
            detail: "Transition",
            isPending: controller.pendingTransition == .auto
                || controller.snapshot.transition.isInTransition,
            isEnabled: transitionsAreEnabled,
            background: .blue,
            foreground: .white,
            blinks: false,
            accessibilityValue: controller.snapshot.transition.isInTransition
                ? "Auto transition in progress"
                : "Take Preview with the configured transition",
            accessibilityIdentifier: "autoButton"
        ) {
            controller.performTransition(.auto)
        }

        let isFadeActive = controller.snapshot.fadeToBlack.isFullyBlack
            || controller.snapshot.fadeToBlack.isInTransition
        let ftb = ControlButton(
            title: "FTB",
            detail: controller.snapshot.fadeToBlack.isFullyBlack ? "Active" : "Fade to black",
            isPending: controller.isFadeToBlackPending
                || controller.snapshot.fadeToBlack.isInTransition,
            isEnabled: controller.isConnected
                && !controller.isFadeToBlackPending
                && !controller.snapshot.fadeToBlack.isInTransition,
            background: isFadeActive
                ? .red
                : Color(uiColor: .secondarySystemGroupedBackground),
            foreground: isFadeActive ? .white : .primary,
            blinks: controller.snapshot.fadeToBlack.isFullyBlack,
            accessibilityValue: controller.snapshot.fadeToBlack.isFullyBlack
                ? "Fade to Black active"
                : "Fade Program to black",
            accessibilityIdentifier: "fadeToBlackButton"
        ) {
            controller.performFadeToBlack()
        }

        if axis == .vertical {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Take")
                cut.frame(maxHeight: .infinity)
                auto.frame(maxHeight: .infinity)
                ftb.frame(maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Take")
                HStack(spacing: 12) {
                    cut
                    auto
                    ftb
                }
            }
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
            return .transition
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

private enum SwitcherMotion {
    static let warningPulse = Animation.linear(duration: 0.18)
    static let warningPulseInterval = Duration.milliseconds(360)
    static let warningDimOpacity = 0.35
    static let press = Animation.timingCurve(
        0.23,
        1,
        0.32,
        1,
        duration: 0.12
    )
    static let stateChange = Animation.timingCurve(
        0.23,
        1,
        0.32,
        1,
        duration: 0.12
    )
}

private enum SourceLight: Equatable {
    case none
    case program
    case preview
    case transition

    var color: Color? {
        switch self {
        case .none:
            return nil
        case .program, .transition:
            return .red
        case .preview:
            return .green
        }
    }

    var shortLabel: String? {
        switch self {
        case .none:
            return nil
        case .program:
            return "PGM"
        case .preview:
            return "PVW"
        case .transition:
            return "TAKE"
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
        case .transition:
            return "Transition in progress"
        }
    }
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

private struct TallyStatus: View {
    let title: String
    let sourceName: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 5, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(sourceName)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(minWidth: 88, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct SourceButton: View {
    let title: String
    let neutralLabel: String
    let light: SourceLight
    let isPending: Bool
    let isEnabled: Bool
    var isCompact = false
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .title) private var regularHeight: CGFloat = 124
    @ScaledMetric(relativeTo: .title2) private var compactHeight: CGFloat = 62

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(statusLabel)
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    if light != .none || isPending {
                        Circle()
                            .fill(.white.opacity(0.92))
                            .frame(width: 7, height: 7)
                    }
                }
                .opacity(isEnabled ? 0.9 : 0.55)

                if !isCompact {
                    Spacer(minLength: 2)
                }

                Text(title)
                    .font(
                        isCompact
                            ? .system(.title3, design: .rounded, weight: .bold)
                            : .system(.largeTitle, design: .rounded, weight: .bold)
                    )
                    .lineLimit(1)

                if !isCompact {
                    Spacer(minLength: 2)
                }
            }
            .padding(.horizontal, isCompact ? 16 : 18)
            .padding(.vertical, isCompact ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                minHeight: isCompact ? compactHeight : regularHeight,
                maxHeight: isCompact ? nil : .infinity
            )
            .foregroundStyle(foregroundStyle)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundStyle)
                    .animation(SwitcherMotion.stateChange, value: light)
                    .animation(SwitcherMotion.stateChange, value: isPending)
            }
            .overlay(alignment: .top) {
                if isPending {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.green)
                        .frame(height: 7)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(borderStyle, lineWidth: light == .none ? 1 : 2)
                    .animation(SwitcherMotion.stateChange, value: light)
                    .animation(SwitcherMotion.stateChange, value: isPending)
            }
        }
        .buttonStyle(PanelButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(light == .none ? [] : .isSelected)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var statusLabel: String {
        if isPending {
            return "NEXT"
        }
        return light.shortLabel ?? neutralLabel.uppercased()
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
            return Color.green.opacity(0.20)
        }
        return Color(
            uiColor: isEnabled
                ? .secondarySystemGroupedBackground
                : .tertiarySystemFill
        )
    }

    private var borderStyle: Color {
        if isPending {
            return .green
        }
        return light.color?.opacity(0.9) ?? .primary.opacity(0.08)
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
    let detail: String
    let isPending: Bool
    let isEnabled: Bool
    let background: Color
    let foreground: Color
    let blinks: Bool
    let accessibilityValue: String
    let accessibilityIdentifier: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 60
    @State private var warningBackgroundOpacity = 1.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline.bold())
                    Text(detail)
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                ZStack {
                    if isPending {
                        ProgressView()
                            .tint(foreground)
                            .transition(.opacity)
                    }
                }
                .frame(width: 20, height: 20)
                .animation(SwitcherMotion.press, value: isPending)
            }
            .padding(.horizontal, 16)
            .frame(
                maxWidth: .infinity,
                minHeight: minimumHeight,
                maxHeight: .infinity,
                alignment: .leading
            )
            .foregroundStyle(foreground)
            .background(
                background.opacity(warningBackgroundOpacity),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
            }
        }
        .buttonStyle(PanelButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier)
        .task(id: blinks && !reduceMotion) {
            warningBackgroundOpacity = 1
            guard blinks && !reduceMotion else {
                return
            }

            do {
                while !Task.isCancelled {
                    withAnimation(SwitcherMotion.warningPulse) {
                        warningBackgroundOpacity = SwitcherMotion.warningDimOpacity
                    }
                    try await Task.sleep(for: SwitcherMotion.warningPulseInterval)
                    withAnimation(SwitcherMotion.warningPulse) {
                        warningBackgroundOpacity = 1
                    }
                    try await Task.sleep(for: SwitcherMotion.warningPulseInterval)
                }
            } catch {
                return
            }
        }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(SwitcherMotion.press, value: configuration.isPressed)
    }
}
