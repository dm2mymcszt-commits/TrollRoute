import SwiftUI

struct AltitudeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: AltitudeSettings
    @ObservedObject var controller: AltitudeController
    @State private var custom = false
    @State private var input = ""

    var body: some View {
        if #available(iOS 16.0, *) {
            editor.presentationDetents([.medium, .large])
        } else { editor }
    }

    private var editor: some View {
        NavigationView {
            Form {
                Section("Current setting") {
                    if controller.flightAltitude != nil {
                        valueRow("Flight altitude", controller.currentMeters.map(meters) ?? "Unknown")
                        Text("The flight profile controls altitude while flying. Your saved setting applies again after landing.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    valueRow("Mode", settings.profile.mode == .automatic ? "Automatic" : "Custom")
                    if settings.profile.mode == .custom {
                        valueRow("Altitude", meters(settings.profile.customMeters))
                    } else {
                        valueRow("Ground elevation", controller.currentMeters.map(meters) ?? "Unknown")
                        Text(controller.isActive
                             ? "Terrain estimates refresh as you move. If a lookup is unavailable, altitude is reported as unknown."
                             : "Ground elevation is looked up when you set a simulated location.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Section {
                    Picker("Altitude", selection: $custom) {
                        Text("Automatic").tag(false)
                        Text("Custom").tag(true)
                    }.pickerStyle(.segmented)
                    if custom {
                        HStack {
                            Button("− / +") {
                                if input.hasPrefix("-") { input.removeFirst() }
                                else { input = "-" + input.replacingOccurrences(of: "+", with: "") }
                            }.accessibilityLabel("Change altitude sign")
                            TextField("Altitude", text: $input)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .accessibilityLabel("Custom altitude in meters")
                            Text("m").foregroundColor(.secondary)
                        }
                        if !input.isEmpty && AltitudeProfile.parse(input) == nil {
                            Text("Enter a number, for example 12,5 or -20.").font(.caption).foregroundColor(.red)
                        }
                        Button("Apply custom altitude") {
                            if let value = AltitudeProfile.parse(input) { settings.setCustom(value) }
                        }.disabled(AltitudeProfile.parse(input) == nil)
                    }
                    Button("Reset to Automatic") {
                        settings.reset(); custom = false; input = ""
                    }
                } footer: {
                    Text("Saved for simulated locations. During a flight, changes apply after landing; otherwise they apply immediately.")
                }
            }
            .navigationTitle("Altitude").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                custom = settings.profile.mode == .custom
                input = custom ? String(settings.profile.customMeters) : ""
            }
            .onChange(of: custom) { value in if !value { settings.reset() } }
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary) }
    }

    private func meters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " m"
    }
}
