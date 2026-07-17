import XCTest
@testable import StrandAnalytics

/// Pins the "Sleep detected" notification policy: fires once for a genuinely new, freshly-ended
/// session; stays silent for rescores, historical backfills, and anything already announced.
final class SleepDetectedAlertPolicyTests: XCTestCase {

    // A canonical night: 23:00 → 07:00 against now = 08:00 (an hour after wake).
    private let now = 1_700_000_000
    private var nightStart: Int { now - 9 * 3_600 }
    private var nightEnd: Int { now - 3_600 }

    func testFreshNewNightFires() {
        let alerts = SleepDetectedAlertPolicy.evaluate(
            banked: [(nightStart, nightEnd)], preexisting: [], alreadyNotified: [], now: now)
        XCTAssertEqual(alerts, [.init(startTs: nightStart, endTs: nightEnd, isNap: false)])
    }

    func testRescoredNightIsSilent() {
        // The 15-min tick re-banks the same night with a drifted onset (+90 s): overlap, not
        // exact match, must suppress it.
        let alerts = SleepDetectedAlertPolicy.evaluate(
            banked: [(nightStart + 90, nightEnd)],
            preexisting: [(nightStart, nightEnd)],
            alreadyNotified: [], now: now)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testHistoricalBackfillIsSilent() {
        // First install syncs three weeks of history: every night is "new" but none ended
        // recently — nothing may fire except a night inside the fresh-wake window.
        let old = (0..<21).map { d in (nightStart - d * 86_400 - 86_400, nightEnd - d * 86_400 - 86_400) }
        let alerts = SleepDetectedAlertPolicy.evaluate(
            banked: old, preexisting: [], alreadyNotified: [], now: now)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testFreshWakeWindowBoundary() {
        // Ended exactly at the 6 h edge: silent. One second inside: fires.
        let edge = now - SleepDetectedAlertPolicy.freshWakeMaxAgeS
        let silent = SleepDetectedAlertPolicy.evaluate(
            banked: [(edge - 8 * 3_600, edge)], preexisting: [], alreadyNotified: [], now: now)
        XCTAssertTrue(silent.isEmpty)
        let fires = SleepDetectedAlertPolicy.evaluate(
            banked: [(edge - 8 * 3_600, edge + 1)], preexisting: [], alreadyNotified: [], now: now)
        XCTAssertEqual(fires.count, 1)
    }

    func testAlreadyNotifiedTokenSuppresses() {
        let token = "\(nightStart):\(nightEnd)"
        let alerts = SleepDetectedAlertPolicy.evaluate(
            banked: [(nightStart, nightEnd)], preexisting: [],
            alreadyNotified: [token], now: now)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testNapClassification() {
        // 90 min ending 30 min ago → nap. 3 h exactly → night (boundary is < , not <=).
        let napEnd = now - 1_800
        let nap = SleepDetectedAlertPolicy.evaluate(
            banked: [(napEnd - 5_400, napEnd)], preexisting: [], alreadyNotified: [], now: now)
        XCTAssertEqual(nap.map(\.isNap), [true])
        let threeHours = SleepDetectedAlertPolicy.evaluate(
            banked: [(napEnd - SleepDetectedAlertPolicy.napMaxDurationS, napEnd)],
            preexisting: [], alreadyNotified: [], now: now)
        XCTAssertEqual(threeHours.map(\.isNap), [false])
    }

    func testNightAndNapSamePassBothFireInOrder() {
        // Night ended 4 h ago, a 90-min nap ended 30 min ago — both banked in one pass.
        let night = (now - 12 * 3_600, now - 4 * 3_600)
        let nap = (now - 7_200, now - 1_800)
        let alerts = SleepDetectedAlertPolicy.evaluate(
            banked: [nap, night], preexisting: [], alreadyNotified: [], now: now)
        XCTAssertEqual(alerts.map(\.startTs), [night.0, nap.0])
        XCTAssertEqual(alerts.map(\.isNap), [false, true])
    }

    func testOverlapWithAnyPreexistingSuppressesOnlyThatSession() {
        // The night was banked by an earlier pass (stored with slightly wider bounds); only the
        // new nap may fire.
        let night = (now - 12 * 3_600, now - 4 * 3_600)
        let nap = (now - 7_200, now - 1_800)
        let alerts = SleepDetectedAlertPolicy.evaluate(
            banked: [nap, night],
            preexisting: [(night.0 - 60, night.1 + 60)],
            alreadyNotified: [], now: now)
        XCTAssertEqual(alerts.map(\.startTs), [nap.0])
        XCTAssertEqual(alerts.map(\.isNap), [true])
    }
}
