import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/flight_replay.dart';
import '../domain/geo_point.dart';

enum FlightReplayState { ready, playing, paused, completed }

class FlightReplayFrame {
  const FlightReplayFrame({
    required this.recordedAt,
    required this.samples,
    required this.wind,
    required this.landingArea,
  });

  final DateTime recordedAt;
  final Map<String, FlightReplaySample> samples;
  final FlightReplayWindContext? wind;
  final FlightReplayLandingArea? landingArea;
}

/// Plays a completed-flight archive against one shared clock.
class FlightReplayController extends ChangeNotifier {
  FlightReplayController(
    this.replay, {
    this.tickInterval = const Duration(milliseconds: 100),
  });

  static const maximumInterpolatedGap = Duration(minutes: 2);

  final FlightReplay replay;
  final Duration tickInterval;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  double _timeScale = 8;
  FlightReplayState _state = FlightReplayState.ready;

  Duration get elapsed => _elapsed;
  double get timeScale => _timeScale;
  FlightReplayState get state => _state;
  bool get isPlaying => _state == FlightReplayState.playing;
  double get progress => replay.duration.inMicroseconds <= 0
      ? 1
      : (_elapsed.inMicroseconds / replay.duration.inMicroseconds).clamp(0, 1);

  FlightReplayFrame get frame {
    final at = replay.startedAt.add(_elapsed);
    final samples = <String, FlightReplaySample>{};
    for (final track in replay.tracks) {
      final sample = _sampleAt(track, at);
      if (sample != null) samples[track.id] = sample;
    }
    return FlightReplayFrame(
      recordedAt: at,
      samples: samples,
      wind: replay.windContexts
          .where((context) => !context.recordedAt.isAfter(at))
          .lastOrNull,
      landingArea: replay.landingAreas
          .where((area) => !area.recordedAt.isAfter(at))
          .lastOrNull,
    );
  }

  void play() {
    if (_state == FlightReplayState.completed) restart();
    if (isPlaying) return;
    _state = FlightReplayState.playing;
    _timer ??= Timer.periodic(tickInterval, (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!isPlaying) return;
    _state = FlightReplayState.paused;
    notifyListeners();
  }

  void restart() {
    _elapsed = Duration.zero;
    _state = FlightReplayState.ready;
    notifyListeners();
  }

  void seek(double progress) {
    final bounded = progress.clamp(0, 1);
    _elapsed = Duration(
      microseconds: (replay.duration.inMicroseconds * bounded).round(),
    );
    _state = bounded >= 1
        ? FlightReplayState.completed
        : FlightReplayState.paused;
    notifyListeners();
  }

  void setTimeScale(double value) {
    final next = value.clamp(1, 32).toDouble();
    if (next == _timeScale) return;
    _timeScale = next;
    notifyListeners();
  }

  void _tick() {
    if (!isPlaying) return;
    final delta = Duration(
      microseconds: (tickInterval.inMicroseconds * _timeScale).round(),
    );
    _elapsed += delta;
    if (_elapsed >= replay.duration) {
      _elapsed = replay.duration;
      _state = FlightReplayState.completed;
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  static FlightReplaySample? _sampleAt(FlightReplayTrack track, DateTime at) {
    final samples = track.samples;
    if (samples.isEmpty || at.isBefore(samples.first.recordedAt)) return null;
    if (!at.isBefore(samples.last.recordedAt)) return samples.last;
    for (var index = 0; index < samples.length - 1; index += 1) {
      final before = samples[index];
      final after = samples[index + 1];
      if (at.isAfter(after.recordedAt)) continue;
      final gap = after.recordedAt.difference(before.recordedAt);
      if (gap > maximumInterpolatedGap) return before;
      final fraction = gap.inMicroseconds <= 0
          ? 0.0
          : at.difference(before.recordedAt).inMicroseconds /
                gap.inMicroseconds;
      double? between(double? left, double? right) =>
          left == null || right == null
          ? left ?? right
          : left + (right - left) * fraction;
      return FlightReplaySample(
        position: GeoPoint(
          latitude:
              before.position.latitude +
              (after.position.latitude - before.position.latitude) * fraction,
          longitude:
              before.position.longitude +
              (after.position.longitude - before.position.longitude) * fraction,
        ),
        recordedAt: at,
        speedMetersPerSecond: between(
          before.speedMetersPerSecond,
          after.speedMetersPerSecond,
        ),
        headingDegrees: between(before.headingDegrees, after.headingDegrees),
        altitudeMeters: between(before.altitudeMeters, after.altitudeMeters),
        altitudeSource: before.altitudeSource,
        altitudeDatum: before.altitudeDatum,
        verticalSpeedMetersPerSecond: between(
          before.verticalSpeedMetersPerSecond,
          after.verticalSpeedMetersPerSecond,
        ),
      );
    }
    return samples.last;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
