import '../domain/rider_location.dart';

/// One device's latest contribution to a craft's position.
class CraftFixCandidate {
  const CraftFixCandidate({
    required this.deviceId,
    required this.sample,
    this.isNominatedPrimary = false,
  });

  final String deviceId;
  final LocationSample sample;

  /// Whether the pilot nominated this device as the craft's primary reporter.
  /// A preference, not an override: a nominated device with a dead receiver must
  /// not keep the craft silent while another phone in the same basket has a fix.
  final bool isNominatedPrimary;
}

/// Why a craft has no position worth publishing.
enum CraftFixAbsence {
  /// No device on this craft has reported at all.
  noDevices,

  /// Devices have reported, but every fix is older than the staleness threshold
  /// or too inaccurate to use. Deliberately distinct from [noDevices]: "the crew
  /// are aboard but we have lost them" is a different situation for a chase crew
  /// from "nobody has joined", and collapsing the two hides a real problem.
  allUnusable,
}

/// Which device currently speaks for a craft, and why.
class CraftFix {
  const CraftFix.elected({
    required this.deviceId,
    required this.sample,
    required this.contributingDeviceCount,
  }) : absence = null;

  const CraftFix.absent(this.absence, {required this.contributingDeviceCount})
    : deviceId = null,
      sample = null;

  final String? deviceId;
  final LocationSample? sample;
  final CraftFixAbsence? absence;

  /// How many devices are aboard and reporting, whether or not their fix won.
  /// A crew of three in a basket is worth showing even though only one of their
  /// phones is publishing the balloon's position.
  final int contributingDeviceCount;

  bool get hasFix => sample != null;
}

/// Decides which device on a craft publishes that craft's position.
///
/// The problem this solves: several phones in one basket. Left alone they become
/// several participants stacked on each other, and nothing can answer "where is
/// the balloon". A craft has one position; this picks whose.
///
/// **Every peer must reach the same answer without negotiating.** The rule is
/// therefore a pure function of facts already in the journal — no messages, no
/// leader election, no clock beyond the evaluation time that is passed in. Two
/// phones computing this from the same events agree by construction, which is the
/// same discipline the deleted Tail End Charlie resolution used.
///
/// Order of preference:
///  1. usable fixes only — fresh enough, and accurate enough;
///  2. the pilot's nominated primary device, if its fix is usable;
///  3. the freshest fix;
///  4. lowest device id, so ties break identically everywhere.
///
/// Hysteresis sits on top: the incumbent keeps the craft until a challenger is
/// *meaningfully* fresher. Without it, two phones side by side in a basket trade
/// the balloon back and forth every few seconds and the track visibly stutters
/// between two positions metres apart — which reads to a chase crew as the
/// balloon jinking, and it never happened.
class CraftTelemetryElection {
  const CraftTelemetryElection({
    this.staleAfter = const Duration(seconds: 45),
    this.maximumAccuracyMeters = 100,
    this.hysteresis = const Duration(seconds: 15),
  });

  /// A fix older than this cannot speak for the craft. Chosen shorter than the
  /// map's own stale threshold: losing the election is recoverable, whereas
  /// showing a stale position as live is not.
  final Duration staleAfter;

  /// A fix less accurate than this is not worth publishing as a balloon's
  /// position, however fresh it is.
  final double maximumAccuracyMeters;

  /// How much fresher a challenger must be before it takes the craft from the
  /// incumbent.
  final Duration hysteresis;

  /// [incumbentDeviceId] is whoever last spoke for this craft, if anyone.
  CraftFix elect({
    required Iterable<CraftFixCandidate> candidates,
    required DateTime now,
    String? incumbentDeviceId,
  }) {
    final all = candidates.toList(growable: false);
    if (all.isEmpty) {
      return const CraftFix.absent(
        CraftFixAbsence.noDevices,
        contributingDeviceCount: 0,
      );
    }

    final usable = all
        .where((c) => _isUsable(c.sample, now))
        .toList(growable: false);
    if (usable.isEmpty) {
      return CraftFix.absent(
        CraftFixAbsence.allUnusable,
        contributingDeviceCount: all.length,
      );
    }

    final winner = _best(usable, incumbentDeviceId, now);
    return CraftFix.elected(
      deviceId: winner.deviceId,
      sample: winner.sample,
      contributingDeviceCount: all.length,
    );
  }

  bool _isUsable(LocationSample sample, DateTime now) =>
      sample.ageAt(now) <= staleAfter &&
      sample.accuracyMeters <= maximumAccuracyMeters;

  CraftFixCandidate _best(
    List<CraftFixCandidate> usable,
    String? incumbentDeviceId,
    DateTime now,
  ) {
    // A nominated primary that is still usable wins outright. The pilot said
    // which phone is the balloon's; honour it while it works.
    final nominated = usable.where((c) => c.isNominatedPrimary).toList()
      ..sort(_byFreshnessThenId(now));
    if (nominated.isNotEmpty) return nominated.first;

    final ranked = [...usable]..sort(_byFreshnessThenId(now));
    final challenger = ranked.first;

    final incumbent = incumbentDeviceId == null
        ? null
        : usable
              .where((c) => c.deviceId == incumbentDeviceId)
              .cast<CraftFixCandidate?>()
              .firstWhere((c) => true, orElse: () => null);
    if (incumbent == null || incumbent.deviceId == challenger.deviceId) {
      return challenger;
    }

    // Hold the craft with the incumbent unless the challenger is meaningfully
    // fresher, so two phones in one basket do not trade it back and forth.
    final gain =
        incumbent.sample.ageAt(now) - challenger.sample.ageAt(now);
    return gain >= hysteresis ? challenger : incumbent;
  }

  int Function(CraftFixCandidate, CraftFixCandidate) _byFreshnessThenId(
    DateTime now,
  ) => (first, second) {
    final byAge = first.sample.ageAt(now).compareTo(second.sample.ageAt(now));
    return byAge != 0 ? byAge : first.deviceId.compareTo(second.deviceId);
  };
}
