# Changelog

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
