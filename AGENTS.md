# Collaboration Rules

All contributors, including Codex and human collaborators, must read this file and `ARCHITECTURE.md` before changing code.

## Required workflow

1. Start from the latest GitHub `main` and inspect the worktree before editing.
2. Read `ARCHITECTURE.md` to identify the owning layer and files.
3. Preserve existing collaborator work and keep changes scoped to the requested feature.
4. Keep UI, state transitions, persistence, and domain models separate.
5. Build or run focused checks before proposing a commit.
6. Update `ARCHITECTURE.md` whenever file responsibilities or data flow change.

## Architecture principles

- High cohesion: a type or file owns one clear area of behavior.
- Low coupling: views request state changes through `AppState` methods instead of writing persistence directly.
- SwiftUI views render state and collect input; `AppState` validates state transitions and persists user data.
- Shared styling stays in reusable extensions or components rather than being copied between screens.

## Protected behavior

- Weight records, goal weight, trend history, activities, and local persistence must keep working.
- Weight units are fixed to `kg`.
- Weight above the goal uses progressively stronger red tones.
- The iOS app and WeChat mini program are separate entry points; do not remove or replace one while editing the other.

## Git and release policy

- Local edits and Xcode builds do not automatically upload to GitHub.
- Do not push or merge to `main` without explicit user confirmation.
- A GitHub push or merge does not publish an App Store release.
- App Store, TestFlight, or Xcode Cloud releases require a separate, explicit release action.

