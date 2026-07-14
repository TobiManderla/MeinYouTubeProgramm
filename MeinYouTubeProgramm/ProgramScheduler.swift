import Foundation

// MARK: - Data types

struct PlayPlan {
    var videoId: String
    var title: String
    var thumb: String
    var channelId: String
    var startSec: Double
    var endSec: Double
    var durationSec: Double
    var isFinal: Bool
    var fullVideo: Bool     // true = ganzes Video ohne Segment-Unterbrechung
}

private struct QueueItem {
    var videoId: String
    var title: String
    var thumb: String
    var channelId: String
    var resumeAtSec: Double
    var durationSec: Double
}

// MARK: - Scheduler (1:1 Port von tv-programm.html pickNext/enqueueContinuation)

final class ProgramScheduler {
    private let sender: Sender
    private let segmentSec: Double
    private let sessionEndAt: Date

    private var continuationQueue: [QueueItem] = []
    private var recentChannelIds: [String] = []
    private var playedPerChannel: [String: Set<String>] = [:]  // channelId -> Set<videoId>

    init(sender: Sender) {
        self.sender = sender
        self.segmentSec = sender.segmentMin * 60
        self.sessionEndAt = Date().addingTimeInterval(sender.sessionMin * 60)
    }

    var isSessionOver: Bool { Date() >= sessionEndAt }

    func pickNext() -> PlayPlan? {
        guard !isSessionOver else { return nil }

        let queueMax = sender.queueMax
        let contProb = sender.continuationProb
        let seg = segmentSec
        let plan: PlayPlan

        if !continuationQueue.isEmpty && Double.random(in: 0..<1) < contProb {
            // --- Continuation ---
            let item = continuationQueue.removeFirst()
            let isFullVideo = sender.fullVideoChannelIds.contains(item.channelId)
            let endSec = min(item.resumeAtSec + seg, item.durationSec)
            let isFinal = endSec >= item.durationSec - 1
            plan = PlayPlan(videoId: item.videoId, title: item.title, thumb: item.thumb,
                            channelId: item.channelId, startSec: item.resumeAtSec,
                            endSec: endSec, durationSec: item.durationSec,
                            isFinal: isFinal, fullVideo: isFullVideo)
        } else {
            // --- New video ---
            let channels = sender.resolvedChannels.filter { !$0.videos.isEmpty }
            guard !channels.isEmpty else { return nil }

            var eligible = channels.filter { !recentChannelIds.contains($0.id) }
            if eligible.isEmpty { eligible = channels }

            let channel = eligible.randomElement()!
            let isFullVideo = sender.fullVideoChannelIds.contains(channel.id)

            var played = playedPerChannel[channel.id] ?? []
            var remaining = channel.videos.filter { !played.contains($0.id) }
            if remaining.isEmpty { played.removeAll(); remaining = channel.videos }

            // If continuation queue is already full, prefer short videos
            var pool = remaining
            if continuationQueue.count >= queueMax {
                let short = remaining.filter { ($0.durationSec > 0 ? $0.durationSec : seg) <= seg }
                if !short.isEmpty { pool = short }
            }

            let video = pool.randomElement()!
            played.insert(video.id)
            playedPerChannel[channel.id] = played

            let dur = video.durationSec > 0 ? video.durationSec : seg
            let endSec = min(seg, dur)
            let isFinal = endSec >= dur - 1
            plan = PlayPlan(videoId: video.id, title: video.title, thumb: video.thumb,
                            channelId: channel.id, startSec: 0,
                            endSec: endSec, durationSec: dur,
                            isFinal: isFinal, fullVideo: isFullVideo)
        }

        // Update cooldown
        recentChannelIds.append(plan.channelId)
        let coolN = sender.cooldownN
        while recentChannelIds.count > coolN { recentChannelIds.removeFirst() }

        enqueueContinuation(plan, queueMax: queueMax)
        return plan
    }

    private func enqueueContinuation(_ plan: PlayPlan, queueMax: Int) {
        guard !plan.isFinal, continuationQueue.count < queueMax else { return }
        continuationQueue.append(QueueItem(
            videoId: plan.videoId, title: plan.title, thumb: plan.thumb,
            channelId: plan.channelId, resumeAtSec: plan.endSec, durationSec: plan.durationSec
        ))
    }
}
