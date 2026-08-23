import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/land_access_note_controller.dart';
import '../../domain/geo_point.dart' as awareness;
import '../../domain/imported_route.dart' as route_domain;
import '../../domain/land_access_note.dart';
import '../../services/rider_trail_recorder.dart';
import '../map/ride_map_feature.dart';

class LandAccessNotesScreen extends StatefulWidget {
  const LandAccessNotesScreen({
    super.key,
    required this.controller,
    required this.recordedBy,
    this.initialPoint,
    this.enableNativeMap = true,
  });

  final LandAccessNoteController controller;
  final String recordedBy;
  final awareness.GeoPoint? initialPoint;
  final bool enableNativeMap;

  static Future<void> show(
    BuildContext context, {
    required LandAccessNoteController controller,
    required String recordedBy,
    awareness.GeoPoint? initialPoint,
  }) => Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => LandAccessNotesScreen(
        controller: controller,
        recordedBy: recordedBy,
        initialPoint: initialPoint,
      ),
    ),
  );

  @override
  State<LandAccessNotesScreen> createState() => _LandAccessNotesScreenState();
}

class _LandAccessNotesScreenState extends State<LandAccessNotesScreen> {
  bool _showExpired = false;

  @override
  void initState() {
    super.initState();
    if (!widget.controller.loaded) unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Private land access')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final now = DateTime.now().toUtc();
        final notes = widget.controller.notes
            .where((note) => _showExpired || !note.isExpiredAt(now))
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const _PrivacyBoundaryCard(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('add-land-access-note'),
                  onPressed: widget.controller.busy
                      ? null
                      : () => _editNote(context),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add place'),
                ),
                OutlinedButton.icon(
                  key: const Key('import-land-access-notes'),
                  onPressed: widget.controller.busy ? null : _import,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Import encrypted'),
                ),
                OutlinedButton.icon(
                  key: const Key('export-land-access-notes'),
                  onPressed:
                      widget.controller.busy || widget.controller.notes.isEmpty
                      ? null
                      : _exportAll,
                  icon: const Icon(Icons.lock_outlined),
                  label: const Text('Export encrypted'),
                ),
              ],
            ),
            SwitchListTile(
              key: const Key('show-land-access-notes-on-map'),
              contentPadding: EdgeInsets.zero,
              value: widget.controller.showOnMap,
              title: const Text('Show active notes on recovery map'),
              subtitle: const Text(
                'Private points and outlines stay on this phone and hide at their review date.',
              ),
              onChanged: widget.controller.setShowOnMap,
            ),
            SwitchListTile(
              key: const Key('show-expired-land-access-notes'),
              contentPadding: EdgeInsets.zero,
              value: _showExpired,
              title: const Text('Show notes due for review'),
              subtitle: const Text(
                'Expired notes are hidden from the map by default.',
              ),
              onChanged: (value) => setState(() => _showExpired = value),
            ),
            if (widget.controller.errorMessage case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  error,
                  style: const TextStyle(color: Color(0xFFFF9AAB)),
                ),
              ),
            if (!widget.controller.loaded && widget.controller.busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (notes.isEmpty)
              const _EmptyLandAccessNotes()
            else
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LandAccessNoteCard(
                    note: note,
                    onEdit: () => _editNote(context, note: note),
                    onDelete: () => _delete(note),
                  ),
                ),
          ],
        );
      },
    ),
  );

  Future<void> _editNote(BuildContext context, {LandAccessNote? note}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LandAccessNoteEditor(
          controller: widget.controller,
          recordedBy: widget.recordedBy,
          note: note,
          initialPoint: widget.initialPoint,
          enableNativeMap: widget.enableNativeMap,
        ),
      ),
    );
  }

  Future<void> _delete(LandAccessNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this private note?'),
        content: const Text(
          'This removes the note and its export history from this phone. '
          'It cannot erase copies you deliberately sent; ask every recipient '
          'to delete those copies as well.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.delete(note.id);
  }

  Future<void> _exportAll() async {
    final passphrase = await _askForPassphrase(
      title: 'Encrypt private notes',
      explanation:
          'Choose at least 12 characters and send the passphrase separately. It is not saved.',
      confirmation: true,
    );
    if (passphrase == null) return;
    final exported = await widget.controller.export(
      noteIds: widget.controller.notes.map((note) => note.id),
      passphrase: passphrase,
    );
    if (exported == null || !mounted) return;
    final date = exported.createdAt.toIso8601String().split('T').first;
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Encrypted Balloon Crumbs land access notes',
        text:
            'Private encrypted land access notes. Send the passphrase separately and delete the file when no longer needed.',
        files: [
          XFile.fromData(
            exported.contents,
            mimeType: 'application/vnd.balloon-crumbs.land-access+json',
            name: 'balloon-crumbs-land-access-$date.bcland',
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    const type = XTypeGroup(
      label: 'Balloon Crumbs private notes',
      extensions: ['bcland'],
    );
    final file = await openFile(acceptedTypeGroups: const [type]);
    if (file == null || !mounted) return;
    final passphrase = await _askForPassphrase(
      title: 'Open encrypted notes',
      explanation:
          'Enter the passphrase supplied by the exporting crew member. It is not saved.',
    );
    if (passphrase == null) return;
    final imported = await widget.controller.import(
      Uint8List.fromList(await file.readAsBytes()),
      passphrase,
    );
    if (!mounted || widget.controller.errorMessage != null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$imported private note${imported == 1 ? '' : 's'} imported.',
        ),
      ),
    );
  }

  Future<String?> _askForPassphrase({
    required String title,
    required String explanation,
    bool confirmation = false,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(explanation),
              const SizedBox(height: 12),
              TextField(
                key: const Key('land-access-passphrase'),
                controller: first,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Passphrase'),
              ),
              if (confirmation) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('land-access-passphrase-confirmation'),
                  controller: second,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Confirm passphrase',
                  ),
                ),
              ],
              if (error case final message?) ...[
                const SizedBox(height: 8),
                Text(message, style: const TextStyle(color: Color(0xFFFF9AAB))),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = first.text;
                if (value.runes.length < 12) {
                  setDialogState(() => error = 'Use at least 12 characters.');
                  return;
                }
                if (confirmation && value != second.text) {
                  setDialogState(() => error = 'The passphrases do not match.');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: Text(confirmation ? 'Encrypt' : 'Open'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }
}

class LandAccessNoteEditor extends StatefulWidget {
  const LandAccessNoteEditor({
    super.key,
    required this.controller,
    required this.recordedBy,
    this.note,
    this.initialPoint,
    this.enableNativeMap = true,
  });

  final LandAccessNoteController controller;
  final String recordedBy;
  final LandAccessNote? note;
  final awareness.GeoPoint? initialPoint;
  final bool enableNativeMap;

  @override
  State<LandAccessNoteEditor> createState() => _LandAccessNoteEditorState();
}

class _LandAccessNoteEditorState extends State<LandAccessNoteEditor> {
  late LandAccessGeometryKind _kind;
  late List<awareness.GeoPoint> _points;
  late LandAccessOutcome _outcome;
  late LandAccessProvenance _provenance;
  late LandAccessConsentStatus _consentStatus;
  late DateTime _confirmedAt;
  late DateTime _reviewAfter;
  late final TextEditingController _firstName;
  late final TextEditingController _contactRole;
  late final TextEditingController _phone;
  late final TextEditingController _gateNotes;
  late final ValueNotifier<route_domain.GeoPoint?> _mapAnchor;
  final _markers = ValueNotifier<List<MapOverlayMarker>>(const []);
  final _traces = ValueNotifier<List<MapOverlayTrace>>(const []);
  bool _privacyAcknowledged = false;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _kind = note?.geometry.kind ?? LandAccessGeometryKind.point;
    _points = [...?note?.geometry.points];
    _outcome = note?.outcome ?? LandAccessOutcome.unknown;
    _provenance = note?.provenance ?? LandAccessProvenance.crewObservation;
    _consentStatus = note?.consentStatus ?? LandAccessConsentStatus.notRecorded;
    _confirmedAt = note?.confirmedAt ?? DateTime.now().toUtc();
    _reviewAfter =
        note?.reviewAfter ?? _confirmedAt.add(const Duration(days: 365));
    _firstName = TextEditingController(text: note?.firstName);
    _contactRole = TextEditingController(text: note?.contactRole);
    _phone = TextEditingController(text: note?.phoneNumber);
    _gateNotes = TextEditingController(text: note?.gateNotes);
    final anchor = _points.firstOrNull ?? widget.initialPoint;
    _mapAnchor = ValueNotifier(
      anchor == null
          ? null
          : route_domain.GeoPoint(
              latitude: anchor.latitude,
              longitude: anchor.longitude,
            ),
    );
    _refreshGeometryOverlay();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _contactRole.dispose();
    _phone.dispose();
    _gateNotes.dispose();
    _mapAnchor.dispose();
    _markers.dispose();
    _traces.dispose();
    super.dispose();
  }

  bool get _geometryValid => switch (_kind) {
    LandAccessGeometryKind.point => _points.length == 1,
    LandAccessGeometryKind.polygon => _points.length >= 3,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.note == null
            ? 'Add private access note'
            : 'Edit private access note',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const Text(
          'Tap the map to place an access point, or add at least three corners '
          'for a field boundary. Boundaries are indicative and never identify '
          'an owner or grant access.',
          style: TextStyle(color: Color(0xFFB8C2CF)),
        ),
        const SizedBox(height: 12),
        SegmentedButton<LandAccessGeometryKind>(
          key: const Key('land-access-geometry-kind'),
          segments: const [
            ButtonSegment(
              value: LandAccessGeometryKind.point,
              icon: Icon(Icons.place_outlined),
              label: Text('Point'),
            ),
            ButtonSegment(
              value: LandAccessGeometryKind.polygon,
              icon: Icon(Icons.polyline_outlined),
              label: Text('Field outline'),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (values) {
            setState(() {
              _kind = values.single;
              if (_kind == LandAccessGeometryKind.point && _points.length > 1) {
                _points = [_points.last];
              }
              _refreshGeometryOverlay();
            });
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 330,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: widget.enableNativeMap
                ? RideMapFeature.fromEnvironment(
                    key: const Key('land-access-map-editor'),
                    currentPosition: _mapAnchor,
                    overlayMarkers: _markers,
                    riderTrails: _traces,
                    showRouteProgress: false,
                    canEditRoute: false,
                    onMapTap: _addPoint,
                  )
                : ColoredBox(
                    key: const Key('land-access-map-editor-placeholder'),
                    color: const Color(0xFF111820),
                    child: Center(
                      child: Text(
                        '${_points.length} map point${_points.length == 1 ? '' : 's'} selected',
                      ),
                    ),
                  ),
          ),
        ),
        Row(
          children: [
            Text('${_points.length} point${_points.length == 1 ? '' : 's'}'),
            const Spacer(),
            TextButton.icon(
              key: const Key('undo-land-access-point'),
              onPressed: _points.isEmpty ? null : _undoPoint,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
            ),
            TextButton(
              key: const Key('clear-land-access-points'),
              onPressed: _points.isEmpty ? null : _clearPoints,
              child: const Text('Clear'),
            ),
          ],
        ),
        DropdownButtonFormField<LandAccessOutcome>(
          key: const Key('land-access-outcome'),
          initialValue: _outcome,
          decoration: const InputDecoration(labelText: 'Access outcome'),
          items: LandAccessOutcome.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_outcomeLabel(value)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            setState(() {
              _outcome = value ?? _outcome;
              _refreshGeometryOverlay();
            });
          },
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('land-access-gate-notes'),
          controller: _gateNotes,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Gate or access notes',
            hintText: 'Which gate, where to park, who to ask',
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: const Key('land-access-first-name'),
          controller: _firstName,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'First name (optional)'),
        ),
        TextField(
          key: const Key('land-access-contact-role'),
          controller: _contactRole,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Role (optional)',
            hintText: 'Owner, occupier, farm manager',
          ),
        ),
        TextField(
          key: const Key('land-access-phone'),
          controller: _phone,
          maxLength: 40,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number (optional)',
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<LandAccessProvenance>(
          key: const Key('land-access-provenance'),
          initialValue: _provenance,
          decoration: const InputDecoration(
            labelText: 'How was this confirmed?',
          ),
          items: LandAccessProvenance.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_provenanceLabel(value)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) =>
              setState(() => _provenance = value ?? _provenance),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<LandAccessConsentStatus>(
          key: const Key('land-access-consent'),
          initialValue: _consentStatus,
          decoration: const InputDecoration(labelText: 'Contact-data consent'),
          items: LandAccessConsentStatus.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_consentLabel(value)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) =>
              setState(() => _consentStatus = value ?? _consentStatus),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text('Confirmed ${_formatDate(_confirmedAt)}'),
          subtitle: Text('Review or delete by ${_formatDate(_reviewAfter)}'),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDates,
        ),
        Card(
          color: const Color(0xFF1D2A35),
          child: CheckboxListTile(
            key: const Key('land-access-privacy-acknowledgement'),
            value: _privacyAcknowledged,
            onChanged: (value) =>
                setState(() => _privacyAcknowledged = value ?? false),
            title: const Text('Save privately on this phone'),
            subtitle: const Text(
              'Purpose: recovery access. Audience: this phone unless I make an '
              'encrypted export. Retention: hidden at the review date until I '
              'correct, renew or delete it. I have recorded only what is necessary.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('save-land-access-note'),
          onPressed:
              !_privacyAcknowledged || !_geometryValid || widget.controller.busy
              ? null
              : _save,
          icon: const Icon(Icons.lock_outline),
          label: const Text('Save private note'),
        ),
      ],
    ),
  );

  void _addPoint(route_domain.GeoPoint point) {
    setState(() {
      final converted = awareness.GeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (_kind == LandAccessGeometryKind.point) {
        _points = [converted];
      } else if (_points.length < 200) {
        _points = [..._points, converted];
      }
      _refreshGeometryOverlay();
    });
  }

  void _undoPoint() {
    setState(() {
      _points = _points.sublist(0, _points.length - 1);
      _refreshGeometryOverlay();
    });
  }

  void _clearPoints() {
    setState(() {
      _points = [];
      _refreshGeometryOverlay();
    });
  }

  void _refreshGeometryOverlay() {
    final color = _outcomeColor(_outcome);
    _markers.value = [
      for (var index = 0; index < _points.length; index += 1)
        MapOverlayMarker(
          id: 'land-access-editor-point-$index',
          point: route_domain.GeoPoint(
            latitude: _points[index].latitude,
            longitude: _points[index].longitude,
          ),
          label: _kind == LandAccessGeometryKind.point
              ? 'Access point'
              : 'Field corner ${index + 1}',
          icon: _kind == LandAccessGeometryKind.point
              ? Icons.place_outlined
              : Icons.circle,
          color: color,
        ),
    ];
    _traces.value =
        _kind == LandAccessGeometryKind.polygon && _points.length >= 2
        ? [
            MapOverlayTrace(
              id: 'land-access-editor-outline',
              label: 'Private indicative field outline',
              kind: RiderTrailKind.operationalBoundary,
              color: color,
              points: [
                for (final point in _points)
                  route_domain.GeoPoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                  ),
                if (_points.length >= 3)
                  route_domain.GeoPoint(
                    latitude: _points.first.latitude,
                    longitude: _points.first.longitude,
                  ),
              ],
            ),
          ]
        : const [];
  }

  Future<void> _pickDates() async {
    final confirmed = await showDatePicker(
      context: context,
      firstDate: DateTime.utc(2020),
      lastDate: DateTime.now().toUtc().add(const Duration(days: 1)),
      initialDate: _confirmedAt,
      helpText: 'When was this information confirmed?',
    );
    if (confirmed == null || !mounted) return;
    final review = await showDatePicker(
      context: context,
      firstDate: confirmed,
      lastDate: confirmed.add(const Duration(days: 730)),
      initialDate: _reviewAfter.isBefore(confirmed) ? confirmed : _reviewAfter,
      helpText: 'When should the crew review or delete it?',
    );
    if (review == null) return;
    setState(() {
      _confirmedAt = DateTime.utc(
        confirmed.year,
        confirmed.month,
        confirmed.day,
      );
      _reviewAfter = DateTime.utc(review.year, review.month, review.day);
    });
  }

  Future<void> _save() async {
    final existing = widget.note;
    final now = DateTime.now().toUtc();
    await widget.controller.save(
      LandAccessNote(
        id: existing?.id ?? widget.controller.newId(),
        geometry: LandAccessGeometry(kind: _kind, points: _points),
        outcome: _outcome,
        firstName: _optional(_firstName.text),
        contactRole: _optional(_contactRole.text),
        phoneNumber: _optional(_phone.text),
        gateNotes: _gateNotes.text.trim(),
        confirmedAt: _confirmedAt,
        recordedBy: widget.recordedBy.trim().isEmpty
            ? 'This device'
            : widget.recordedBy.trim(),
        provenance: _provenance,
        consentStatus: _consentStatus,
        reviewAfter: _reviewAfter,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    if (mounted && widget.controller.errorMessage == null) {
      Navigator.pop(context);
    }
  }
}

class _PrivacyBoundaryCard extends StatelessWidget {
  const _PrivacyBoundaryCard();

  @override
  Widget build(BuildContext context) => const Card(
    color: Color(0xFF1D2A35),
    child: Padding(
      padding: EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Private recovery memory',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            'These notes are encrypted on this device. They are never uploaded, '
            'relayed, scored publicly or treated as permission. Sharing requires '
            'an explicit encrypted export with a separate passphrase.',
          ),
          SizedBox(height: 6),
          Text(
            'If a named person asks for correction or removal, edit or delete the '
            'record here and ask anyone who received an export to delete it too.',
            style: TextStyle(color: Color(0xFFB8C2CF)),
          ),
        ],
      ),
    ),
  );
}

