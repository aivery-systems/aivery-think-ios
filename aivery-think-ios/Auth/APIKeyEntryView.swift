import SwiftUI

struct APIKeyEntryView: View {
    @Binding var isSignedIn: Bool
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Logo / wordmark
                VStack(spacing: 6) {
                    Text("aivery")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("think")
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("Enter your API key")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("You can find your API key in Settings inside the Aivery web app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Group {
                        if showKey {
                            TextField("ak_...", text: $apiKey)
                        } else {
                            SecureField("ak_...", text: $apiKey)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        HStack {
                            Spacer()
                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 12)
                            }
                        }
                    )

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button(action: continue_) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(apiKey.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func continue_() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        APIClient.shared.setApiKey(trimmed)
        Haptics.tapLight()
        withAnimation { isSignedIn = true }
    }
}
