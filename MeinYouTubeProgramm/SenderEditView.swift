import SwiftUI

struct SenderEditView: View {
    let original: Sender
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss

    @State private var draft: Sender
    @State private var logLines: [String] = []
    @State private var isLoading = false
    @State private var showDeleteConfirm = false

    private var isNew: Bool { !store.senders.contains { $0.id == original.id } }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.isReady }

    init(sender: Sender) {
        self.original = sender
        self._draft = State(initialValue: sender)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                channelSection
                settingsSection
                daypartSection
                if !isNew { deleteSection }
            }
            .navigationTitle(isNew ? "Neuer Sender" : draft.name.isEmpty ? "Sender bearbeiten" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Sender löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { store.deleteSender(id: draft.id); dismiss() }
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Sender-Name") {
            TextField("z.B. Kinderkanal, Sport, Natur …", text: $draft.name)
        }
    }

    private var channelSection: some View {
        Section {
            TextEditor(text: $draft.channelsRaw)
                .frame(minHeight: 90)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                Task { await loadChannels() }
            } label: {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Kanäle laden", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isLoading || draft.channelsRaw.trimmingCharacters(in: .whitespaces).isEmpty || store.settings.apiKey.isEmpty)

            if store.settings.apiKey.isEmpty {
                Label("Bitte zuerst API-Key in Einstellungen eintragen.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !logLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(line.contains("✗") ? .red : .secondary)
                    }
                }
            }

            ForEach(draft.resolvedChannels) { ch in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.title).font(.subheadline)
                            Text("\(ch.videos.count) Videos").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Toggle("Ganze Videos erlauben", isOn: Binding(
                        get: { draft.fullVideoChannelIds.contains(ch.id) },
                        set: { on in
                            if on { draft.fullVideoChannelIds.insert(ch.id) }
                            else  { draft.fullVideoChannelIds.remove(ch.id) }
                        }
                    ))
                    .font(.caption)
                    .tint(.orange)
                }
            }
        } header: {
            Text("Kanal-Pool")
        } footer: {
            Text("Einen Kanal pro Zeile: @handle, youtube.com/@handle, Kanal-ID (UCxxx…) oder vollständige Kanal-URL.")
        }
    }

    private var settingsSection: some View {
        Section("Programm-Einstellungen") {
            LabeledSlider(label: "Häppchen-Länge",       value: $draft.segmentMin,      range: 1...30,    step: 1,   display: { "\(Int($0)) Min" })
            LabeledSlider(label: "Sitzungs-Länge",       value: $draft.sessionMin,      range: 10...120,  step: 5,   display: { "\(Int($0)) Min" })
            LabeledSlider(label: "Fortsetzungs-Chance",  value: $draft.continuationProb, range: 0...1,    step: 0.05, display: { "\(Int($0 * 100)) %" })
            LabeledSlider(label: "Max. Videos in Queue",
                value: Binding(get: { Double(draft.queueMax)  }, set: { draft.queueMax  = Int($0) }),
                range: 1...10, step: 1, display: { "\(Int($0))" })
            LabeledSlider(label: "Kanal-Cooldown",
                value: Binding(get: { Double(draft.cooldownN) }, set: { draft.cooldownN = Int($0) }),
                range: 0...10, step: 1, display: { "\(Int($0))" })
            LabeledSlider(label: "Cache-Dauer",           value: $draft.cacheHours,     range: 6...48,    step: 6,   display: { "\(Int($0)) Std" })
        }
    }

    private var daypartSection: some View {
        Section {
            Toggle("Zeitfenster aktivieren", isOn: $draft.daypartEnabled)
            if draft.daypartEnabled {
                HStack {
                    Text("Von")
                    Spacer()
                    TimePickerField(value: $draft.daypartStart)
                }
                HStack {
                    Text("Bis")
                    Spacer()
                    TimePickerField(value: $draft.daypartEnd)
                }
            }
        } header: {
            Text("Tageszeit-Empfehlung")
        } footer: {
            Text("Zeigt ein 'Jetzt empfohlen'-Badge auf der Sender-Kachel wenn die Uhrzeit im gewaehlten Fenster liegt.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Sender löschen", systemImage: "trash").frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        var s = draft
        s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew { store.addSender(s) } else { store.updateSender(s) }
        dismiss()
    }

    @MainActor
    private func loadChannels() async {
        isLoading = true
        logLines = []
        draft.resolvedChannels = []
        draft.cachedAt = 0
        do {
            draft.resolvedChannels = try await YouTubeAPI.resolveSenderChannels(
                apiKey: store.settings.apiKey,
                channelsRaw: draft.channelsRaw,
                maxPerChannel: draft.maxPerChannel,
                log: { line in logLines.append(line) }
            )
            draft.cachedAt = Date().timeIntervalSince1970 * 1000
        } catch {
            logLines.append("Fehler: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Helpers

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(display(value)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }
}

struct TimePickerField: View {
    @Binding var value: String   // "HH:MM"

    private var asDate: Date {
        let p = value.split(separator: ":").compactMap { Int($0) }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = p.first ?? 0; c.minute = p.count > 1 ? p[1] : 0
        return Calendar.current.date(from: c) ?? Date()
    }

    var body: some View {
        DatePicker("", selection: Binding(
            get: { asDate },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                value = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
    }
}