class _EmptyLandAccessNotes extends StatelessWidget {
  const _EmptyLandAccessNotes();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        Icon(Icons.place_outlined, size: 44, color: Color(0xFF8D98A7)),
        SizedBox(height: 10),
        Text(
          'No private access notes on this phone',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 4),
        Text(
          'Add only details the recovery crew genuinely needs.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _LandAccessNoteCard extends StatelessWidget {
  const _LandAccessNoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final LandAccessNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final contact = [
      ?_optional(note.firstName),
      ?_optional(note.contactRole),
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  note.geometry.kind == LandAccessGeometryKind.point
                      ? Icons.place_outlined
                      : Icons.polyline_outlined,
                  color: _outcomeColor(note.outcome),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _outcomeLabel(note.outcome),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit private note',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete private note',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (note.gateNotes.trim().isNotEmpty) Text(note.gateNotes),
            if (contact.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(contact),
            ],
            if ((note.phoneNumber ?? '').trim().isNotEmpty)
              Text(note.phoneNumber!),
            const SizedBox(height: 8),
            Text(
              'Confirmed ${_formatDate(note.confirmedAt)} · review by ${_formatDate(note.reviewAfter)} · ${_provenanceLabel(note.provenance)}',
              style: const TextStyle(color: Color(0xFF9EABB9), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String _outcomeLabel(LandAccessOutcome outcome) => switch (outcome) {
  LandAccessOutcome.unknown => 'No access outcome recorded',
  LandAccessOutcome.askFirst => 'Ask before vehicle access',
  LandAccessOutcome.permissionConfirmed => 'Permission was confirmed',
  LandAccessOutcome.accessDeclined => 'Vehicle access was declined',
};

Color _outcomeColor(LandAccessOutcome outcome) => switch (outcome) {
  LandAccessOutcome.unknown => const Color(0xFF9EABB9),
  LandAccessOutcome.askFirst => const Color(0xFFFFC857),
  LandAccessOutcome.permissionConfirmed => const Color(0xFF72D5A4),
  LandAccessOutcome.accessDeclined => const Color(0xFFFF8A80),
};

String _provenanceLabel(LandAccessProvenance provenance) =>
    switch (provenance) {
      LandAccessProvenance.crewObservation => 'Crew observation',
      LandAccessProvenance.landContact => 'Land contact',
      LandAccessProvenance.publicReference => 'Public reference',
    };

String _consentLabel(LandAccessConsentStatus consent) => switch (consent) {
  LandAccessConsentStatus.notRecorded => 'No contact-data consent recorded',
  LandAccessConsentStatus.verbal => 'Verbal consent recorded',
  LandAccessConsentStatus.written => 'Written consent recorded',
  LandAccessConsentStatus.contactRequestedRemoval =>
    'Contact requested removal',
};

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
