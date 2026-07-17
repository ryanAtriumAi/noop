import Foundation

/// Decides which just-banked detected sleep sessions deserve a "Sleep detected" notification —
/// the WHOOP-style auto-detect surfacing: shortly after you wake, the phone tells you your night
/// was captured, without the app ever being opened (detection runs on the background BLE sync).
///
/// Pure policy, no clocks and no I/O, so both the fresh-wake window and the spam guards are
/// pinned by tests. The caller (IntelligenceEngine's banking seam) supplies:
///  - the sessions THIS pass banked (post edit/tombstone filtering, so anything the user
///    corrected or deleted can never re-announce itself),
///  - the sessions that were ALREADY stored before this pass's upsert,
///  - the tokens of sessions previously notified (persisted ring, survives restarts),
///  - `now`.
///
/// A session fires only when ALL hold:
///  1. NEW — it does not time-overlap any pre-existing stored session. Overlap, not exact
///     startTs, because a detected onset drifts second-to-second as more raw data arrives
///     (same idiom as the edited/dismissed guards and the #899 heal). The 15-minute rescore
///     tick re-banks the same night every pass; only the FIRST pass sees it as new.
///  2. FRESHLY ENDED — its wake lands within `freshWakeMaxAgeS` of now. A first sync that
///     backfills weeks of history detects dozens of "new" nights; only the one you actually
///     just woke from is worth a banner. (6 h keeps a lazy-Sunday late sync announcing the
///     night, but a Monday sync never re-announces Saturday.)
///  3. UNANNOUNCED — its token is not in the persisted already-notified ring (belt and
///     braces for strap-timebase shifts where a re-banked night may not overlap its stale copy).
public enum SleepDetectedAlertPolicy {

    /// How recently a session must have ENDED to be announced. Six hours: long enough that a
    /// morning phone-side sync still announces last night, short enough that a historical
    /// backfill (first install, strap re-pair) stays silent.
    public static let freshWakeMaxAgeS = 6 * 3_600

    /// Detected sessions shorter than this announce as a nap, at or above it as a night. The
    /// detector's own floor is 60 min, so naps land in [1 h, 3 h).
    public static let napMaxDurationS = 3 * 3_600

    /// Cap on the persisted already-notified ring the caller maintains (oldest dropped first).
    /// 40 tokens ≈ a month of nights + naps; the overlap test is the primary guard, the ring
    /// only backstops timebase shifts, so depth is not critical.
    public static let notifiedRingCap = 40

    public struct Alert: Equatable {
        public let startTs: Int
        public let endTs: Int
        /// True when the session reads as a nap (duration < `napMaxDurationS`), so the caller
        /// can title the banner "Nap detected" instead of "Sleep detected".
        public let isNap: Bool
        /// Stable identity for the notified ring and the notification identifier.
        public var token: String { "\(startTs):\(endTs)" }
        public init(startTs: Int, endTs: Int, isNap: Bool) {
            self.startTs = startTs; self.endTs = endTs; self.isNap = isNap
        }
    }

    /// Evaluate one banking pass. Returns the alerts to post, oldest first (a night and a
    /// morning nap banked in the same pass both fire, in chronological order).
    public static func evaluate(banked: [(startTs: Int, endTs: Int)],
                                preexisting: [(startTs: Int, endTs: Int)],
                                alreadyNotified: Set<String>,
                                now: Int) -> [Alert] {
        banked
            .filter { s in
                s.endTs > now - freshWakeMaxAgeS
                    && !preexisting.contains { s.startTs < $0.endTs && $0.startTs < s.endTs }
                    && !alreadyNotified.contains("\(s.startTs):\(s.endTs)")
            }
            .sorted { $0.startTs < $1.startTs }
            .map { Alert(startTs: $0.startTs, endTs: $0.endTs,
                         isNap: $0.endTs - $0.startTs < napMaxDurationS) }
    }
}
