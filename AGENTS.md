# Collaboration Rules

All contributors, including Codex and human collaborators, must read this file and `ARCHITECTURE.md` before changing code.

## Required workflow

1. Start from the latest GitHub `main` and inspect the worktree before editing.
2. Read `ARCHITECTURE.md` to identify the owning layer and files.
3. Preserve existing collaborator work and keep changes scoped to the requested feature.
4. Keep UI, state transitions, persistence, and domain models separate.
5. Build or run focused checks before proposing a commit.
6. Update `ARCHITECTURE.md` whenever file responsibilities or data flow change.
7. Before uploading or pushing to GitHub, run the unified validation set: a
   macOS Debug build, iOS device and simulator Swift type checks (and a full
   iOS build when simulator runtimes are available), plus the relevant
   WeChat mini-program check when that client changed. Record any environment
   limitation instead of describing a blocked build as successful.

## Architecture principles

- High cohesion: a type or file owns one clear area of behavior.
- Low coupling: views request state changes through `AppState` methods instead of writing persistence directly.
- SwiftUI views render state and collect input; `AppState` validates state transitions and persists user data.
- Shared styling stays in reusable extensions or components rather than being copied between screens.

## Protected behavior

- Weight records, goal weight, trend history, activities, and local persistence must keep working.
- Weight values are stored canonically in kilograms; user-facing weight
  records and goals support switching between 公斤 and 斤 (`1 公斤 = 2 斤`)
  without changing history. Legacy `kg/g` preferences must remain decodable.
- Weight above the goal uses progressively stronger red tones.
- The iOS app and WeChat mini program are separate entry points; do not remove or replace one while editing the other.

## Git and release policy

- Local edits and Xcode builds do not automatically upload to GitHub.
- Do not push or merge to `main` without explicit user confirmation.
- A GitHub upload must happen only after the unified validation in the required
  workflow has completed or its environment limitation is explicitly recorded.
- A GitHub push or merge does not publish an App Store release.
- App Store, TestFlight, or Xcode Cloud releases require a separate, explicit release action.

## Change summary and TestFlight notes

- Before each GitHub commit, prepare a concise summary covering the user-visible changes, affected areas, and verification performed.
- Put that summary in the commit message body so the change is easy to identify in GitHub history.
- For a TestFlight build, reuse the same summary in App Store Connect's “测试信息 / What to Test” field; GitHub commit messages are not copied to TestFlight automatically.
- Keep the summary factual and mention known limitations or items that still need testing.
