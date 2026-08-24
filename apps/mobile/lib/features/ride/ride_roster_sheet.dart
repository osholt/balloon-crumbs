import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/ride_controller.dart';
import '../../domain/ride_role.dart';
import '../../domain/rider_color.dart';
import '../../services/ride_membership.dart';
import '../map/craft_icon.dart';

enum _RosterFilter { active, attention, left, all }

class RideRosterSheet extends StatefulWidget {
  const RideRosterSheet({
    super.key,
    required this.controller,
    this.legacyPeerRiderIds = const {},
  });

  final RideController controller;

  final Set<String> legacyPeerRiderIds;

  static Future<void> show(
    BuildContext context,
    RideController controller, {
    Set<String> legacyPeerRiderIds = const {},
  }) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RideRosterSheet(
      controller: controller,
      legacyPeerRiderIds: legacyPeerRiderIds,
    ),
  );

  @override
  State<RideRosterSheet> createState() => _RideRosterSheetState();
}

class _RideRosterSheetState extends State<RideRosterSheet> {
  _RosterFilter _filter = _RosterFilter.active;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final all = widget.controller.participants;
      final liveCount = all
          .where((participant) => participant.isIncludedInLiveCount)
          .length;
      final departed = all.where((participant) => participant.hasLeft).length;
      final visible = all.where(_matchesFilter).toList(growable: false)
        ..sort(_compareParticipants);
      return FractionallySizedBox(
        heightFactor: 0.86,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Flight crew',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '$liveCount currently included · ${all.length} recorded',
                          style: const TextStyle(color: Color(0xFF9DA8B6)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close roster',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Shown to everyone, unlike the TEC notice: there is no leader to
            // show it to, and every remaining rider needs to know (#176).
            if (widget.controller.rideHasNoLeader)
              _MissingLeaderNotice(
                onTakeLead: () async {
                  await widget.controller.setRole(RideRole.lead);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            // The record exists; say so where it is not being shown. A rider who
            // has left is the rider a leader may need to look up afterwards.
            if (departed > 0 && !visible.any((rider) => rider.hasLeft))
              _DepartedRidersNotice(
                departed: departed,
                onShow: () => setState(() => _filter = _RosterFilter.left),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_RosterFilter>(
                segments: const [
                  ButtonSegment(
                    value: _RosterFilter.active,
                    icon: Icon(Icons.location_on_outlined),
                    label: Text('Current'),
                  ),
                  ButtonSegment(
                    value: _RosterFilter.attention,
                    icon: Icon(Icons.report_problem_outlined),
                    label: Text('Attention'),
                  ),
                  ButtonSegment(
                    value: _RosterFilter.left,
                    icon: Icon(Icons.logout_outlined),
                    label: Text('Left'),
                  ),
                  ButtonSegment(
                    value: _RosterFilter.all,
                    icon: Icon(Icons.groups_outlined),
                    label: Text('All joined'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.single),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        _filter == _RosterFilter.left
                            ? 'Nobody has left this flight.'
                            : 'No crew match this filter.',
                        style: const TextStyle(color: Color(0xFF9DA8B6)),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('ride-roster-list'),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _ParticipantTile(
                        participant: visible[index],
                        now: DateTime.now(),
                        peerAppIsOlder: widget.legacyPeerRiderIds.contains(
                          visible[index].riderId,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );

  /// The leader may ask any live rider other than themselves who is not the
  /// effective TEC. Before an accepted assignment, a self-selected TEC is
  /// effective; afterwards an older self-selection has been superseded and can
  /// be asked again.
  bool _matchesFilter(RideParticipant participant) => switch (_filter) {
    _RosterFilter.active => participant.isIncludedInLiveCount,
    _RosterFilter.attention =>
      participant.state == RideMembershipState.inactive,
    _RosterFilter.left => participant.hasLeft,
    _RosterFilter.all => true,
  };

  int _compareParticipants(RideParticipant left, RideParticipant right) {
    // Riders still in the ride come first; a departed record is history, and it
    // is kept rather than promoted.
    if (left.hasLeft != right.hasLeft) return left.hasLeft ? 1 : -1;
    final leftAttention = left.state == RideMembershipState.inactive;
    final rightAttention = right.state == RideMembershipState.inactive;
    if (leftAttention != rightAttention) return leftAttention ? -1 : 1;
    if (left.isLocal != right.isLocal) return left.isLocal ? -1 : 1;
    return left.displayName.compareTo(right.displayName);
  }
}

/// Names the missing back-marker for the leader, and both ways to close the gap.
///
/// The leader can now ask a named rider directly (#128). It is still a request
/// the rider accepts, not a silent assignment, so this deliberately says the
/// rider has to accept: a rider who has not noticed they are TEC is worse than
/// no TEC, because the group then believes the back is covered.
/// Shown when a running ride has nobody holding the lead role (#176).
///
/// Offers rather than assigns. Roles in this app are self-selected - the
/// precedent #128 set for the TEC role, where a leader *asks* and the target's
/// own `roleChanged` is what counts - so the group cannot be handed a leader it
/// did not choose, and the app cannot pick one on the strength of who happens to
/// be nearest the front.
class _MissingLeaderNotice extends StatelessWidget {
  const _MissingLeaderNotice({required this.onTakeLead});

  final Future<void> Function() onTakeLead;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Card(
      key: const Key('roster-missing-leader-notice'),
      margin: EdgeInsets.zero,
      color: const Color(0xFF3A2320),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFF8A6B),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This flight has no coordinator',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'The pilot or coordinator has left. Shared route and '
                    'landing-area changes cannot be published until someone '
                    'takes the lead.',
                    style: TextStyle(color: Color(0xFFE4D6D2), height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('roster-take-the-lead-button'),
                    onPressed: () => unawaited(onTakeLead()),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Take the lead'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Says that a departed rider's record is still here, and how to reach it.
///
/// Issue #144: a rider leaving used to erase them from the list a leader was
/// looking at, which is exactly the rider you go back to afterwards when a lost
/// item or a question comes up. They are out of the live group; they are not out
/// of the record.
class _DepartedRidersNotice extends StatelessWidget {
  const _DepartedRidersNotice({required this.departed, required this.onShow});

  final int departed;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
    child: Row(
      key: const Key('roster-departed-notice'),
      children: [
        const Icon(Icons.logout_outlined, size: 18, color: Color(0xFF9DA8B6)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            departed == 1
                ? '1 crew member has left. Their record is kept until this flight ends.'
                : '$departed crew members have left. Their records are kept until '
                      'this flight ends.',
            style: const TextStyle(color: Color(0xFF9DA8B6), height: 1.3),
          ),
        ),
        TextButton(
          key: const Key('roster-show-departed'),
          onPressed: onShow,
          child: const Text('Show'),
        ),
      ],
    ),
  );
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.now,
    this.peerAppIsOlder = false,
  });

  final RideParticipant participant;
  final DateTime now;
  final bool peerAppIsOlder;

  @override
  Widget build(BuildContext context) {
    final role = _roleLabel(participant.role);
    final lastSeen = _lastSeenLabel(participant.lastSeenAt, now);
    // A departed rider's record is only useful if it says where they were last
    // known to be, so an absent position is stated rather than left blank.
    final lastKnownPosition = participant.hasLeft
        ? participant.lastKnownPositionLabel ??
              'No position for this crew member reached this phone'
        : null;
    final rejoin = participant.rejoinLabel;
    final semanticLabel = [
      participant.displayName,
      if (participant.isLocal) 'you',
      role,
      participant.stateLabel,
      'last seen $lastSeen',
      participant.transportLabel,
      ?rejoin,
      ?lastKnownPosition,
      if (peerAppIsOlder) 'app is older',
    ].join(', ');
    return Semantics(
      label: semanticLabel,
      child: ListTile(
        key: Key('roster-rider-${participant.riderId}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        leading: RiderMarkerBadge(
          style: participant.craftStyle,
          symbol: participant.riderSymbol,
          displayName: participant.displayName,
          // Identity colour belongs to the rider, not the role. Role and state
          // remain explicit in text, semantics and status treatment without
          // making the same person change colour between roster and map (#250).
          badgeColor: participant.riderColor.color,
          size: 42,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                '${participant.displayName}${participant.isLocal ? ' (you)' : ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            _StateDot(state: participant.state),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              '$role · ${participant.stateLabel}',
              'Last seen $lastSeen · ${participant.transportLabel}',
              ?rejoin,
              ?lastKnownPosition,
            ].join('\n'),
            style: const TextStyle(color: Color(0xFFA6B0BD), height: 1.35),
          ),
        ),
      ),
    );
  }

  static String _roleLabel(RideRole role) => switch (role) {
    RideRole.lead => 'Lead',
    RideRole.rider => 'Chaser',
  };

  static String _lastSeenLabel(DateTime value, DateTime now) {
    final age = now.difference(value);
    if (age <= const Duration(seconds: 45)) return 'just now';
    if (age < const Duration(hours: 1)) return '${age.inMinutes} min ago';
    if (age < const Duration(hours: 24)) return '${age.inHours} hr ago';
    return '${age.inDays} days ago';
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot({required this.state});

  final RideMembershipState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      RideMembershipState.active => const Color(0xFF59D18C),
      RideMembershipState.joined => const Color(0xFF66AFFF),
      RideMembershipState.inactive => const Color(0xFFFFC857),
      RideMembershipState.left ||
      RideMembershipState.expired => const Color(0xFF7F8A98),
    };
    return Tooltip(
      message: state.name,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
