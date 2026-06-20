import SwiftUI

struct SettingsView: View {
    @Binding var isSignedIn: Bool
    @StateObject private var settings = UserSettings.shared
    @StateObject private var conn = ConnectionMonitor.shared

    @State private var agentId = APIClient.shared.agentId
    @State private var showSignOutConfirm = false
    #if DEBUG
    @State private var devHost = APIClient.storedDevHost
    @State private var endpointTick = 0
    #endif

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
                        Text("AiVery").tag("aivery")
                    } label: {
                        HStack { icon("circle.lefthalf.filled", tint: .indigo); Text("Appearance") }
                    }

                    Toggle(isOn: $settings.showThinking) {
                        HStack { icon("brain", tint: .teal); Text("Show thinking") }
                    }
                    Toggle(isOn: $settings.enableReasoning) {
                        HStack { icon("sparkles", tint: .purple); Text("Enable reasoning") }
                    }
                }

                // ── Visual effects ────────────────────────────────────────
                Section {
                    Toggle(isOn: $settings.showPlexus) {
                        HStack { icon("circle.hexagongrid.fill", tint: .blue); Text("Plexus background") }
                    }
                    Toggle(isOn: $settings.plexusMemoryEffects) {
                        HStack { icon("sparkle", tint: .orange); Text("Memory ripples") }
                    }
                    .disabled(!settings.showPlexus)
                } header: {
                    Text("Visual Effects")
                } footer: {
                    Text("The animated mesh and the gold/blue ripple bursts on memory events. Ripples are also turned off automatically when iOS Reduce Motion is enabled.")
                }

                // ── Connection ────────────────────────────────────────────
                Section {
                    Button {
                        Task { await conn.check() }
                    } label: {
                        HStack {
                            icon("antenna.radiowaves.left.and.right", tint: statusTint)
                            Text("Connection").foregroundStyle(.primary)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle().fill(statusTint).frame(width: 8, height: 8)
                                Text(conn.status.label).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        icon("server.rack", tint: .gray)
                        Text("Host")
                        Spacer()
                        Text(conn.host)
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                } footer: {
                    Text("Tap to re-test. Checks the memories API for your current host.")
                }

                #if DEBUG
                // ── Developer (Debug builds only) ─────────────────────────
                Section {
                    HStack {
                        icon("network", tint: .orange)
                        Text("API Host")
                        Spacer()
                        TextField("auto-detect", text: $devHost)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .foregroundStyle(.secondary)
                            .onSubmit { applyHost() }
                    }
                    HStack {
                        Button("Use Tailscale") { devHost = APIClient.defaultDevHost; applyHost() }
                            .font(.subheadline)
                        Spacer()
                        Button("Reset") { devHost = ""; applyHost() }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fabric  \(APIClient.shared.baseURL.absoluteString)")
                        Text("Cortex  \(APIClient.shared.cortexURL.absoluteString)")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .id(endpointTick)
                } header: {
                    Text("Developer — Local API")
                } footer: {
                    Text("Debug only. Points the app at your Mac's API (ports 5128/5127). Run ./run-api.sh local-tailscale + ./run-cortex.sh local-tailscale and join the same tailnet to use it remotely. Release builds always use api/cortex.aivery.systems.")
                }
                #endif

                // ── Account ───────────────────────────────────────────────
                Section {
                    Button(role: .destructive) { showSignOutConfirm = true } label: {
                        Text("Sign Out").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await conn.check() }
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

    // MARK: - Helpers

    private var statusTint: Color {
        switch conn.status {
        case .online:             return .green
        case .checking, .unknown: return .yellow
        case .unauthorized:       return .orange
        case .offline:            return .red
        }
    }

    #if DEBUG
    private func applyHost() {
        APIClient.shared.setDevHost(devHost)
        devHost = APIClient.storedDevHost   // reflect normalized/cleared value
        endpointTick += 1                   // refresh the endpoint readout
        Task { await conn.check() }         // re-test against the new host
    }
    #endif

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
