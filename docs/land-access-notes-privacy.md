# Private land-access notes: privacy and abuse boundary

Status: implemented as a device-local v1. This is an engineering record, not
legal advice. A club or commercial operator must document its own controller,
lawful basis and retention decision before deploying the feature to its crew.

## Purpose and data flow

The sole purpose is helping a recovery crew remember where to seek permission
and how to approach a field after a landing. A record can contain an indicative
point or polygon, gate/access notes, a factual access outcome, an optional first
name/role/phone number, confirmation and review dates, recorder, provenance and
contact-data consent state.

V1 is deliberately bounded:

- the record is held in the iOS Keychain or Android encrypted-storage boundary
  through `FlutterSecureStorage`;
- it is not an event, analytics property, diagnostic item, notification,
  server request, relay payload or automatic backup;
- the ordinary recovery map can render a local point/outline only after the
  user switches the private layer on, and hides records due for review;
- sharing is an explicit file export encrypted and authenticated with AES-256
  GCM; PBKDF2-HMAC-SHA256 derives the key from a passphrase that is never saved;
- the exporting user must send the passphrase separately and choose the
  recipient. Import is equally deliberate.

An encrypted export is still personal data in the hands of its sender and
recipient. Deleting the local record removes its local export metadata, but
cannot remotely erase a file already sent. The UI tells the user to ask every
recipient to delete such copies.

## Controller, lawful basis and consent

Balloon Crumbs has no account or central land-contact service and does not
receive this data. The person or organisation deciding why the record exists
and who receives it is the controller for that copy. A club/operator should
record the controller name and contact route in its own member notice.

Do not assume that participation in a flight is consent to store a land
contact's details. An operator considering legitimate interests should complete
and retain its own purpose/necessity/balancing assessment. Where consent is the
chosen basis, it must be specific, informed and withdrawable. The app records
whether verbal/written consent was obtained, no consent was recorded, or the
contact requested removal; it does not turn that label into legal validity.

Record the minimum needed. Name, role and phone are optional. Never use free
text for gossip, allegations or sensitive personal information.

## Retention, correction and removal

New records default to a review date 12 months after confirmation; the user may
choose an earlier date. On that date the record disappears from the recovery
map and the active list until it is corrected, renewed or deleted. Operational
policy should prefer deletion when the crew cannot reconfirm the information.

A contact subject can ask the crew member or club that recorded/shared the data
to view, correct or remove it. That user can edit or delete the record on the
device and must notify known export recipients. There is no central Balloon
Crumbs database to search or erase in v1.

## Neutral presentation and limitations

Outcomes are restricted to:

- no outcome recorded;
- ask before vehicle access;
- permission was confirmed;
- vehicle access was declined.

They describe one dated interaction. There is no cooperation rating, public
leaderboard or automatic sharing. A point, drawn outline, HMLR reference or
previous permission never identifies the current owner/occupier, grants access,
or establishes a safe landing area.

## Abuse threat model

| Threat | V1 control | Residual action |
| --- | --- | --- |
| Public landowner directory or reputation score | No server/relay API; local layer off by default; fixed neutral outcomes | Do not screenshot or republish the layer |
| Phone/name leaked through logs or notifications | Domain/store are outside diagnostics, notifications, events and internet clients; contract test scans those boundaries | Report any new serialization path as a release blocker |
| Lost or inspected phone | Keychain/keystore-backed storage; app exposes only the local user's records | Device passcode, OS updates and remote device controls remain the user's responsibility |
| Export intercepted | AES-256-GCM authenticated encryption; separate unsaved 12+ character passphrase | Use a distinct passphrase and separate channel; delete after import |
| Weak or malicious import | Authenticated envelope, bounded KDF settings, schema/size/geometry limits, newest-update conflict rule | Import only from a known crew member |
| Stale permission treated as current | Confirmation/provenance/review visible; expired records hidden from active map | Reconfirm locally before access every time |
| Contact cannot withdraw | Edit/delete and explicit recipient-deletion instructions | Clubs must publish their own controller contact route |
| Free-text harassment or sensitive claims | Purpose copy and 1,000-character bound; no public sharing path | Crew policy and device owner remain responsible for appropriate content |

Any future relay sync, club directory, moderation or remote deletion service is
a new privacy product. It requires a separate notice, access controls, audit
trail, correction/erasure workflow, abuse response and legal review before code
or API activation.
