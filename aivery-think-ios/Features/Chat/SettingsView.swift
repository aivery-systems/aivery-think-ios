import SwiftUI

struct SettingsView: View {
    @Binding var isSignedIn: Bool
    @StateObject private var settings = UserSettings.shared

    @State private var agentId = APIClient.shared.agentId
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // ── Drill-down pages ──────────────────────────────────────
                Section {
                    NavigationLink {
                        ProviderSettingsView()
                    } label: {
                        row("Model Provider", icon: "cpu", tint: .blue, value: providerSummary)
                    }
                    NavigationLink {
                        PersonaSettingsView()
                    } label: {
                        row("Persona", icon: "theatermasks.fill", tint: .purple, value: personaSummary)
                    }
                }

                // ── Inline general settings ───────────────────────────────
                Section("General") {
                    HStack {
                        icon("person.fill", tint: .gray)
                        Text("Agent ID")
                        Spacer()
                        TextField("default", text: $agentId)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.secondary)
                            .onChange(of: agentId) {
                                APIClient.shared.agentId = agentId
                                KeychainHelper.save(key: "agentId", value: agentId)
                            }
                    }

                    Picker(selection: $settings.colorScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    } label: {
                        HStack { icon("circle.lefthalf.filled", tint: .indigo); Text("Appearance") }
                    }

                    Toggle(isOn: $settings.showThinking) {
                        HStack { icon("brain", tint: .teal); Text("Show thinking") }
                    }
                }

                // ── Account ───────────────────────────────────────────────
                Section {
                    Button(role: .destructive) { showSignOutConfirm = true } label: {
                        Text("Sign Out").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    APIClient.shared.clearApiKey()
                    withAnimation { isSignedIn = false }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your API key will be removed from this device.")
            }
        }
    }

    // MARK: - Row helpers

    private var providerSummary: String {
        guard let ps = ProviderSettingsLocal.load(), ps.enabled, !ps.baseUrl.isEmpty else { return "Default" }
        return ps.model.isEmpty ? ps.type.capitalized : ps.model
    }

    private var personaSummary: String {
        (ChatPrefsLocal.systemPrompt.isEmpty && ChatPrefsLocal.chatStyle.isEmpty) ? "Default" : "Custom"
    }

    @ViewBuilder
    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func row(_ title: String, icon name: String, tint: Color, value: String) -> some View {
        HStack {
            icon(name, tint: tint)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).font(.subheadline).lineLimit(1)
        }
    }
}
