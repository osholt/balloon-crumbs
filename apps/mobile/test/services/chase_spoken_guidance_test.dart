import 'package:balloon_crumbs/services/chase_spoken_guidance.dart';
import 'package:balloon_crumbs/services/spoken_audio_mode.dart';
import 'package:balloon_crumbs/services/spoken_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ChaseSpokenGuidancePolicy();

  test('the first route instruction explains the road rendezvous boundary', () {
    final announcement = policy.choose([
      ChaseSpeechCandidate.routeOverview('route-1'),
    ]);

    expect(announcement!.phrase, contains('road rendezvous'));
    expect(announcement.phrase, contains('not at the balloon'));
    expect(announcement.phrase, contains('lawful and safe'));
  });

  test('stale and arrival messages outrank recalculation chatter', () {
    final stale = policy.choose([
      ChaseSpeechCandidate.recalculation('attempt-1'),
      ChaseSpeechCandidate.staleFix('loss-1'),
    ]);
    final arrival = policy.choose([
      ChaseSpeechCandidate.routeUnavailable('attempt-2'),
      ChaseSpeechCandidate.arrival('route-1'),
    ]);

    expect(stale!.priority, ChaseSpeechPriority.staleFix);
    expect(arrival!.priority, ChaseSpeechPriority.arrival);
  });

  test('repeated churn is deduplicated by semantic revision', () async {
    final engine = _RecordingEngine();
    final speaker = SpokenGuidanceSpeaker(engine);
    final churn = [
      for (var index = 0; index < 20; index += 1)
        policy.choose([
          ChaseSpeechCandidate.recalculation('attempt-1'),
          ChaseSpeechCandidate.staleFix('loss-1'),
        ])!,
    ];

    for (final announcement in churn) {
      await speaker.speakAlert(
        key: announcement.key,
        phrase: announcement.phrase,
        enabled: spokenAudioAllows(
          SpokenAudioMode.everything,
          announcement.audioClass,
        ),
        rideActive: true,
      );
    }

    expect(engine.spoken, [
      'Balloon position is stale. The last road route is being held.',
    ]);
  });

  test('alerts-only keeps state warnings but silences route chatter', () {
    final recalculation = ChaseSpeechCandidate.recalculation('attempt-1');
    final stale = ChaseSpeechCandidate.staleFix('loss-1');

    expect(
      spokenAudioAllows(SpokenAudioMode.alertsOnly, recalculation.audioClass),
      isFalse,
    );
    expect(
      spokenAudioAllows(SpokenAudioMode.alertsOnly, stale.audioClass),
      isTrue,
    );
  });
}

class _RecordingEngine implements SpokenGuidanceEngine {
  final spoken = <String>[];

  @override
  Future<void> configure() async {}

  @override
  Future<void> speak(String phrase) async => spoken.add(phrase);

  @override
  Future<void> stop() async {}
}
