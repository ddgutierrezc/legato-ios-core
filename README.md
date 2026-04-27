# Legato iOS Native Core (Runtime Integrity v1)

This directory contains the iOS native core used by `@ddgutierrezc/legato-capacitor`.

Current scope includes:
- canonical queue/state/snapshot/event behavior owned by `LegatoiOSPlayerEngine`,
- AVPlayer-backed runtime support via `LegatoiOSAVPlayerPlaybackRuntime`,
- manager boundaries for AVAudioSession / Now Playing / Remote Command integration,
- direct runtime evidence for transport/progress/end/snapshot coherence.

AVPlayer-backed runtime is implemented and active as the default runtime path for iOS foreground audible playback (`LegatoiOSAVPlayerPlaybackRuntime`).

Out of scope for `ios-runtime-playback-v1`:
- full background/interruption lifecycle production hardening,
- broad Android/iOS parity expansion,
- new end-user playback feature additions.

Scope guardrails: `docs/architecture/ios-runtime-playback-v1-scope-guardrails.md`.

This is NOT yet full background/lifecycle production hardening.

## Dependency composition

This module currently uses **manual composition + constructor injection**, not a DI container such as Swinject or Factory.

The canonical composition root is:

- `LegatoiOSCoreDependencies`
- `LegatoiOSCoreFactory.make(...)`

That is the current project standard unless the graph/lifecycle complexity grows enough to justify containerization later.
