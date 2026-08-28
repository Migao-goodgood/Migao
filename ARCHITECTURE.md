# Project Map

## Product entry points

| Client | Location | Runtime |
| --- | --- | --- |
| Native Apple app | `ZheBuDeShouSi-iOS/` | SwiftUI in Xcode |
| WeChat mini program | `app.*`, `pages/` | WeChat Developer Tools |

The two clients share product concepts but do not share runtime state or persistence.

## Logical feature map

```text
App
├── AppState              # weight, goal, activity logs, local snapshot
├── RootView              # tab navigation and modal presentation
└── DependencyContainer   # app-level object creation and injection

Features
├── Weight
│   ├── WeightModels      # WeightRecord and goal-derived values
│   ├── WeightStore       # AppState actions and persistence boundary
│   └── WeightViews       # weight cards, wheel picker, trend chart
├── BodyMeasurements
│   ├── BodyMeasurementModels
│   ├── BodyMeasurementStore
│   └── BodyMeasurementViews
├── Habits
│   ├── HabitModels
│   ├── HabitStore
│   └── HabitViews
└── HealthKit
    ├── HealthKitClient   # platform API adapter
    ├── HealthKitMapper   # sample -> domain conversion
    └── HealthSyncCoordinator

Core
├── Persistence           # UserDefaults snapshots
├── DesignSystem          # shared kawaii colors and view modifiers
├── DateFormatting
└── Permissions           # HealthKit authorization boundary
```

The current repository keeps the original collaborator-facing SwiftUI presentation in `ContentView.swift` and the original weight store in `Models.swift`; the logical ownership above is the boundary to preserve while those files are split incrementally. New HealthKit code already follows the adapter/coordinator boundary.

## iOS files

- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/ZheBuDeShouSiApp.swift`: application entry point; creates and injects `AppState`, `HealthStore`, and `HealthSyncCoordinator`.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Models.swift`: domain enums/models, `AppState`, derived progress and color rules, user actions, and `UserDefaults` snapshot persistence.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/ContentView.swift`: app navigation and SwiftUI presentation. Screens read `AppState`, collect user input, and invoke state methods.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Health/Domain/HealthModels.swift`: body-measurement and habit value objects, including source metadata and presentation labels.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Health/Application/HealthStore.swift`: local persistence and use cases for body measurements and daily habit completion. This store is independent from weight state so HealthKit can be added behind a separate adapter later.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Infrastructure/HealthKitClient.swift`: the platform adapter for HealthKit authorization and read-only queries. The fallback implementation keeps macOS builds and previews independent from the iOS-only framework.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Infrastructure/HealthKitMapper.swift`: converts HealthKit quantities into app-level samples and keeps unit conversion out of stores and views.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Application/HealthSyncCoordinator.swift`: coordinates authorization, a bounded 90-day import, deduplication, and fan-out into the weight, body-measurement, and habit stores.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/ZheBuDeShouSi.entitlements`: enables the HealthKit capability for iPhone and iPad signing.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Assets.xcassets/`: icons and image assets.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi.xcodeproj/`: Xcode targets, platforms, signing, and build settings.

## Current iOS presentation

- `HomeView` in `ContentView.swift`: a two-part weight workspace modeled on the supplied references. The upper plan card shows initial/current/goal weight and progress; the lower panel shows the trend line followed by date-grouped weight history. It intentionally does not duplicate habit summaries or activity logs.
- `TrendView` in `ContentView.swift`: white trend workspace with date-period filters, weight/goal chart, stage analysis, weight history, and a separate body-measurement mode. Weight chart data comes from `AppState.records`; body-measurement data comes from `HealthStore`.
- `HabitsView` in `ContentView.swift`: renders all seven habit rows with a record action. Meal, exercise, and water keep their existing detailed record flow; sleep, bowel movement, medication, and menstrual-cycle notes use `HabitRecordModal` and `HealthStore.recordHabit(_:,on:note:)`.
- `BottomNav` in `ContentView.swift`: persistent navigation for home, trend, habits, profile, plus the central weigh action that opens the existing weight-record modal.

## iOS state flow

`ZheBuDeShouSiApp` creates `AppState`, `HealthStore`, and `HealthSyncCoordinator` -> injects them into `ContentView` -> weight screens call `AppState` actions while habits/body-measurement screens call `HealthStore` actions -> the profile screen asks `HealthSyncCoordinator` to authorize and read HealthKit -> imported samples are deduplicated by their external identifier and handed to the owning store -> each store validates and persists its own snapshot -> observing views refresh independently.

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
- Body measurements and habits use their own `HealthStore` snapshot key; HealthKit imports preserve the original source metadata and deduplicate by the external sample identifier.
- The first HealthKit slice imports body mass, waist circumference, dietary energy, dietary water, exercise time, sleep, and menstrual-flow samples. HealthKit does not provide standard values for every requested body circumference, nor a reliable general-purpose bowel-movement source; hips, arms, thighs, calves, bowel movement, and medication remain manual.
- Cross-client changes must list iOS and mini-program verification separately.
