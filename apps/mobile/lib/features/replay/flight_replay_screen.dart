import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controllers/flight_replay_controller.dart';
import '../../domain/altitude_unit.dart';
import '../../domain/distance_unit.dart';
import '../../domain/flight_replay.dart';
import '../../domain/geo_point.dart';
import '../../services/measurement_formatter.dart';

class FlightReplayScreen extends StatefulWidget {
  const FlightReplayScreen({
    super.key,
    required this.title,
    required this.replay,
    required this.distanceUnit,
    this.altitudeUnit = AltitudeUnit.metres,
  });

  final String title;
  final FlightReplay replay;
  final DistanceUnit distanceUnit;
  final AltitudeUnit altitudeUnit;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required FlightReplay replay,
    required DistanceUnit distanceUnit,
    required AltitudeUnit altitudeUnit,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FlightReplayScreen(
        title: title,
        replay: replay,
        distanceUnit: distanceUnit,
        altitudeUnit: altitudeUnit,
      ),
    ),
  );

  @override
  State<FlightReplayScreen> createState() => _FlightReplayScreenState();
}

class _FlightReplayScreenState extends State<FlightReplayScreen> {
  late final FlightReplayController _controller = FlightReplayController(
    widget.replay,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Replay · ${widget.title}')),
    body: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final frame = _controller.frame;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CustomPaint(
                  key: const Key('archived-flight-replay-map'),
                  painter: _FlightReplayPainter(
                    replay: widget.replay,
                    frame: frame,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ReplayControls(controller: _controller),
            const SizedBox(height: 12),
            _TelemetryGrid(
              replay: widget.replay,
              frame: frame,
              distanceUnit: widget.distanceUnit,
              altitudeUnit: widget.altitudeUnit,
            ),
            const SizedBox(height: 12),
            _WindCard(frame.wind, altitudeUnit: widget.altitudeUnit),
            const SizedBox(height: 10),
            Text(
              widget.replay.peerTracksIncluded
                  ? 'This local archive includes the other chaser tracks that were available when it was saved.'
                  : 'This local archive keeps the balloon and this device’s track. Other chaser histories were not retained.',
              style: const TextStyle(color: Color(0xFF8994A2), fontSize: 12),
            ),
          ],
        );
      },
    ),
  );
}

class _ReplayControls extends StatelessWidget {
  const _ReplayControls({required this.controller});

  final FlightReplayController controller;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('flight-replay-play-pause'),
                tooltip: controller.isPlaying ? 'Pause replay' : 'Play replay',
                onPressed: controller.isPlaying
                    ? controller.pause
                    : controller.play,
                icon: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
              IconButton(
                tooltip: 'Restart replay',
                onPressed: controller.restart,
                icon: const Icon(Icons.replay),
              ),
              Expanded(
                child: Slider(
                  key: const Key('flight-replay-timeline'),
                  value: controller.progress,
                  onChanged: controller.seek,
                ),
              ),
              Text(
                '${_duration(controller.elapsed)} / ${_duration(controller.replay.duration)}',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1×')),
              ButtonSegment(value: 8, label: Text('8×')),
              ButtonSegment(value: 32, label: Text('32×')),
            ],
            selected: {controller.timeScale},
            onSelectionChanged: (values) =>
                controller.setTimeScale(values.first),
          ),
        ],
      ),
    ),
  );
}

class _TelemetryGrid extends StatelessWidget {
  const _TelemetryGrid({
    required this.replay,
    required this.frame,
    required this.distanceUnit,
    required this.altitudeUnit,
  });

  final FlightReplay replay;
  final FlightReplayFrame frame;
  final DistanceUnit distanceUnit;
  final AltitudeUnit altitudeUnit;

