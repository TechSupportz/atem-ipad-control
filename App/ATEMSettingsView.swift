import SwiftUI

@MainActor
struct ATEMSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let controller: ATEMController
    @State private var draftHost: String

    init(controller: ATEMController) {
        self.controller = controller
        _draftHost = State(initialValue: controller.host)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ATEM IP address", text: $draftHost)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("atemHostField")
                } header: {
                    Text("Connection")
                } footer: {
                    Text("The iPad connects directly to UDP port 9910. Internet access is not required.")
                }

                Section("Diagnostics") {
                    LabeledContent("Status", value: controller.statusTitle)
                    LabeledContent(
                        "Initial sync",
                        value: controller.snapshot.isInitialSyncComplete ? "Complete" : "Not complete"
                    )
                    LabeledContent(
                        "Commands received",
                        value: String(controller.initialStateCommandCount)
                    )
                    LabeledContent(
                        "Program",
                        value: controller.snapshot.programSource?.displayName ?? "—"
                    )
                    LabeledContent(
                        "Preview",
                        value: controller.snapshot.previewSource?.displayName ?? "—"
                    )
                    LabeledContent(
                        "Transition",
                        value: controller.snapshot.transition.isInTransition
                            ? "In progress"
                            : "Idle"
                    )
                    LabeledContent(
                        "Fade to black",
                        value: fadeToBlackStatus
                    )
                }
            }
            .navigationTitle("ATEM Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        controller.updateHost(draftHost)
                        dismiss()
                    }
                    .disabled(!isValidIPv4Address(draftHost))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func isValidIPv4Address(_ value: String) -> Bool {
        let components = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else {
            return false
        }

        return components.allSatisfy { component in
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  let byte = UInt8(component)
            else {
                return false
            }
            return String(byte) == component || component == "0"
        }
    }

    private var fadeToBlackStatus: String {
        if controller.snapshot.fadeToBlack.isInTransition {
            return "In progress"
        }
        return controller.snapshot.fadeToBlack.isFullyBlack ? "Black" : "Off"
    }
}
