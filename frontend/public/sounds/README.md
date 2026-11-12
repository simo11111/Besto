# Haunted Camp Sound Assets

Place the original, licensed MP3 assets in this directory using these exact names:
- night-ambience.mp3 (seamless 10–20s loop)
- morning-birds.mp3 (8–12s loop)
- death-sting.mp3 (1–2s)
- save-chime.mp3 (0.5–1.5s)
- vote-click.mp3 (under 0.5s)
- eject-whoosh.mp3 (under 1.5s)
- win-fanfare.mp3 (1–3s)
- lose-drone.mp3 (1–3s)
- role-reveal.mp3 (under 1s)

Target: MP3 mono/stereo 22.05kHz or 44.1kHz, 48–96kbps for short UI sounds, ideally <=100KB per file. Keep source/license attribution in `ATTRIBUTION.md`.

The app preloads these files on entering a game, fades ambient tracks, and falls back to Web Audio synthesized cues if a file is unavailable. The service worker caches sound files on demand so already-loaded audio remains available offline. No empty/fake MP3 files are shipped.
