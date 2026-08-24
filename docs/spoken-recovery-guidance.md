# Spoken recovery guidance

Status: automated policy and projected controls implemented; physical audio
evidence remains a release gate.

## Driver contract

Road manoeuvres keep the inherited staged scheduler. Balloon recovery state is
a separate, deduplicated channel whose messages use semantic revisions rather
than map-refresh frequency.

| Priority | Event | Driver-facing meaning |
| --- | --- | --- |
| 7 | Arrival | Arriving at a road rendezvous; stop only where lawful and safe; the balloon may be elsewhere |
| 6 | Balloon fix stale | Freeze the last road route; do not imply a live target |
| 5 | Route unavailable | Keep the previous route and assess locally |
| 4 | Fix recovered | Reconsider the road rendezvous |
| 3 | Target or landing intent changed | Name the change and reconsider the route |
| 2 | Explicit recalculation | State that the road rendezvous is being recalculated |
| 1 | First road route | Explain that the endpoint is near the balloon, not the airborne coordinate |

If several events arrive together, only the highest-priority phrase is chosen.
`SpokenGuidanceSpeaker` then refuses the same semantic key twice. Routine
moving-target refreshes do not announce every recalculation: only an explicit
target/landing revision, stale recovery, or driver-requested refresh speaks.

“Alerts only” preserves stale, recovery, target, failure and arrival warnings
while silencing the route overview, recalculation chatter and manoeuvres.
“Muted” suppresses all speech.

iOS declares the `audio` background mode alongside active-flight location and
uses the system `voicePrompt` audio-session mode with temporary ducking and
spoken-audio interruption. These are the platform facilities Apple documents
for short turn-by-turn text-to-speech prompts; physical evidence is still
required before claiming reliability.

## Controls

- The phone flight menu exposes one large **Mute and stop voice** action. It
  changes the saved mode to muted and immediately stops the current utterance.
- The CarPlay recovery map projects the same phone-owned state and exposes one
  speaker button beside map orientation. It cannot drift into a separate native
  preference; reconnect republishes the phone state.
- Settings retains the full Voice on / Alerts only / Muted choice and voice
  selection.

## Automated evidence

- `chase_spoken_guidance_test.dart`: road-endpoint disclosure, simultaneous
  event priority, 20-update churn deduplication, alerts-only classification.
- `spoken_guidance_schedule_test.dart`: staged manoeuvre timing and close-junction
  behaviour.
- `spoken_guidance_test.dart`: engine configuration, mute gates, alert and
  manoeuvre deduplication, stop and OS fallback behaviour.
- `carplay_bridge_test.dart` and `carplay_layout_test.dart`: phone-owned mute
  projection and the one-tap projected control.

## Required physical evidence

Record build, phone/OS, audio route and outcome for each row. A simulator pass
does not close these rows.

| Case | iOS phone | Android phone | CarPlay head unit |
| --- | --- | --- | --- |
| Speaker foreground | | | |
| Bluetooth foreground | | | |
| Incoming-call/audio interruption and recovery | | | |
| Screen locked with permitted background location | | | n/a |
| App background with permitted background location | | | |
| One-tap mute interrupts the current phrase | | | |
| Reconnect restores mute state | n/a | n/a | |

Do not claim background or projected reliability until the applicable rows are
filled with physical-device evidence.
