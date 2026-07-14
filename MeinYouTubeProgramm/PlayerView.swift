import SwiftUI
import Combine

struct PlayerView: View {
    let sender: Sender
    @Environment(AppStore.self) var store
    @Environment(\.dismiss) var dismiss

    @StateObject private var coordinator = YouTubePlayerCoordinator()
    @State private var scheduler: ProgramScheduler
    @State private var phase: Phase = .loading
    @State private var currentPlan: PlayPlan? = nil
    @State private var nextPlan: PlayPlan? = nil
    @State private var isPaused = false
    @State private var consecutiveErrors = 0
    @State private var interstitialTask: Task<Void, Never>? = nil

    // Skip-Vorschau
    @State private var skipVisible = false
    @State private var skipAutoHideTask: Task<Void, Never>? = nil

    // Weiterschauen-Countdown (fullVideo-Kanäle)
    @State private var showKeepWatching = false
    @State private var keepWatchingCountdown = 5
    @State private var keepWatchingTask: Task<Void, Never>? = nil
    @State private var extendedPlay = false

    private static let maxErrors = 3
    private static let interstitialSec: UInt64 = 3_500_000_000

    private let pollTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    enum Phase { case loading, playing, interstitial, sessionEnd, technicalError }

    init(sender: Sender) {
        self.sender = sender
        self._scheduler = State(initialValue: ProgramScheduler(sender: sender))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            YouTubePlayerRepresentable(coordinator: coordinator).ignoresSafeArea()
            overlays
        }
        .statusBarHidden()
        .onReceive(pollTimer) { _ in poll() }
        .onAppear { setup() }
        .onDisappear {
            interstitialTask?.cancel()
            skipAutoHideTask?.cancel()
            keepWatchingTask?.cancel()
            coordinator.pause()
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        switch phase {
        case .loading:
            Color.black.opacity(0.7).ignoresSafeArea()
            ProgressView().tint(.white).scaleEffect(1.5)

        case .playing:
            VStack(spacing: 0) {
                // Oben: Schließen + Pause
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title).foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Button { togglePause() } label: {
                        Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.title).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(24)

                Spacer()

                // Unten: Weiterschauen-Balken (fullVideo) und/oder Skip-Vorschau
                VStack(spacing: 8) {
                    // Weiterschauen-Balken: slides in from right
                    if showKeepWatching {
                        keepWatchingBar
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    // Skip-Vorschau oder Recall-Handle
                    if store.settings.skipEnabled, let next = nextPlan, !showKeepWatching {
                        ZStack(alignment: .leading) {
                            if skipVisible {
                                skipCard(next: next)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                            // Recall-Handle: immer sichtbar wenn Karte weg
                            if !skipVisible {
                                Button { recallSkipCard() } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                        Text("Weiter")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.white.opacity(0.55))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(.leading, 24)
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.4), value: skipVisible)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: showKeepWatching)
                .padding(.bottom, 28)
            }

        case .interstitial:
            if let ended = currentPlan {
                InterstitialCard(ended: ended, next: nextPlan, isError: consecutiveErrors > 0)
                    .transition(.opacity)
            }

        case .sessionEnd:
            SessionEndView(isError: false) { dismiss() }

        case .technicalError:
            SessionEndView(isError: true) { dismiss() }
        }
    }

    // MARK: - Weiterschauen-Balken

    private var keepWatchingBar: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(keepWatchingCountdown) / 5.0)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: keepWatchingCountdown)
                Text("\(keepWatchingCountdown)")
                    .font(.caption.bold()).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            Text("Segment endet gleich")
                .font(.caption).foregroundStyle(.white)

            Spacer()

            Button("Weiterschauen") { keepWatching() }
                .font(.caption.bold())
                .foregroundStyle(.orange)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.orange.opacity(0.2), in: Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    // MARK: - Skip-Vorschau

    @ViewBuilder
    private func skipCard(next: PlayPlan) -> some View {
        Button { play(next) } label: {
            HStack(spacing: 10) {
                AsyncImage(url: URL(string: next.thumb)) { img in
                    img.resizable().aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Naechstes Video")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(next.title)
                        .font(.caption).foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "forward.end.fill")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Setup

    private func setup() {
        coordinator.onReady = { startFirst() }
        coordinator.onStateChange = { state in
            if state == 0 { segmentEnded() }
        }
        coordinator.onError = { _ in handleError() }
        coordinator.loadHTML()
    }

    // MARK: - Playback control

    private func startFirst() {
        guard let plan = scheduler.pickNext() else { phase = .sessionEnd; return }
        play(plan)
    }

    private func play(_ plan: PlayPlan) {
        interstitialTask?.cancel()
        keepWatchingTask?.cancel()
        currentPlan = plan
        nextPlan = scheduler.pickNext()
        isPaused = false
        extendedPlay = false
        showKeepWatching = false
        coordinator.loadVideo(videoId: plan.videoId, startSec: plan.startSec,
                              ccEnabled: store.settings.ccEnabled)
        withAnimation { phase = .playing }
        startSkipAutoHide()
    }

    private func togglePause() {
        isPaused.toggle()
        isPaused ? coordinator.pause() : coordinator.resume()
    }

    // MARK: - Skip Auto-Hide

    private func startSkipAutoHide() {
        skipAutoHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { skipVisible = true }
        skipAutoHideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) { skipVisible = false }
        }
    }

    private func recallSkipCard() {
        startSkipAutoHide()
    }

    // MARK: - Weiterschauen

    private func startKeepWatchingCountdown() {
        showKeepWatching = true
        keepWatchingCountdown = 5
        keepWatchingTask?.cancel()
        keepWatchingTask = Task {
            for i in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                keepWatchingCountdown = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            segmentEnded()
        }
    }

    private func keepWatching() {
        keepWatchingTask?.cancel()
        extendedPlay = true
        withAnimation(.easeInOut(duration: 0.3)) { showKeepWatching = false }
    }

    // MARK: - Polling (400 ms)

    private func poll() {
        guard phase == .playing, !isPaused, let plan = currentPlan else { return }
        coordinator.getCurrentTime { t in
            guard self.phase == .playing, t > 0 else { return }

            // Weiterschauen-Prompt: 5.5s vor Segment-Ende bei fullVideo-Kanälen
            if plan.fullVideo && !self.extendedPlay && !self.showKeepWatching
                && t >= plan.endSec - 5.5 {
                self.startKeepWatchingCountdown()
            }

            // Normales Segment-Ende (deaktiviert wenn Weiterschauen gewählt)
            if !self.extendedPlay && t >= plan.endSec - 0.5 {
                self.segmentEnded()
            }
        }
    }

    // MARK: - Segment end

    private func segmentEnded() {
        guard phase == .playing || phase == .loading else { return }
        consecutiveErrors = 0
        keepWatchingTask?.cancel()
        showKeepWatching = false
        extendedPlay = false
        withAnimation { phase = .interstitial }
        scheduleAfterInterstitial(next: nextPlan, delay: Self.interstitialSec)
    }

    private func scheduleAfterInterstitial(next: PlayPlan?, delay: UInt64) {
        interstitialTask?.cancel()
        interstitialTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            if let n = next { play(n) } else { withAnimation { phase = .sessionEnd } }
        }
    }

    // MARK: - Error handling

    private func handleError() {
        guard phase == .playing || phase == .loading else { return }
        consecutiveErrors += 1
        if consecutiveErrors >= Self.maxErrors {
            withAnimation { phase = .technicalError }; return
        }
        keepWatchingTask?.cancel()
        showKeepWatching = false
        withAnimation { phase = .interstitial }
        scheduleAfterInterstitial(next: nextPlan, delay: 2_000_000_000)
    }
}

