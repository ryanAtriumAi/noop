import Foundation
import UserNotifications
import StrandAnalytics

/// The WHOOP-style "sleep auto-detected" surfacing: shortly after you wake, the phone announces
/// that last night (or a nap) was captured — without the app being opened, because detection runs
/// when the background BLE sync completes and re-scores the fresh raw data. The strap wearer's
/// only cue that auto-detection worked used to be opening the app; this closes that gap.
///
/// Mirrors `IllnessNotifier` / `BatteryNotifier`: requestAuthorization() up front when the toggle
/// is enabled, status-only check at fire time, and the persisted gate (the notified-token ring)
/// advances even when delivery is deferred or declined — the Sleep screen stays the live surface
/// either way. Which sessions fire is decided by the pure, test-pinned
/// `SleepDetectedAlertPolicy`; this file is only the UserDefaults + UNUserNotificationCenter glue.
/// On-device only; gated behind "Sleep detected alerts" (default ON, WHOOP parity).
enum SleepDetectedNotifier {
    static let enabledKey = "behavior.sleepDetectedAlerts"
    private static let notifiedRingKey = "sleep.detectedNotifiedTokens"

    /// Ask up front (called when the user enables the alerts) so the system dialog appears at a
    /// predictable moment, not on the first morning-after sync.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Run the policy against one banking pass and post at most one notification per genuinely
    /// new, freshly-ended session. `banked` are the sessions the pass just upserted (already
    /// filtered of edited/dismissed windows); `preexisting` the sessions stored BEFORE the upsert.
    static func onSleepBanked(banked: [(startTs: Int, endTs: Int)],
                              preexisting: [(startTs: Int, endTs: Int)],
                              now: Int = Int(Date().timeIntervalSince1970)) {
        let d = UserDefaults.standard
        guard d.object(forKey: enabledKey) as? Bool ?? true else { return }
        var ring = d.stringArray(forKey: notifiedRingKey) ?? []
        let alerts = SleepDetectedAlertPolicy.evaluate(banked: banked,
                                                       preexisting: preexisting,
                                                       alreadyNotified: Set(ring),
                                                       now: now)
        guard !alerts.isEmpty else { return }
        // Advance the persisted gate up front (mirroring the sibling notifiers) so a session is
        // announced at most once regardless of authorization state or delivery timing.
        ring.append(contentsOf: alerts.map(\.token))
        if ring.count > SleepDetectedAlertPolicy.notifiedRingCap {
            ring.removeFirst(ring.count - SleepDetectedAlertPolicy.notifiedRingCap)
        }
        d.set(ring, forKey: notifiedRingKey)
        for alert in alerts { post(alert) }
    }

    private static func post(_ alert: SleepDetectedAlertPolicy.Alert) {
        let center = UNUserNotificationCenter.current()
        // Authorization is requested once via requestAuthorization() when alerts are enabled;
        // here we only check status (no second system prompt).
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = alert.isNap
                ? String(localized: "Nap detected")
                : String(localized: "Sleep detected")
            content.body = String(localized:
                "\(durationText(alert.endTs - alert.startTs)) · \(clockText(alert.startTs)) – \(clockText(alert.endTs)). Open NOOP for your Rest and Charge.")
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "sleep-detected-\(alert.token)",
                                             content: content, trigger: nil))
        }
    }

    /// "7h 32m" — same shape the Sleep screen uses for stage durations.
    private static func durationText(_ seconds: Int) -> String {
        let m = Swift.max(0, seconds / 60)
        if m < 60 { return String(localized: "\(m)m") }
        return String(localized: "\(m / 60)h \(m % 60)m")
    }

    /// Clock time in the device 12/24-hour preference ("jmm" template, same as the sleep axis).
    private static func clockText(_ ts: Int) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: Date(timeIntervalSince1970: Double(ts)))
    }
}
