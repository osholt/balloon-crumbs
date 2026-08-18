import 'package:balloon_crumbs/domain/ride_coordination_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stored second-bike drop-off flight degrades to a group, not solo', () {
    // The trap this exists to hold shut. `secondBikeDropOff` was the only mode
    // before the choice existed, so every flight stored before then reads back
    // as an unrecognised name once the mode is deleted. Solo is the wrong
    // fallback and the damage is silent: it has no join code and no crew, so a
    // stored flight would lose both on the next load, with nothing to say so.
    expect(
      RideCoordinationMode.fromName('secondBikeDropOff'),
      RideCoordinationMode.keepTogether,
    );
    expect(RideCoordinationMode.fromName('secondBikeDropOff').isGroup, isTrue);
  });

  test('any unrecognised mode degrades the same way', () {
    for (final name in [null, '', 'tailEndCharlie', 'somethingNewer']) {
      expect(
        RideCoordinationMode.fromName(name),
        RideCoordinationMode.keepTogether,
        reason: 'fromName($name)',
      );
    }
  });

  test('a mode this build does know round-trips by name', () {
    for (final mode in RideCoordinationMode.values) {
      expect(RideCoordinationMode.fromName(mode.name), mode);
    }
  });

  test('solo is the only mode that is not a group', () {
    expect(RideCoordinationMode.solo.isGroup, isFalse);
    expect(RideCoordinationMode.keepTogether.isGroup, isTrue);
  });
}
