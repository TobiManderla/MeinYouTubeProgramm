import Foundation

enum YTAPIError: LocalizedError {
    case noAPIKey, noChannels, channelNotFound(String), apiError(String)
    var errorDescription: String? {
        switch self {
        case .noAPIKey:              return "Kein API-Key hinterlegt – bitte in Einstellungen eintragen."
        case .noChannels:            return "Bitte mindestens einen Kanal eintragen."
        case .channelNotFound(let s): return "Kanal nicht gefunden: \(s)"
        case .apiError(let s):       return s
        }
    }
}

struct YouTubeAPI {
    private static let base = "https://www.googleapis.com/youtube/v3/"

    // MARK: - Channel entry parsing (1:1 aus tv-programm.html)

    private enum ChannelKind { case id, handle, legacy }
    private struct ChannelEntry { let kind: ChannelKind; let value: String }

    private static func extractEntry(from raw: String) -> ChannelEntry? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let urlPattern = #"youtube\.com/(channel/|c/|user/|@)([^/\?&\s]+)"#
        if let rx = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive),
           let m = rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let r1 = Range(m.range(at: 1), in: s),
           let r2 = Range(m.range(at: 2), in: s) {
            let prefix = String(s[r1]); let value = String(s[r2])
            if prefix == "channel/" { return ChannelEntry(kind: .id,     value: value) }
            if prefix == "@"        { return ChannelEntry(kind: .handle,  value: "@\(value)") }
            return                          ChannelEntry(kind: .legacy,  value: value)
        }
        if s.hasPrefix("@") { return ChannelEntry(kind: .handle, value: s) }
        if s.range(of: #"^UC[0-9A-Za-z_-]{20,}$"#, options: .regularExpression) != nil {
            return ChannelEntry(kind: .id, value: s)
        }
        return ChannelEntry(kind: .handle, value: "@\(s)")
    }

    // MARK: - Low-level GET

    private static func get(_ path: String, params: [String: String], apiKey: String) async throws -> Any {
        var comps = URLComponents(string: base + path)!
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "key", value: apiKey))
        comps.queryItems = items
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse else { throw YTAPIError.apiError("Netzwerkfehler") }
        let json = try JSONSerialization.jsonObject(with: data)
        if http.statusCode != 200,
           let d = json as? [String: Any],
           let e = d["error"] as? [String: Any],
           let msg = e["message"] as? String { throw YTAPIError.apiError(msg) }
        return json
    }

    // MARK: - Channel resolution

    private struct ChannelInfo { let id: String; let title: String; let uploadsPlaylist: String }

    private static func channelInfo(from json: Any, fallback: String) throws -> ChannelInfo {
        guard let d = json as? [String: Any],
              let items = d["items"] as? [[String: Any]], let item = items.first,
              let id    = item["id"] as? String,
              let sn    = item["snippet"] as? [String: Any], let title = sn["title"] as? String,
              let cd    = item["contentDetails"] as? [String: Any],
              let rp    = cd["relatedPlaylists"] as? [String: Any], let uploads = rp["uploads"] as? String
        else { throw YTAPIError.channelNotFound(fallback) }
        return ChannelInfo(id: id, title: title, uploadsPlaylist: uploads)
    }

    private static func resolveChannel(_ entry: ChannelEntry, apiKey: String) async throws -> ChannelInfo {
        switch entry.kind {
        case .id:
            return try channelInfo(from: try await get("channels", params: ["part": "snippet,contentDetails", "id": entry.value], apiKey: apiKey), fallback: entry.value)
        case .handle:
            return try channelInfo(from: try await get("channels", params: ["part": "snippet,contentDetails", "forHandle": entry.value], apiKey: apiKey), fallback: entry.value)
        case .legacy:
            do {
                let json = try await get("channels", params: ["part": "snippet,contentDetails", "forUsername": entry.value], apiKey: apiKey)
                if let d = json as? [String: Any], let items = d["items"] as? [[String: Any]], !items.isEmpty {
                    return try channelInfo(from: json, fallback: entry.value)
                }
            } catch {}
            // Fallback: search
            let sj = try await get("search", params: ["part": "snippet", "q": entry.value, "type": "channel", "maxResults": "1"], apiKey: apiKey)
            guard let sd = sj as? [String: Any], let sitems = sd["items"] as? [[String: Any]], let si = sitems.first,
                  let cid = (si["snippet"] as? [String: Any])?["channelId"] as? String
                           ?? (si["id"] as? [String: Any])?["channelId"] as? String
            else { throw YTAPIError.channelNotFound(entry.value) }
            return try channelInfo(from: try await get("channels", params: ["part": "snippet,contentDetails", "id": cid], apiKey: apiKey), fallback: entry.value)
        }
    }

    // MARK: - Video IDs via uploads playlist

    private static func fetchVideoIds(uploadsPlaylist: String, cap: Int, apiKey: String) async throws -> [String] {
        var ids: [String] = []; var pageToken = ""
        while ids.count < cap {
            var p: [String: String] = ["part": "contentDetails", "playlistId": uploadsPlaylist, "maxResults": "50"]
            if !pageToken.isEmpty { p["pageToken"] = pageToken }
            let json = try await get("playlistItems", params: p, apiKey: apiKey)
            guard let d = json as? [String: Any] else { break }
            (d["items"] as? [[String: Any]] ?? []).forEach {
                if let vid = ($0["contentDetails"] as? [String: Any])?["videoId"] as? String { ids.append(vid) }
            }
            if let next = d["nextPageToken"] as? String { pageToken = next } else { break }
        }
        return Array(ids.prefix(cap))
    }

    // MARK: - Video metadata

    private static func parseISO8601Duration(_ iso: String?) -> Double {
        guard let iso else { return 0 }
        var result = 0.0
        let rx = try? NSRegularExpression(pattern: #"(\d+)([HMS])"#)
        (rx?.matches(in: iso, range: NSRange(iso.startIndex..., in: iso)) ?? []).forEach { m in
            guard let nr = Range(m.range(at: 1), in: iso), let ur = Range(m.range(at: 2), in: iso) else { return }
            let n = Double(iso[nr]) ?? 0
            switch iso[ur] { case "H": result += n * 3600; case "M": result += n * 60; case "S": result += n; default: break }
        }
        return result
    }

    private static func fetchVideoMeta(ids: [String], apiKey: String) async throws -> [Video] {
        var out: [Video] = []
        var i = 0
        while i < ids.count {
            let batch = Array(ids[i..<min(i + 50, ids.count)])
            let json = try await get("videos", params: ["part": "snippet,contentDetails,status", "id": batch.joined(separator: ",")], apiKey: apiKey)
            (((json as? [String: Any])?["items"]) as? [[String: Any]] ?? []).forEach { it in
                let sn = it["snippet"] as? [String: Any]
                if let live = sn?["liveBroadcastContent"] as? String, live != "none" { return }
                let st = it["status"] as? [String: Any]
                if st?["embeddable"] as? Bool == false { return }
                if st?["privacyStatus"] as? String == "private" { return }
                guard let vid = it["id"] as? String else { return }
                let thumbs = sn?["thumbnails"] as? [String: Any]
                let thumb  = (thumbs?["medium"] as? [String: Any])?["url"] as? String
                           ?? (thumbs?["default"] as? [String: Any])?["url"] as? String ?? ""
                out.append(Video(
                    id: vid,
                    title: sn?["title"] as? String ?? "(ohne Titel)",
                    durationSec: parseISO8601Duration((it["contentDetails"] as? [String: Any])?["duration"] as? String),
                    thumb: thumb
                ))
            }
            i += 50
        }
        return out
    }

    // MARK: - Key validation

    static func testKey(_ apiKey: String) async throws {
        // Ruft YouTubes eigenen Kanal ab — schlaegt fehl wenn der Key ungueltig ist
        _ = try await get("channels", params: ["part": "snippet", "id": "UCBR8-60-B28hp2BmDPdntcQ"], apiKey: apiKey)
    }

    // MARK: - Public entry point

    static func resolveSenderChannels(
        apiKey: String,
        channelsRaw: String,
        maxPerChannel: Int,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> [ResolvedChannel] {
        guard !apiKey.isEmpty else { throw YTAPIError.noAPIKey }
        let lines = channelsRaw
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw YTAPIError.noChannels }
        var result: [ResolvedChannel] = []
        for line in lines {
            guard let entry = extractEntry(from: line) else { continue }
            do {
                log("Löse auf: \(line) …")
                let ch = try await resolveChannel(entry, apiKey: apiKey)
                log("  → gefunden: \(ch.title)")
                let ids = try await fetchVideoIds(uploadsPlaylist: ch.uploadsPlaylist, cap: maxPerChannel, apiKey: apiKey)
                log("  → \(ids.count) Video-IDs, hole Details …")
                let meta = try await fetchVideoMeta(ids: ids, apiKey: apiKey)
                let skipped = ids.count - meta.count
                log("  → \(meta.count) Videos geladen\(skipped > 0 ? " (\(skipped) übersprungen)" : "")")
                result.append(ResolvedChannel(id: ch.id, title: ch.title, videos: meta))
            } catch {
                log("  ✗ Fehler bei \"\(line)\": \(error.localizedDescription)")
            }
        }
        return result
    }
}
