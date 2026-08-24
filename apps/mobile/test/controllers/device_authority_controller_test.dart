import 'dart:math';

import 'package:balloon_crumbs/controllers/ride_controller.dart';
import 'package:balloon_crumbs/data/in_memory_device_identity_store.dart';
import 'package:balloon_crumbs/data/in_memory_event_store.dart';
import 'package:balloon_crumbs/data/in_memory_session_store.dart';
import 'package:balloon_crumbs/domain/geo_point.dart';
import 'package:balloon_crumbs/domain/ride_event.dart';
import 'package:balloon_crumbs/domain/quick_message.dart';
import 'package:balloon_crumbs/domain/ride_role.dart';
import 'package:balloon_crumbs/domain/rider_location.dart';
import 'package:balloon_crumbs/relay/relay_presence.dart';
import 'package:balloon_crumbs/services/nearby_bridge.dart';
import 'package:balloon_crumbs/services/ride_event_authenticator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production identity path creates restorable schema-two events',
    () async {
      final eventStore = InMemoryEventStore();
      final sessionStore = InMemorySessionStore();
      final identities = InMemoryDeviceIdentityStore();
      var id = 0;
      final controller = RideController(
        eventStore,
        sessionStore,
        const _Nearby(),
        deviceIdentityStore: identities,
        idFactory: () => 'event-${id++}',
        random: Random(7),
        clock: () => DateTime.utc(2026, 8, 24, 12),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.createRide('Pilot');

      final session = controller.session!;
      expect(session.usesDeviceAuthority, isTrue);
      expect(session.localRiderId, startsWith('bcd1_'));
      expect(session.authorityRootPublicKey, session.localDevicePublicKey);
      expect(controller.events, isNotEmpty);
      for (final event in controller.events) {
        expect(event.schemaVersion, 2);
        expect(event.devicePublicKey, session.localDevicePublicKey);
        expect(
          await RideEventAuthenticator.verifyAsync(event, session.inviteSecret),
          isTrue,
        );
        final restored = RideEvent.fromJson(event.toJson());
        expect(
          await RideEventAuthenticator.verifyAsync(
            restored,
            session.inviteSecret,
          ),
          isTrue,
        );
      }

      final restoredController = RideController(
        eventStore,
        sessionStore,
        const _Nearby(),
        deviceIdentityStore: identities,
        idFactory: () => 'restored-${id++}',
      );
      addTearDown(restoredController.dispose);
      await restoredController.initialize();
      expect(restoredController.events, hasLength(controller.events.length));
      expect(restoredController.hasFlightAuthority, isTrue);
    },
  );

  test(
    'schema-one event is rejected inside a device-authority flight',
    () async {
      final eventStore = InMemoryEventStore();
      var id = 0;
      final controller = RideController(
        eventStore,
        InMemorySessionStore(),
        const _Nearby(),
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
        idFactory: () => 'id-${id++}',
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.createRide('Pilot');
      final session = controller.session!;
      final unsigned = RideEvent(
        id: 'legacy-forgery',
        rideId: session.rideId,
        deviceId: session.localRiderId,
        type: RideEventType.rideEnded,
        priority: EventPriority.critical,
        createdAt: DateTime.utc(2026, 8, 24, 13),
        payload: const {},
        signature: '',
      );
      await eventStore.append(
        RideEvent(
          id: unsigned.id,
          rideId: unsigned.rideId,
          deviceId: unsigned.deviceId,
          type: unsigned.type,
          priority: unsigned.priority,
          createdAt: unsigned.createdAt,
          payload: unsigned.payload,
          signature: RideEventAuthenticator.sign(
            unsigned,
            session.inviteSecret,
          ),
        ),
      );

      await controller.reloadEvents();
      expect(
        controller.events,
        isNot(
          contains(
            predicate<RideEvent>((event) => event.id == 'legacy-forgery'),
          ),
        ),
      );
      expect(controller.rideEnded, isFalse);
    },
  );

  test(
    'local key rotation preserves device identity and survives restore',
    () async {
      final eventStore = InMemoryEventStore();
      final sessionStore = InMemorySessionStore();
      final identities = InMemoryDeviceIdentityStore();
      var id = 0;
      final controller = RideController(
        eventStore,
        sessionStore,
        const _Nearby(),
        deviceIdentityStore: identities,
        idFactory: () => 'rotate-${id++}',
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.createRide('Pilot');
      final deviceId = controller.session!.localRiderId;
      final oldPublicKey = controller.session!.localDevicePublicKey;

      await controller.rotateLocalDeviceAuthority();

      expect(controller.errorMessage, isNull);
      expect(controller.session!.localRiderId, deviceId);
      expect(controller.session!.localDevicePublicKey, isNot(oldPublicKey));
      expect(
        controller.events.where(
          (event) => event.type == RideEventType.deviceAuthorityRotated,
        ),
        hasLength(1),
      );
      await controller.sendQuickMessage(QuickMessage.stopped);
      expect(controller.errorMessage, isNull);

      final restored = RideController(
        eventStore,
        sessionStore,
        const _Nearby(),
        deviceIdentityStore: identities,
        idFactory: () => 'restored-${id++}',
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.session!.localRiderId, deviceId);
      expect(restored.events.length, controller.events.length);
    },
  );

  test(
    'a peer cannot bypass proof checks by claiming the local device id',
    () async {
      final now = DateTime.utc(2026, 8, 24, 12);
      final controller = RideController(
        InMemoryEventStore(),
        InMemorySessionStore(),
        const _Nearby(),
        deviceIdentityStore: InMemoryDeviceIdentityStore(),
        clock: () => now,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.createRide('Pilot');
      final session = controller.session!;
      final position = RiderLocation(
        riderId: session.localRiderId,
        displayName: session.displayName,
        role: RideRole.lead,
        sample: LocationSample(
          position: const GeoPoint(latitude: 51.25, longitude: -2.35),
          recordedAt: now,
          accuracyMeters: 4,
        ),
        receivedAt: now,
      );
      final signed = await controller.createAuthenticatedPresence(
        position: position,
        clear: false,
        ttl: const Duration(seconds: 45),
      );

      expect(await controller.verifyAuthenticatedPresence(signed, now), isTrue);
      expect(
        await controller.verifyAuthenticatedPresence(
          RelayPresenceUpdate(
            riderId: session.localRiderId,
            sentAt: now,
            expiresAt: now.add(const Duration(seconds: 45)),
            clear: false,
            position: position,
          ),
          now,
        ),
        isFalse,
      );
    },
  );
}

class _Nearby extends NearbyBridge {
  const _Nearby();

  @override
  Future<NearbyCapabilities> capabilities() async =>
      const NearbyCapabilities.unavailable();
}
