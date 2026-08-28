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
├── BodyTrend
│   ├── Domain             # InBody snapshots, avatar parameters, mood, assessment rules
│   ├── Application        # local snapshot and avatar preference store
│   ├── Infrastructure     # Vision OCR adapter
│   └── UI                 # timeline, SceneKit avatar, entry and assessment views
└── HealthKit
    ├── HealthKitClient   # platform API adapter
    ├── HealthKitMapper   # sample -> domain conversion
    └── HealthSyncCoordinator

Core
├── Persistence           # UserDefaults snapshots
├── DesignSystem          # shared jelly colors and view modifiers
├── DateFormatting
└── Permissions           # HealthKit authorization boundary
```

The repository keeps the collaborator-facing SwiftUI presentation in `Shared/UI/ContentView.swift` and the weight store in `Shared/Models/Models.swift`; the logical ownership above is the boundary to preserve while these files are split incrementally. New HealthKit code follows the adapter/coordinator boundary.

## iOS files

- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/App/ZheBuDeShouSiApp.swift`: application entry point; creates and injects `AppState`, `HealthStore`, and `HealthSyncCoordinator`.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/Models/Models.swift`: domain enums/models, `AppState`, derived progress and color rules, shared jelly palette, avatar snapshot persistence, user actions, and `UserDefaults` snapshot persistence.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/UI/ContentView.swift`: app navigation and SwiftUI presentation. Screens read `AppState`, collect user input, and invoke state methods.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Domain/BodyTrendModels.swift`: InBody snapshot schema, avatar styles/parameters, mood values, and deterministic non-medical assessment rules.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Application/BodyTrendStore.swift`: validates, sorts, and persists InBody snapshots and avatar preferences independently from weight and habit state.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Infrastructure/InBodyOCRService.swift`: local Vision OCR adapter that extracts a reviewable draft from an uploaded report image.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/UI/BodyTrendView.swift`: body-trend workspace container, timeline slider, upload/manual entry flows, mood display, and assessment cards.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/UI/BodyAvatarSceneRenderer.swift`: SceneKit-only renderer/controller for the parameterized chibi human/animal/photo avatar, stage, materials, lighting, camera, interaction-friendly animation, and input-keyed scene caching; it has no persistence or domain mutations.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Health/Domain/HealthModels.swift`: body-measurement and habit value objects, including source metadata and presentation labels.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Health/Application/HealthStore.swift`: local persistence and use cases for body measurements and daily habit completion. This store is independent from weight state so HealthKit can be added behind a separate adapter later.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Infrastructure/HealthKitClient.swift`: the platform adapter for HealthKit authorization and read-only queries. The fallback implementation keeps macOS builds and previews independent from the iOS-only framework.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Infrastructure/HealthKitMapper.swift`: converts HealthKit quantities into app-level samples and keeps unit conversion out of stores and views.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Application/HealthSyncCoordinator.swift`: coordinates authorization, a bounded 90-day import, deduplication, and fan-out into the weight, body-measurement, and habit stores.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/App/ZheBuDeShouSi.entitlements`: enables the HealthKit capability for iPhone and iPad signing.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Resources/Assets.xcassets/`: icons and image assets.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi.xcodeproj/`: Xcode targets, platforms, signing, and build settings.

## Current iOS presentation

- `HomeView` in `Shared/UI/ContentView.swift`: a two-part weight workspace modeled on the supplied references. The upper plan card shows current/goal weight and a linear progress rail; the lower area separates a tappable weight trend preview from date-grouped journal cards with fixed time/weight/change columns. It intentionally does not duplicate habit summaries or activity logs.
- The shared presentation palette remains compatible with the existing weight tone rules; the body-trend workspace adds its own editorial paper palette (warm paper, ink blue, mist blue, sage, and muted blush) so the reference-inspired treatment stays local to that feature. `AppState.weightTone(_:)` remains the single source of truth for green/red weight-value tones.
- `BodyTrendView` in `Features/BodyTrend/UI/BodyTrendView.swift`: replaces the previous trend workspace with InBody photo/manual entry, a timeline-driven parameterized 3D chibi avatar, mood and metric rows, and offline stage assessment. Its visual language translates the supplied reference into paper-like spacing, hairline rules, restrained color accents, and asymmetric editorial layout without copying source imagery; the 3D character is intentionally a brighter kawaii focal point. The header keeps only the right-side scan/entry actions, while the empty state uses the available viewport height to center one visual composition rather than duplicating controls. Existing weight/body-measurement data remains owned by `AppState`/`HealthStore` and is not deleted.
- `HabitsView` in `Shared/UI/ContentView.swift`: renders all seven habits as two-column tiles with independent completion toggles and record actions. Meal, exercise, and water keep their existing detailed record flow; sleep, bowel movement, medication, and menstrual-cycle notes use `HabitRecordModal` and `HealthStore.recordHabit(_:,on:note:)`.
- `ProfileView` in `Shared/UI/ContentView.swift`: the main avatar opens `PhotosPicker` and persists selected image data through `AppState`; the header action opens the WeChat login surface. Real WeChat OAuth still requires an Open Platform AppID and callback configuration.
- `BottomNav` in `Shared/UI/ContentView.swift`: persistent four-item navigation for home, trend, habits, and profile with equal-width slots. Weight recording is opened from the home and trend surfaces.

## iOS state flow

`ZheBuDeShouSiApp` creates `AppState`, `HealthStore`, `HealthSyncCoordinator`, and `BodyTrendStore` -> injects them into `ContentView` -> weight screens call `AppState` actions, habits/body measurements call `HealthStore` actions, and the body-trend workspace calls `BodyTrendStore` -> uploaded reports go through local Vision OCR into an editable draft -> confirmed snapshots are validated and persisted -> the selected timeline snapshot drives the avatar, mood, metrics, and deterministic assessment independently.

## Goal weight feature

- Owner: `AppState` in `Models.swift`.
- Persisted property: `goalWeight` in the app snapshot.
- Mutation API: `updateGoalWeight(_:)`; this is the only UI-facing way to change the goal.
- Presentation: `WeightHero` displays a tappable goal control and presents `GoalWeightModal` from `ContentView.swift`.
- Consumers: home progress/tone calculations, trend displays, and profile statistics read the same `AppState.goalWeight` value.

## Editing guide

- Visual-only changes belong in SwiftUI views in `Shared/UI/ContentView.swift`.
- Rules, validation, derived values, shared palette, and persistence belong in `Shared/Models/Models.swift`.
- New persisted fields must remain compatible with snapshots created by previous app versions.
- Body measurements and habits use their own `HealthStore` snapshot key; HealthKit imports preserve the original source metadata and deduplicate by the external sample identifier.
- The first HealthKit slice imports body mass, waist circumference, dietary energy, dietary water, exercise time, sleep, and menstrual-flow samples. HealthKit does not provide standard values for every requested body circumference, nor a reliable general-purpose bowel-movement source; hips, arms, thighs, calves, bowel movement, and medication remain manual.
- BodyTrend OCR is local and review-first; a single report photo cannot reliably generate a medical-grade mesh. The 3D person/cat/dog/custom-photo views are parameterized visualizations driven by recorded values. Mood is explicitly user-entered and is never inferred from body composition. Assessments are offline summaries with a non-medical disclaimer.
- Cross-client changes must list iOS and mini-program verification separately.
