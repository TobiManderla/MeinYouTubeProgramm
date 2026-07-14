import SwiftUI

// MARK: - Root

struct ContentView: View {
    @State private var store = AppStore()
    @State private var editingSender: Sender?
    @State private var playingSender: Sender?
    @State private var showSettings = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                scrollArea
                addButton
            }
            .navigationTitle("Mein Programm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Label("Einstellungen", systemImage: "gear")
                    }
                }
            }
        }
        .environment(store)
        .sheet(isPresented: $showSettings) {
            GlobalSettingsView().environment(store)
        }
        .sheet(item: $editingSender) { sender in
            SenderEditView(sender: sender).environment(store)
        }
        .fullScreenCover(item: $playingSender) { sender in
            PlayerView(sender: sender).environment(store)
        }
    }

    @ViewBuilder
    private var scrollArea: some View {
        if store.senders.isEmpty {
            emptyState
        } else {
            ScrollView {
                if store.settings.apiKey.isEmpty { apiKeyBanner }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.senders) { sender in
                        SenderTile(sender: sender) {
                            playingSender = sender
                        } onEdit: {
                            editingSender = sender
                        }
                    }
                }
                .padding()
            }
        }
    }

    private var apiKeyBanner: some View {
        Label("Kein API-Key hinterlegt – bitte in Einstellungen eintragen.", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    private var addButton: some View {
        Button { editingSender = Sender.makeNew() } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .padding(24)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Noch kein Sender")
                .font(.title2.bold())
            Text("Tippe auf + um deinen ersten Sender anzulegen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sender-Kachel

struct SenderTile: View {
    let sender: Sender
    let onPlay: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPlay) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sender.name.isEmpty ? "Unbenannter Sender" : sender.name)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(sender.resolvedChannels.count) Kanäle · \(sender.videoCount) Videos")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if sender.isRecommendedNow {
                        Label("Jetzt empfohlen", systemImage: "star.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Image(systemName: sender.isReady ? "play.fill" : "clock")
                        .font(.title3)
                        .foregroundStyle(sender.isReady ? .blue : .secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                .background(.regularMaterial)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!sender.isReady)

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }
}



#Preview {
    ContentView()
}
