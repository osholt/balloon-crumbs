import 'spoken_audio_mode.dart';

enum ChaseSpeechPriority {
  routeOverview(10),
  recalculation(20),
  targetChange(30),
  fixRecovered(40),
  routeUnavailable(50),
  staleFix(60),
  arrival(70);

  const ChaseSpeechPriority(this.weight);

  final int weight;
}

class ChaseSpeechCandidate {
  const ChaseSpeechCandidate({
    required this.key,
    required this.phrase,
    required this.priority,
    required this.audioClass,
  });

  final String key;
  final String phrase;
  final ChaseSpeechPriority priority;
  final SpokenAudioClass audioClass;

  factory ChaseSpeechCandidate.routeOverview(String routeRevision) =>
      ChaseSpeechCandidate(
        key: 'chase-route-overview:$routeRevision',
        phrase:
            'Road guidance ends at a road rendezvous near the balloon, not at '
            'the balloon itself. Check access and stop only where it is lawful '
            'and safe.',
        priority: ChaseSpeechPriority.routeOverview,
        audioClass: SpokenAudioClass.navigation,
      );

  factory ChaseSpeechCandidate.recalculation(String attemptRevision) =>
      ChaseSpeechCandidate(
        key: 'chase-recalculation:$attemptRevision',
        phrase: 'Recalculating the road rendezvous.',
        priority: ChaseSpeechPriority.recalculation,
        audioClass: SpokenAudioClass.navigation,
      );

  factory ChaseSpeechCandidate.targetChanged({
    required String revision,
    required String phrase,
  }) => ChaseSpeechCandidate(
    key: 'chase-target:$revision',
    phrase: phrase,
    priority: ChaseSpeechPriority.targetChange,
    audioClass: SpokenAudioClass.safety,
  );

  factory ChaseSpeechCandidate.fixRecovered(String fixRevision) =>
      ChaseSpeechCandidate(
        key: 'chase-fix-recovered:$fixRevision',
        phrase:
            'Balloon position recovered. Recalculating the road rendezvous.',
        priority: ChaseSpeechPriority.fixRecovered,
        audioClass: SpokenAudioClass.safety,
      );

  factory ChaseSpeechCandidate.routeUnavailable(String attemptRevision) =>
      ChaseSpeechCandidate(
        key: 'chase-route-unavailable:$attemptRevision',
        phrase:
            'A new road rendezvous is unavailable. Continue with the last '
            'route and assess locally.',
        priority: ChaseSpeechPriority.routeUnavailable,
        audioClass: SpokenAudioClass.safety,
      );

  factory ChaseSpeechCandidate.staleFix(String lossRevision) =>
      ChaseSpeechCandidate(
        key: 'chase-stale-fix:$lossRevision',
        phrase: 'Balloon position is stale. The last road route is being held.',
        priority: ChaseSpeechPriority.staleFix,
        audioClass: SpokenAudioClass.safety,
      );

  factory ChaseSpeechCandidate.arrival(String routeRevision) =>
      ChaseSpeechCandidate(
        key: 'chase-arrival:$routeRevision',
        phrase:
            'Arriving at the road rendezvous. Stop only where it is lawful and '
            'safe. The balloon may still be elsewhere.',
        priority: ChaseSpeechPriority.arrival,
        audioClass: SpokenAudioClass.safety,
      );
}

/// Chooses one unambiguous recovery message when several state changes happen
/// together. Identity/deduplication remains in [SpokenGuidanceSpeaker], so a
/// muted event is still eligible if the driver enables speech before the state
/// changes again.
class ChaseSpokenGuidancePolicy {
  const ChaseSpokenGuidancePolicy();

  ChaseSpeechCandidate? choose(Iterable<ChaseSpeechCandidate> candidates) {
    final usable = candidates.where(
      (candidate) =>
          candidate.key.trim().isNotEmpty && candidate.phrase.trim().isNotEmpty,
    );
    if (usable.isEmpty) return null;
    return usable.reduce(
      (current, candidate) =>
          candidate.priority.weight > current.priority.weight
          ? candidate
          : current,
    );
  }
}