// MARK: - Interstitial-Karte (3.5 s zwischen Segmenten)

struct InterstitialCard: View {
    let ended: PlayPlan
    let next: PlayPlan?
    var isError: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(isError ? "Video nicht verfuegbar – wird uebersprungen"
                     : next == nil ? "Ende" : "Wird fortgesetzt \u{2026}")
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(isError ? .orange : .secondary)

                AsyncImage(url: URL(string: ended.thumb)) { img in
                    img.resizable().aspectRatio(16/9, contentMode: .fit)
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.25)).aspectRatio(16/9, contentMode: .fit)
                }
                .cornerRadius(8)
                .frame(maxWidth: 280)

                Text(ended.title)
                    .font(.subheadline).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.center)

                if let next {
                    Divider().background(.white.opacity(0.15)).padding(.vertical, 4)
                    Text("Gleich geht's weiter mit")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(next.title)
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1).multilineTextAlignment(.center)
                }
            }
            .padding(28)
        }
    }
}

// MARK: - Sitzungsende / Technischer Fehler

struct SessionEndView: View {
    let isError: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(isError ? "📡" : "🎬").font(.system(size: 64))
                Text(isError ? "Kein Empfang" : "Sitzung beendet")
                    .font(.title2.bold()).foregroundStyle(.white)
                Text(isError
                     ? "Zu viele Fehler hintereinander. Bitte spaeter erneut versuchen."
                     : "Die Sendezeit ist vorbei.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Zurueck", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
    }
}
