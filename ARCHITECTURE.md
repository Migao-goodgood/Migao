# Project Map

## Product entry points

| Client | Location | Runtime |
| --- | --- | --- |
| Native Apple app | `ZheBuDeShouSi-iOS/` | SwiftUI in Xcode |
| WeChat mini program | `app.*`, `pages/` | WeChat Developer Tools |

The two clients share product concepts but do not share runtime state or persistence.

## iOS files

- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/ZheBuDeShouSiApp.swift`: application entry point; creates and injects the shared `AppState`.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Models.swift`: domain enums/models, `AppState`, derived progress and color rules, user actions, and `UserDefaults` snapshot persistence.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/ContentView.swift`: app navigation and SwiftUI presentation. Screens read `AppState`, collect user input, and invoke state methods.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Assets.xcassets/`: icons and image assets.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi.xcodeproj/`: Xcode targets, platforms, signing, and build settings.

## iOS state flow

`ZheBuDeShouSiApp` creates `AppState` -> injects it into `ContentView` -> a screen presents an input modal -> the modal calls an `AppState` action -> `AppState` updates published state and saves a version-tolerant snapshot -> all observing views refresh.

## Goal weight feature

- Owner: `AppState` in `Models.swift`.
- Persisted property: `goalWeight` in the app snapshot.
- Mutation API: `updateGoalWeight(_:)`; this is the only UI-facing way to change the goal.
- Presentation: `WeightHero` displays a tappable goal control and presents `GoalWeightModal` from `ContentView.swift`.
- Consumers: home progress/tone calculations, trend displays, and profile statistics read the same `AppState.goalWeight` value.

## Editing guide

- Visual-only changes belong in SwiftUI views in `ContentView.swift`.
- Rules, validation, derived values, and persistence belong in `Models.swift`.
- New persisted fields must remain compatible with snapshots created by previous app versions.
- Cross-client changes must list iOS and mini-program verification separately.

