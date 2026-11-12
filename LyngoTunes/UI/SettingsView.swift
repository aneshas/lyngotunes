import LyngoCore
import SwiftUI

/// Everything the app needs from its user: the two keys, the Spotify login, the language.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(SpotifySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showKey = false
    @State private var copied = false
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Picker(selection: $settings.targetLangCode) {
                        ForEach(Language.all) { language in
                            Text("\(language.flag)  \(language.name)").tag(language.code)
                        }
                    } label: {
                        Label("Translate lyrics to", systemImage: "character.bubble.fill")
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("settings.language")
                } header: {
                    Text("Language")
                } footer: {
                    Text("Each song is translated once per language and then kept on this phone. A new language means a new translation with your OpenAI key.")
                }

                Section {
                    LabeledContent("Client ID") {
                        TextField("paste here", text: $settings.spotifyClientID)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .disabled(session.isConnected)
                            .foregroundStyle(session.isConnected ? .secondary : .primary)
                            .accessibilityIdentifier("settings.clientID")
                    }
                    Button {
                        UIPasteboard.general.string = SpotifyAuth.redirectURI
                        copied = true
                    } label: {
                        LabeledContent("Redirect URI") {
                            HStack(spacing: 8) {
                                Text(SpotifyAuth.redirectURI).font(.system(.footnote, design: .monospaced))
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            }
                            .foregroundStyle(copied ? Theme.amber : .secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint("Copies the redirect URI")
                    .accessibilityIdentifier("settings.redirect")

                    if session.isConnected {
                        HStack {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.amber)
                            Spacer()
                            Button("Disconnect", role: .destructive) { session.disconnect() }
                                .accessibilityIdentifier("settings.disconnect")
                        }
                    } else {
                        Button {
                            Task { await session.login() }
                        } label: {
                            HStack {
                                Label("Sign in with Spotify", systemImage: "person.crop.circle.badge.checkmark")
                                if session.isLoggingIn { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(!settings.hasSpotifyClientID || session.isLoggingIn)
                        .accessibilityIdentifier("settings.signIn")
                    }
                    if let error = session.loginError {
                        Text(error).font(.footnote).foregroundStyle(Theme.coral)
                    }
                } header: {
                    Text("Spotify")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create an app in the Spotify developer dashboard (Web API), add the redirect URI above to it, and paste its Client ID here. No client secret is needed. Disconnect to change the Client ID. Controlling playback needs Spotify Premium.")
                        Link("Open developer.spotify.com/dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    }
                }

                Section {
                    LabeledContent("API key") {
                        HStack(spacing: 8) {
                            Group {
                                if showKey {
                                    TextField("sk-…", text: $settings.openAIKey)
                                } else {
                                    SecureField("sk-…", text: $settings.openAIKey)
                                }
                            }
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("settings.openAIKey")

                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(showKey ? "Hide key" : "Show key")
                        }
                    }
                    LabeledContent("Model") {
                        TextField(OpenAITranslator.defaultModel, text: $settings.openAIModel)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("settings.model")
                    }
                } header: {
                    Text("Translation · OpenAI")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your keys are stored in this phone's Keychain. The OpenAI key is sent only to OpenAI, together with the lyrics to translate.")
                        Link("Get a key at platform.openai.com", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    }
                }

                Section {
                    LabeledContent("Saved songs", value: "\(model.cachedSongs)")
                        .accessibilityIdentifier("settings.savedSongs")
                    Button("Delete saved lyrics and translations", role: .destructive) { confirmClear = true }
                        .disabled(model.cachedSongs == 0)
                } header: {
                    Text("On this phone")
                } footer: {
                    Text("LyngoTunes has no server and no account. Lyrics come from lrclib.net.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .scrollContentBackground(.hidden)
            .background(StageBackground(tint: Theme.defaultTint))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                        .accessibilityIdentifier("settings.done")
                }
            }
            .confirmationDialog("Delete all saved lyrics and translations?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await model.clearCache() } }
            } message: {
                Text("Songs will be fetched and translated again the next time they play.")
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.amber)
    }
}
