import SwiftUI

struct PersonaSettingsView: View {
    @State private var systemPrompt = ChatPrefsLocal.systemPrompt
    @State private var chatStyle = ChatPrefsLocal.chatStyle

    var body: some View {
        Form {
            Section {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 120)
                    .onChange(of: systemPrompt) { ChatPrefsLocal.systemPrompt = systemPrompt }
            } header: {
                Text("System Prompt")
            } footer: {
                Text("Base instruction injected into every chat.")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ChatFlavors.all) { flavor in
                            Button {
                                chatStyle = flavor.prompt
                                ChatPrefsLocal.chatStyle = flavor.prompt
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            } label: {
                                Text(flavor.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(chatStyle == flavor.prompt ? Color.accentColor : Color(.secondarySystemFill),
                                                in: Capsule())
                                    .foregroundStyle(chatStyle == flavor.prompt ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                TextEditor(text: $chatStyle)
                    .frame(minHeight: 80)
                    .onChange(of: chatStyle) { ChatPrefsLocal.chatStyle = chatStyle }
            } header: {
                Text("Chat Style")
            } footer: {
                Text("Tone, format, or constraints. Tap a flavor to fill, or write your own.")
            }

            if !systemPrompt.isEmpty || !chatStyle.isEmpty {
                Section {
                    Button(role: .destructive) {
                        systemPrompt = ""; chatStyle = ""
                        ChatPrefsLocal.systemPrompt = ""; ChatPrefsLocal.chatStyle = ""
                    } label: { Text("Clear persona") }
                }
            }
        }
        .navigationTitle("Persona")
        .navigationBarTitleDisplayMode(.inline)
    }
}
