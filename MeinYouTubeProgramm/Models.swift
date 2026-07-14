import Foundation

struct Video: Codable, Identifiable {
    var id: String
    var title: String
    var durationSec: Double
    var thumb: String
}

struct ResolvedChannel: Codable, Identifiable {
    var id: String
    var title: String
    var videos: [Video]
}

struct Sender: Codable, Identifiable {
    var id: String
    var name: String
    var channelsRaw: String
    var maxPerChannel: Int
    var cacheHours: Double
    var segmentMin: Double
    var sessionMin: Double
    var continuationProb: Double
    var queueMax: Int
    var cooldownN: Int
    var daypartEnabled: Bool
    var daypartStart: String        // "HH:MM"
    var daypartEnd: String          // "HH:MM"
    var resolvedChannels: [ResolvedChannel]
    var cachedAt: Double            // Unix-ms wie in der Web-Version
    var fullVideoChannelIds: Set<String>  // Kanäle, die ungekürzt abgespielt werden

    static func makeNew() -> Sender {
        Sender(
            id: UUID().uuidString,
            name: "",
            channelsRaw: "",
            maxPerChannel: 200,
            cacheHours: 12,
            segmentMin: 6,
            sessionMin: 45,
            continuationProb: 0.35,
            queueMax: 3,
            cooldownN: 3,
            daypartEnabled: false,
            daypartStart: "06:00",
            daypartEnd: "12:00",
            resolvedChannels: [],
            cachedAt: 0,
            fullVideoChannelIds: []
        )
    }

    var videoCount: Int {
        resolvedChannels.reduce(0) { $0 + $1.videos.count }
    }

    var isReady: Bool {
        resolvedChannels.contains { !$0.videos.isEmpty }
    }

    var isRecommendedNow: Bool {
        guard daypartEnabled else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let start = parseHHMM(daypartStart)
        let end   = parseHHMM(daypartEnd)
        return start <= end
            ? now >= start && now <= end
            : now >= start || now <= end   // Mitternachts-Wrap
    }

    private func parseHHMM(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }
}

struct AppSettings: Codable {
    var apiKey: String    = ""
    var pinEnabled: Bool  = false
    var pin: String       = ""
    var ccEnabled: Bool   = false
    var skipEnabled: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey     = try c.decodeIfPresent(String.self, forKey: .apiKey)    ?? ""
        pinEnabled = try c.decodeIfPresent(Bool.self,   forKey: .pinEnabled) ?? false
        pin        = try c.decodeIfPresent(String.self, forKey: .pin)        ?? ""
        ccEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .ccEnabled)  ?? false
        skipEnabled = try c.decodeIfPresent(Bool.self,  forKey: .skipEnabled) ?? false
    }
}

extension Sender {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self,            forKey: .id)
        name             = try c.decode(String.self,            forKey: .name)
        channelsRaw      = try c.decode(String.self,            forKey: .channelsRaw)
        maxPerChannel    = try c.decode(Int.self,               forKey: .maxPerChannel)
        cacheHours       = try c.decode(Double.self,            forKey: .cacheHours)
        segmentMin       = try c.decode(Double.self,            forKey: .segmentMin)
        sessionMin       = try c.decode(Double.self,            forKey: .sessionMin)
        continuationProb = try c.decode(Double.self,            forKey: .continuationProb)
        queueMax         = try c.decode(Int.self,               forKey: .queueMax)
        cooldownN        = try c.decode(Int.self,               forKey: .cooldownN)
        daypartEnabled   = try c.decode(Bool.self,              forKey: .daypartEnabled)
        daypartStart     = try c.decode(String.self,            forKey: .daypartStart)
        daypartEnd       = try c.decode(String.self,            forKey: .daypartEnd)
        resolvedChannels = try c.decode([ResolvedChannel].self, forKey: .resolvedChannels)
        cachedAt         = try c.decode(Double.self,            forKey: .cachedAt)
        fullVideoChannelIds = try c.decodeIfPresent(Set<String>.self, forKey: .fullVideoChannelIds) ?? []
    }
}
