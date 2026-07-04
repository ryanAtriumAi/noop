import Foundation
import WhoopProtocol

/// Weak-signal PPG ("tattoo mode") preference — the opt-in acceptance floor for the WHOOP 5 v26
/// optical heart-rate estimator.
///
/// Dark tattoo ink absorbs the green PPG light, so a real pulse over inked skin returns a much
/// weaker autocorrelation peak than clean skin. The canonical gate (`PpgHr.minConfidence`, 0.3)
/// rejects those windows outright, which reads as HR *gaps* on tattooed wrists. This mode lowers
/// the floor so genuinely-weak-but-periodic signal is accepted — every accepted sample still
/// carries its TRUE `conf`, and the read/chart paths render sub-0.3 stretches distinctly, so a
/// weak estimate is never presented as a clean measured beat.
///
/// OFF by default: the default pipeline stays byte-identical to the canonical Python/Android
/// behaviour (#219 parity). The toggle lives in Settings → Experimental.
enum PpgPrefs {
    /// UserDefaults key for the weak-signal toggle. Read cheaply (one bool) per backfill chunk.
    static let weakSignalKey = "ppg.weakSignalMode"

    /// The lowered acceptance floor while weak-signal mode is ON. Above the pure-noise
    /// autocorrelation floor (~0.1) but low enough to keep a faint real pulse; chosen conservatively
    /// so garbage windows still fail the gate.
    static let weakSignalFloor = 0.15

    /// The v26 PPG acceptance floor to use right now: the canonical `PpgHr.minConfidence` unless
    /// the user opted into weak-signal mode.
    static func effectiveMinConfidence() -> Double {
        UserDefaults.standard.bool(forKey: weakSignalKey) ? weakSignalFloor : PpgHr.minConfidence
    }
}
