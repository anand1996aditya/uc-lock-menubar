# Changelog

## 1.4.7 — 23 Oct 2026

- The UC Lock bearer token now lives in the macOS Keychain (service `com.secureu.uclock`), not in `config.json`.
- Existing sessions migrate on first launch: the token moves to the Keychain and is blanked from the JSON. Other settings are kept.
- `config.json` now holds only non-secret settings and keeps `0600` permissions. The Settings screen saves the token to the Keychain.
- Diagnostics logs and `status.json` are written with `0600`; older `0644` files are repaired on launch.
- Ad-hoc signing is unchanged. Notarisation needs an Apple Developer ID and is not part of this release.

## 1.4.6 — 22 Oct 2026

- Battery reading is white for maximum readability; a thin coloured ring keeps the warning cue.

## 1.4.5 — 22 Oct 2026

- Battery warning now uses a deeper red, with a stronger border and lighter pill.

## 1.4.4 — 22 Oct 2026

- Header card is lighter and warmer, so the red battery warning reads clearly.
- Battery pill has a neutral background, a coloured border and a softer red.

## 1.4.3 — 22 Oct 2026

- Removed the divider between the header card and the activity list.

## 1.4.2 — 22 Oct 2026

- Removed the pulsing artwork animation; the transparent cut-out and static glow remain.

## 1.4.1 — 22 Oct 2026

- Transparent cut-out now uses correct premultiplied alpha, so no white fringe remains.

## 1.4.0 — 22 Oct 2026

- Lock artwork background is removed locally, so the product floats on the card.
- Soft pulsing glow, floor reflection and bottom fade behind the artwork.
- No image or certificate leaves the Mac during processing.

## 1.3.1 — 22 Oct 2026

- Unlock timestamps are parsed from the time part before the method, so history sorts correctly.

## 1.3.0 — 22 Oct 2026

- Activity history is stored locally for 72 hours, then pruned and deleted.
- Redesigned header card with a soft gradient fade and artwork glow.
- Last unlock split into time, person and method so nothing is truncated.
- Self-tests cover history persistence, pruning and unlock detail extraction.

## 1.2.1 — 22 Oct 2026

- Refresh, Settings and Quit are real buttons; Refresh is disabled while loading.
- Doorbell card Dismiss and Open UC Lock are real buttons.
- Settings blocks an empty token and rejects non-hex or too-short device and appliance ids.
- Self-tests cover identifier validation.

## 1.2.0 — 22 Oct 2026

- Menu bar mark rebuilt from the official UC app icon, with no bell substitution.
- Status item rebuilds after display changes and wake so it cannot be stranded.
- Family portrait framing fixed for dad, mom and self.
- Local family portrait configuration in Application Support, never in the repository.
- Offline self-tests for config, parser, device, family fallback and freshness.

## 1.1.0 — 22 Oct 2026

- Family portraits for fingerprint unlocks when the event has no photo.
- Configurable portrait list, stored locally in Application Support.
- Menu bar icon rebuilt from the official UC mark, with no bell substitution.
- Status item rebuilds after display changes and wake, so it cannot be stranded.
- Sanitised build: no credentials, device IDs or personal photos in the repository.

## 1.0.0 — 22 Oct 2026

- Initial menu bar app: battery, status line, activity feed, door bell photos.
