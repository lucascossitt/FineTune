import Foundation
import Testing

@testable import FineTune

/// The ISO 226 target curve is unbounded by construction: at low listening levels it
/// asks for +14 dB of bass at 25% volume and over +22 dB at 5%. Loudness compensation
/// runs after the volume gain and directly before `SoftLimiter` (threshold 0.95,
/// headroom 0.05), so an unbounded target drives the limiter far past its knee and its
/// asymptotic curve pins the output at the ceiling — broadband distortion rather than
/// the intended bass lift.
///
/// These tests pin the ceiling that keeps the limiter idle on normal material, and the
/// 1 kHz normalization that keeps midrange untouched.
struct LoudnessBoostCeilingTests {

    private static let sampleRate = 48000.0
    private static let volumes: [Float] = [0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50, 0.60, 0.75, 0.90, 1.0]

    @Test("Target curve never asks for more boost than the ceiling, at any volume")
    func targetCurveRespectsCeiling() {
        let ceiling = LoudnessCompensator.maxCompensationBoostDB

        for volume in Self.volumes {
            let phon = ISO226Contours.estimatedPhon(fromSystemVolume: volume)
            let gains = ISO226Contours.compensationGains(
                atPhon: phon,
                maxGainDB: ceiling
            )
            let peak = gains.max() ?? 0

            #expect(peak <= ceiling + 0.001,
                    "volume \(volume): target peak \(peak) dB exceeds ceiling \(ceiling) dB")
        }
    }

    @Test("Without the ceiling the raw target really does run away — the bug this guards")
    func uncappedTargetExceedsCeiling() {
        let phon = ISO226Contours.estimatedPhon(fromSystemVolume: 0.25)
        let uncapped = ISO226Contours.compensationGains(atPhon: phon)
        let peak = uncapped.max() ?? 0

        #expect(peak > 10.0,
                "expected the uncapped ISO target to ask for >10 dB at 25% volume, got \(peak)")
    }

    @Test("Ceiling bounds the realized filter response, not just the request")
    func realizedResponseStaysBounded() {
        // The four-section fit can overshoot the target between grid points, so assert
        // on the response the filters actually produce, with a small fitting margin.
        for volume in Self.volumes {
            let phon = ISO226Contours.estimatedPhon(fromSystemVolume: volume)
            let gains = LoudnessCompensator.fittedSectionGains(forPhon: phon, sampleRate: Self.sampleRate)
            let peakSection = gains.max() ?? 0

            #expect(Double(peakSection) <= LoudnessCompensator.maxCompensationBoostDB + 2.0,
                    "volume \(volume): realized section gain \(peakSection) dB overshoots the ceiling")
        }
    }

    @Test("Midrange stays untouched — the curve is normalized at 1 kHz")
    func midrangeIsNotAttenuated() {
        // The failure mode of a preamp-cut approach: bass returns to unity but midrange
        // drops by the full boost. Normalization at 1 kHz is what prevents that.
        let phon = ISO226Contours.estimatedPhon(fromSystemVolume: 0.25)
        let gains = ISO226Contours.compensationGains(
            atPhon: phon,
            maxGainDB: LoudnessCompensator.maxCompensationBoostDB
        )
        let oneKilohertzIndex = ISO226Contours.frequencies.firstIndex(of: 1000)
        let atOneKilohertz = try! #require(oneKilohertzIndex.map { gains[$0] })

        #expect(abs(atOneKilohertz) < 0.001,
                "1 kHz should be unity, got \(atOneKilohertz) dB")
    }

    @Test("Compensation still does something audible at low volume")
    func compensationRemainsAudible() {
        // A ceiling that is too aggressive would silently disable the feature.
        let phon = ISO226Contours.estimatedPhon(fromSystemVolume: 0.25)
        let gains = ISO226Contours.compensationGains(
            atPhon: phon,
            maxGainDB: LoudnessCompensator.maxCompensationBoostDB
        )
        let peak = gains.max() ?? 0

        #expect(peak >= 3.0,
                "expected an audible bass lift at 25% volume, got only \(peak) dB")
    }
}
