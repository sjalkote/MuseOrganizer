import BackgroundTasks
import SwiftUI
import UserNotifications

/// Keeps the app in step with Muse's price watch: loads live options, re-checks prices, and turns
/// Muse's advice into notifications so the group hears about drops without opening the app.
///
/// With no backend configured it shows demo watches (labeled as such) and never sends notifications.
@Observable
final class PriceWatchCenter {
    static let refreshTaskID = "com.sjalkote.MuseOrganizer.pricewatch"

    let api: HuddleAPI?
    private(set) var watches: [String: [PriceWatch]] = [:]
    /// nil until the backend answers; stays nil with no backend.
    private(set) var live: LiveStatus?
    private(set) var checking: Set<String> = []
    private(set) var loadedBoards: Set<String> = []
    var error: String?
    var notificationsAllowed = false

    /// Newest alert time already turned into a notification.
    private var seenUntil: Double {
        get { UserDefaults.standard.double(forKey: "priceWatch.seenUntil") }
        set { UserDefaults.standard.set(newValue, forKey: "priceWatch.seenUntil") }
    }
    private var polling: Task<Void, Never>?

    init(api: HuddleAPI? = HuddleAPI.configured) {
        self.api = api
        if api == nil {
            for id in ["japan", "car"] { watches[id] = Mock.demoWatches(for: id) }
        }
        Task { await refreshNotificationStatus() }
    }

    var isDemo: Bool { api == nil || live.map { !$0.muse || !$0.serpapi } ?? false }

    /// "Demo data" when nothing live, else which side is still simulated.
    var sourceNote: String {
        guard api != nil else { return "Demo data · connect the Huddle backend" }
        guard let live else { return "Connecting to Muse…" }
        switch (live.muse, live.serpapi) {
        case (true, true): return "Live · Muse Spark + SerpApi"
        case (true, false): return "Muse live · SerpApi demo prices"
        case (false, true): return "SerpApi live · Muse demo advice"
        case (false, false): return "Demo data · add API keys to the backend"
        }
    }

    func watches(for planID: String) -> [PriceWatch] { watches[planID] ?? [] }

    func watch(id: String?) -> PriceWatch? {
        guard let id else { return nil }
        return watches.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    /// The newest piece of Muse advice on a plan, with its watch.
    func latestAdvice(for planID: String) -> (PriceWatch, PriceAdvice)? {
        watches(for: planID)
            .compactMap { w in w.advice.map { (w, $0) } }
            .max { $0.1.at < $1.1.at }
    }

    // MARK: Loading

    /// Trip plans get their options from live searches; every plan gets its watches.
    func load(_ plan: Plan) async {
        guard let api else { return }
        do {
            if plan.kind == .trip, let trip = plan.tripQuery, !loadedBoards.contains(plan.id) {
                let board = try await api.board(planID: plan.id, trip: trip)
                withAnimation(Motion.smooth) {
                    plan.replaceOptions(with: board.options)
                    watches[plan.id] = board.watches
                    live = board.live
                }
                loadedBoards.insert(plan.id)
            } else {
                if plan.kind == .decision, let request = plan.watchRequest, watches(for: plan.id).isEmpty {
                    _ = try await api.addWatch(planID: plan.id, request)
                }
                let out = try await api.watches(planID: plan.id)
                withAnimation(Motion.smooth) { watches[plan.id] = out.watches }
                if live == nil { live = try? await api.status().live }
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Ask SerpApi again right now (pull to refresh, "Check now").
    func check(_ planID: String) async {
        guard let api else { return }
        checking.insert(planID)
        defer { checking.remove(planID) }
        do {
            let out = try await api.check(planID: planID)
            withAnimation(Motion.smooth) { watches[planID] = out.watches }
            await notify(out.alerts)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Background

    /// Picks up alerts the backend's own sweep found, every minute while the app is open.
    func startPolling(plans: @escaping () -> [Plan]) {
        guard api != nil, polling == nil else { return }
        polling = Task { [weak self] in
            // Fill in every plan's watches up front so Home can show Muse's calls before a plan is opened.
            for plan in plans() {
                if let out = try? await self?.api?.watches(planID: plan.id), !out.watches.isEmpty {
                    withAnimation(Motion.smooth) { self?.watches[plan.id] = out.watches }
                }
            }
            if self?.live == nil, let status = try? await self?.api?.status() { self?.live = status.live }
            while !Task.isCancelled {
                await self?.poll(plans: plans())
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func poll(plans: [Plan]) async {
        guard let api else { return }
        do {
            let since = seenUntil == 0 ? Date.now.timeIntervalSince1970 - 3_600 : seenUntil
            let out = try await api.alerts(since: since)
            guard !out.alerts.isEmpty else { return }
            await notify(out.alerts)
            for id in Set(out.alerts.map(\.planId)) {
                if let fresh = try? await api.watches(planID: id) {
                    withAnimation(Motion.smooth) { watches[id] = fresh.watches }
                }
            }
        } catch {
            // Backend asleep or offline; try again next minute.
        }
    }

    /// iOS wakes the app now and then (BGAppRefreshTask); re-check every plan and notify on anything new.
    func backgroundRefresh(planIDs: [String]) async {
        guard let api else { return }
        for id in planIDs {
            if let out = try? await api.check(planID: id) { await notify(out.alerts) }
        }
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        guard api != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Notifications

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func requestNotifications() async {
        notificationsAllowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Only "book now" calls interrupt you, and several at once become one notification per plan.
    /// "Wait" and "keep watching" still show on the plan; they just don't buzz your phone.
    private func notify(_ alerts: [PriceAdvice]) async {
        let fresh = alerts.filter { $0.at > seenUntil }
        guard let newest = fresh.map(\.at).max() else { return }
        seenUntil = newest
        if !notificationsAllowed { await refreshNotificationStatus() }
        guard notificationsAllowed else { return }
        let actionable = Dictionary(grouping: fresh.filter { $0.verdict == .book }, by: \.planId)
        for (planID, group) in actionable {
            guard let top = group.max(by: { $0.drop < $1.drop }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = group.count == 1 ? "Muse · Book now" : "Muse · \(group.count) prices worth booking"
            content.subtitle = top.headline
            content.body = group.count == 1 ? top.reason : "\(top.reason) Plus \(group.count - 1) more on this plan."
            content.sound = .default
            content.threadIdentifier = planID
            content.userInfo = ["planID": planID]
            let request = UNNotificationRequest(identifier: top.id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

extension LiveStatus {
    init(_ status: HuddleAPI.Status) { self.init(muse: status.muse, serpapi: status.serpapi) }
}

extension HuddleAPI.Status {
    var live: LiveStatus { LiveStatus(self) }
}

/// Shows price alerts while the app is open and opens the plan when one is tapped.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var open: (String) -> Void = { _ in }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let id = response.notification.request.content.userInfo["planID"] as? String {
            await MainActor.run { open(id) }
        }
    }
}
