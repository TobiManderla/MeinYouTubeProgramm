import SwiftUI

struct GlobalSettingsView: View {
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss

    @State private var apiKey    = ""
    @State private var pinEnabled = false
    @State private var pin       = ""
    @State private var ccEnabled = false
    @State private var skipEnabled = false

    @State private var isTesting = false
    @State private var testResult: TestResult? = nil

    enum TestResult { case ok, fail(String) }

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                pinSection
                subtitleSection
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern", action: save).fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            apiKey     = store.settings.apiKey
            pinEnabled = store.settings.pinEnabled
            pin        = store.settings.pin
            ccEnabled  = store.settings.ccEnabled
            skipEnabled = store.settings.skipEnabled
        }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        Section {
            HStack {
                SecureField("AIzaSy…", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: apiKey) { _, _ in testResult = nil }
                resultIcon
            }

            Button {
                Task { await testKey() }
            } label: {
                if isTesting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("API-Key testen", systemImage: "network")
                }
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)

            if case .fail(let msg) = testResult {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("YouTube Data API-Key")
        } footer: {
            Text("Benoetigt zum Laden von Kanalinhalten. Kostenloser Key ueber die Google Cloud Console.")
        }
    }

    @ViewBuilder
    private var resultIcon: some View {
        switch testResult {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .fail:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    private var pinSection: some View {
        Section {
            Toggle("Eltern-PIN aktivieren", isOn: $pinEnabled)
            if pinEnabled {
                SecureField("4-stellige PIN", text: $pin)
                    .keyboardType(.numberPad)
            }
        } header: {
            Text("Kinderschutz")
        } footer: {
            Text("Der PIN schuetzt das Anlegen und Bearbeiten von Sendern.")
        }
    }

    private var subtitleSection: some View {
        Section {
            Toggle("Untertitel anzeigen", isOn: $ccEnabled)
            Toggle("Weiter-Schaltfläche freigeben", isOn: $skipEnabled)
        } header: {
            Text("Wiedergabe")
        } footer: {
            Text("'Weiter' zeigt waehrend der Wiedergabe ein Vorschaubild des naechsten Videos – Kinder koennen damit das aktuelle Segment ueberspringen.")
        }
    }

    // MARK: - Actions

    private func save() {
        store.settings.apiKey     = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        store.settings.pinEnabled = pinEnabled
        store.settings.pin        = pin
        store.settings.ccEnabled  = ccEnabled
        store.settings.skipEnabled = skipEnabled
        store.save()
        dismiss()
    }

    @MainActor
    private func testKey() async {
        isTesting = true
        testResult = nil
        do {
            try await YouTubeAPI.testKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            testResult = .ok
        } catch {
            testResult = .fail(error.localizedDescription)
        }
        isTesting = false
    }
}