  @override
  Widget build(BuildContext context) {
    final formatter = MeasurementFormatter(distanceUnit);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final track in replay.tracks)
          if (frame.samples[track.id] case final sample?)
            SizedBox(
              width: 178,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sample.speedMetersPerSecond == null
                            ? 'Speed unknown'
                            : formatter.speed(sample.speedMetersPerSecond!),
                      ),
                      Text(
                        sample.altitudeMeters == null
                            ? 'Altitude unknown'
                            : altitudeUnit.altitude(sample.altitudeMeters!),
                      ),
                      Text(
                        sample.headingDegrees == null
                            ? 'Course unknown'
                            : 'Course ${sample.headingDegrees!.round().toString().padLeft(3, '0')}°',
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _WindCard extends StatelessWidget {
  const _WindCard(this.wind, {required this.altitudeUnit});

  final FlightReplayWindContext? wind;
  final AltitudeUnit altitudeUnit;

  @override
  Widget build(BuildContext context) {
    final context = wind;
    if (context == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.air),
          title: Text('No wind context was retained at this time'),
        ),
      );
    }
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.air),
        title: Text(
          context.isForecast
              ? 'Forecast wind context'
              : 'Observed wind context',
        ),
        subtitle: Text(
          '${context.source} · valid ${_clock(context.validAt)} · ${context.vectors.length} altitude levels',
        ),
        children: [
          for (final vector in context.vectors)
            ListTile(
              dense: true,
              title: Text(
                '${altitudeUnit.altitude(vector.altitudeMetersMsl)} MSL',
              ),
              trailing: Text(
                '${vector.fromDegrees.round().toString().padLeft(3, '0')}° from · ${vector.speedKmh.round()} km/h',
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'Replay context only. It is not a current forecast or an aviation weather briefing.',
              style: TextStyle(color: Color(0xFF8994A2), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlightReplayPainter extends CustomPainter {
  const _FlightReplayPainter({required this.replay, required this.frame});

  final FlightReplay replay;
  final FlightReplayFrame frame;

  static const _trackColors = {
    FlightReplayTrackKind.balloon: Color(0xFFFF7A1A),
    FlightReplayTrackKind.localChaser: Color(0xFF42C9E8),
    FlightReplayTrackKind.chaser: Color(0xFF6ED89A),
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101821),
    );
    final all = [
      for (final track in replay.tracks)
        for (final sample in track.samples) sample.position,
      if (frame.landingArea case final area?) area.center,
    ];
    if (all.isEmpty) return;
    final projection = _Projection(all, size);
    final grid = Paint()
      ..color = const Color(0xFF24313D)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final x = size.width * index / 4;
      final y = size.height * index / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (frame.landingArea case final area?) {
      final centre = projection.offset(area.center);
      final radius = math
          .max(8, projection.pixelsPerMetre * area.radiusMeters)
          .toDouble();
      canvas.drawCircle(
        centre,
        radius,
        Paint()..color = const Color(0x3342C9E8),
      );
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = const Color(0xFF42C9E8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    for (final track in replay.tracks) {
      final current = frame.samples[track.id];
      if (current == null) continue;
      final visible = track.samples
          .where((sample) => !sample.recordedAt.isAfter(frame.recordedAt))
          .toList();
      final color = _trackColors[track.kind]!;
      if (visible.length >= 2) {
        final path = Path()
          ..moveTo(
            projection.offset(visible.first.position).dx,
            projection.offset(visible.first.position).dy,
          );
        for (final sample in visible.skip(1)) {
          final point = projection.offset(sample.position);
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = track.kind == FlightReplayTrackKind.balloon ? 4 : 3
            ..strokeCap = StrokeCap.round,
        );
      }
      final marker = projection.offset(current.position);
      canvas.drawCircle(marker, 8, Paint()..color = color);
      canvas.drawCircle(
        marker,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_FlightReplayPainter oldDelegate) =>
      oldDelegate.frame.recordedAt != frame.recordedAt;
}

class _Projection {
  _Projection(List<GeoPoint> points, this.size) {
    final meanLatitude =
        points
            .map((point) => point.latitude)
            .reduce((left, right) => left + right) /
        points.length;
    longitudeScale = math.cos(meanLatitude * math.pi / 180).abs();
    final xs = points.map((point) => point.longitude * longitudeScale).toList();
    final ys = points.map((point) => point.latitude).toList();
    minX = xs.reduce(math.min);
    maxX = xs.reduce(math.max);
    minY = ys.reduce(math.min);
    maxY = ys.reduce(math.max);
    if ((maxX - minX).abs() < 0.0001) maxX = minX + 0.0001;
    if ((maxY - minY).abs() < 0.0001) maxY = minY + 0.0001;
    pixelsPerMetre = math.min(
      (size.width - 40) / ((maxX - minX) * 111320),
      (size.height - 40) / ((maxY - minY) * 111320),
    );
  }

  final Size size;
  late final double longitudeScale;
  late double minX;
  late double maxX;
  late double minY;
  late double maxY;
  late final double pixelsPerMetre;

  Offset offset(GeoPoint point) {
    final x = point.longitude * longitudeScale;
    return Offset(
      20 + (x - minX) / (maxX - minX) * (size.width - 40),
      size.height -
          20 -
          (point.latitude - minY) / (maxY - minY) * (size.height - 40),
    );
  }
}

String _duration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _clock(DateTime value) =>
    '${value.toLocal().hour.toString().padLeft(2, '0')}:'
    '${value.toLocal().minute.toString().padLeft(2, '0')}';
