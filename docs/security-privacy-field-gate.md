# Security, privacy, retention and field gate

Status: implementation complete for automated checks; physical mixed-device and
vehicle evidence remains a release gate.

This is the release boundary for issue #11. It describes what a flight code can
do, what the relay can see, exactly how long data remains, and what evidence a
real field run must record. It does not turn simulator evidence into a claim
about background GPS, Bluetooth, CarPlay, battery or thermal behaviour.

## Authority and encryption

- A new operation creates an Ed25519 identity in iOS Keychain or Android
  encrypted storage. Its public key is carried by the `bc2` invitation; the
  32-byte private seed never leaves that device.
- Every schema-two event has two proofs: the existing operation HMAC for bounded
  transport access and an Ed25519 author signature. Product reducers accept an
  event only after both proofs and the device-authority policy pass.
- A device ID is derived from the operation ID and its first public key. A copied
  flight code cannot select another device ID and sign as that device.
- Pilot-only event types are accepted only from the current pilot key. Pilot
  handover requires an offer by the current pilot and acceptance by the named
  balloon-crew key.
- The pilot can revoke another device from the crew roster. Later events and live
  positions from that device are inert. A device can rotate its key; the old key
  signs the rotation and the replacement key signs a detached possession proof.
- Nearby and internet live-position snapshots carry their own short-lived
  Ed25519 proof. They are not trusted merely because a sender knows the shared
  flight code.
- Internet transport requires TLS. Event bodies, live snapshots, bootstrap
  credentials and crew-room operation data are AES-256-GCM encrypted at rest;
  lookup credentials are stored as hashes or keyed blind indexes.

The relay is not an end-to-end opaque store: it decrypts event bodies in memory
to validate bounds and project the cursor-independent membership roster. A
relay operator with the runtime encryption key is therefore inside the trust
boundary. Logs and metrics remain outside it and contain no body, credential,
provider key or coordinate. End-to-end payload encryption would require a new
minimal projection protocol and is not claimed by this release.

## Threat model

| Threat | Control | Residual limitation |
| --- | --- | --- |
| Six-digit code is photographed, guessed or reused | Rate-limited lookup; encrypted bootstrap; schema-two device signatures; self-certifying first device ID | A valid invite still permits a new non-pilot crew device to join until the operation expires or the pilot revokes it |
| Code holder impersonates pilot or another device | Ed25519 author proof plus root/current-key authority graph | A compromised unlocked participant phone can act as that participant until revoked |
| Code holder spoofs a live position | Position-specific short-lived signature; current-key and revocation check on recipients | A compromised device can lie about its own sensor reading; source age/accuracy remain visible |
| Relay or database is copied | TLS in transit; AES-GCM bodies; hash-only bearer token; keyed alias index | Runtime relay operator is trusted as described above |
| Event is replayed, duplicated or reordered | Signed immutable IDs, idempotency, deduplication and deterministic event ordering | A delayed but unexpired event may arrive as `relayed`; freshness reducers must not label it live |
| Key is lost or suspected compromised | Pilot revocation and two-key rotation protocol | Revocation must reach a recipient before that recipient can reject later traffic |
| Observer link leaks | Separate bounded credential, reduced observer surface, revocation and expiry | Observer functionality has its own issue #14 evidence gate |
| Personal/contact data reaches diagnostics | Personal-share stores stay outside diagnostics; ordinary failures log only error types; flight-code headers are stripped from diagnostic files | Opt-in diagnostic exports contain the recording phone's manoeuvre points and must be shared deliberately |
| Old local data accumulates | Explicit deletion, 24-hour ended-flight journal window, bounded five-file opt-in diagnostics, user-controlled previous-flight deletion | Deliberately retained exports and previous-flight archives remain until their owner deletes them |

## Exact retention and deletion

Durations below are defaults and maximums enforced by code. Operators may set a
shorter value, never a silent longer one beyond the configured validation range.

| Data | Retention | Deletion trigger |
| --- | --- | --- |
| Internet live position | 45 seconds | TTL, explicit clear, flight end or whole-flight cleanup |
| Relayed location event | 30 minutes | Event TTL or whole-flight cleanup |
| Status and personal contact-share events | 2 hours | Event TTL; unused received personal shares are also purged locally at flight end |
| Hazard events | 24 hours | Event TTL or whole-flight cleanup |
| Other operation events and encrypted join bootstrap | Up to 72 hours while active | Last activity moves the active deadline; flight end shortens it to at most 24 hours |
| Idempotency replay | 24 hours | Cleanup job |
| Ended operation, including dependent positions, observers and events | At most 24 hours after end | Scheduled cleanup transaction |
| Stored web plan | 30 days | Plan cleanup job |
| Active local journal and secure device key | For the active operation | Leave/delete clears the session, journal and key; end archives then clears the journal after 24 hours |
| Local previous-flight archive | Until its owner deletes it | Previous flights > Delete |
| Opt-in navigation diagnostic export | Newest five files; feature compiled out and off by default | Automatic oldest-first pruning; app-data deletion; flight codes are never written |
| Private land-access note | Device-local until delete or its review/retention workflow | Per-record edit/delete; governed separately by `land-access-notes-privacy.md` |

Leaving one phone does not delete the shared server operation, because any
participant may still be recovering the balloon. Ending the flight starts the
server's 24-hour recovery deletion window. An immediate shared delete is not
offered to a bearer-token holder: allowing any copied group credential to erase
every crew member's recovery state would be a data-loss vulnerability.

Automated evidence:

- local leave/delete/key removal: `ride_controller_test.dart`,
  `device_authority_controller_test.dart`;
- received contact purge: `ride_controller_test.dart`;
- server end/TTL/cascade cleanup: `test_sync.py`,
  `test_pre_start_presence.py`, `test_additive_event_types.py`;
- stale/relayed labels: `simulator_replay_matrix_test.dart`,
  `live_flight_projection_test.dart`;
- log/code redaction: `runtime_log_privacy_test.dart` and production-disabled
  Uvicorn access logs.

## Driver/pilot distraction and accessibility review

- Driver surfaces are voice-first. Retarget, mute and stop are bounded actions;
  route guidance ends at a lawful road rendezvous and never at a raw airborne or
  off-road coordinate.
- Pilot surfaces omit speed limits, turn prompts and route manipulation while
  airborne. Landing and handover actions require deliberate confirmation.
- Every freshness/authority state has text and semantics, not colour alone.
  Altitude trails retain a legend and unavailable-altitude treatment; touch
  targets use platform sizing and dynamic text must not hide the primary map.
- Simulator and widget checks are necessary but do not prove usability while
  driving or flying. Physical evidence must record unsafe interaction attempts,
  missed spoken prompts and any task that required touching the phone while the
  vehicle was moving.

## Physical release gate

Every real run must use [the field-run record](field-run-template.md). Public
release remains blocked until the mixed iOS/Android matrix covers foreground and
background GPS/altitude, internet loss/recovery, Nearby transport, battery,
thermal state, Bluetooth audio, a physical CarPlay head unit, accessibility and
end-to-recovery deletion. Failures are evidence, not omitted runs.
