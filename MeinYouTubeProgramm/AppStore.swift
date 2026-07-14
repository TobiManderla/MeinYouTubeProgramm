import Foundation
import Observation

@Observable
final class AppStore {
    var senders: [Sender]     = []
    var settings: AppSettings = .init()

    private let sendersKey  = "ytprog_senders_v2"
    private let settingsKey = "ytprog_global_v2"

    init() { load() }

    private func load() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: sendersKey),
           let v = try? JSONDecoder().decode([Sender].self, from: d) {
            senders = v
        }
        if let d = ud.data(forKey: settingsKey),
           let v = try? JSONDecoder().decode(AppSettings.self, from: d) {
            settings = v
        }
    }

    func save() {
        let ud = UserDefaults.standard
        ud.set(try? JSONEncoder().encode(senders),  forKey: sendersKey)
        ud.set(try? JSONEncoder().encode(settings), forKey: settingsKey)
    }

    func addSender(_ s: Sender)    { senders.append(s); save() }
    func deleteSender(id: String)  { senders.removeAll { $0.id == id }; save() }
    func updateSender(_ s: Sender) {
        if let i = senders.firstIndex(where: { $0.id == s.id }) {
            senders[i] = s; save()
        }
    }
}
