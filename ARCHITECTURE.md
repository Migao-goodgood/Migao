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
│   └── WeightViews       # weight cards, ruler/date picker, trend chart
├── BodyMeasurements
│   ├── BodyMeasurementModels
│   ├── BodyMeasurementStore
│   └── BodyMeasurementViews
├── Diet
│   ├── Domain             # meal records, photos, recognition and day summaries
│   ├── Application        # CRUD, local-day queries, kcal aggregation and migration
│   ├── Infrastructure     # replaceable on-device/photo analysis adapter
│   └── UI                 # calendar, mosaic, collage and centered review flows
├── Habits                 # legacy daily completion records kept for compatibility
│   ├── HabitModels
│   ├── HabitStore
│   └── HabitViews
├── BodyTrend
│   ├── Domain             # InBody snapshots, comparable metrics and report-analysis contract
│   ├── Application        # snapshot store, comparison use case, measurement cadence and reminder boundary
│   ├── Infrastructure     # Vision OCR, optional AI backend and local-notification adapters
│   └── UI                 # upload/review, comparisons, metric trends and history
├── HealthKit
│   ├── HealthKitClient   # platform API adapter
│   ├── HealthKitMapper   # sample -> domain conversion
│   └── HealthSyncCoordinator
└── WeChatAuth
    └── WeChatAuthCoordinator # OAuth hand-off and callback state

Core
├── Persistence           # UserDefaults snapshots
├── DesignSystem          # shared jelly colors and view modifiers
├── DateFormatting
└── Permissions           # HealthKit authorization boundary
```

The repository keeps the collaborator-facing SwiftUI presentation in `Shared/UI/ContentView.swift` and the weight store in `Shared/Models/Models.swift`; the logical ownership above is the boundary to preserve while these files are split incrementally. New HealthKit code follows the adapter/coordinator boundary.

## iOS files

- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/App/ZheBuDeShouSiApp.swift`: application entry point; creates and injects `AppState`, `HealthStore`, `HealthSyncCoordinator`, `BodyTrendStore`, `DietStore`, and `WeChatAuthCoordinator`.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/Models/Models.swift`: domain enums/models, `AppState`, canonical-kilogram storage, `WeightUnit` conversion/formatting, derived progress and color rules, shared jelly palette, avatar snapshot persistence, user actions, and `UserDefaults` snapshot persistence.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/Models/SolarTerm.swift`: day-level twenty-four-solar-term lookup and the curated classical greeting text used by the home header; it has no persistence or UI state.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/UI/ContentView.swift`: app navigation and SwiftUI presentation. Screens read `AppState`, collect user input, and invoke state methods.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/UI/NumericInputComponents.swift`: shared centered modal overlay, modal surface/header, ruler-style weight selector with `kg/g` switching, sliding date wheel, and one-decimal wheel selector used by body-circumference records.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/UI/WeightTrendModal.swift`: centered home trend detail, period selection, horizontally scrollable weight plot, and the shared plot renderer.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Shared/UI/WeightCalendarView.swift`: shared `WeightModuleTitle` (horizontal 28-point ink heading matching the trend page's `身体趋势`), local-date grouping, one representative weight per day, month grid presentation, and transient rise/fall color intensity for the weight calendar; the calendar module has no vertical divider.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Domain/BodyTrendModels.swift`: version-compatible InBody snapshot schema, measured values, report metadata, optional legacy mood, and normalization rules.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Domain/InBodyComparisonModels.swift`: stable metric identifiers, value deltas, previous/first comparison results, and non-medical stage-analysis values.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Domain/InBodyReportAnalysis.swift`: provider-neutral report-analysis result and replaceable `InBodyReportAnalyzing` application contract.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Application/BodyTrendStore.swift`: validates, sorts, and persists user-confirmed InBody snapshots and measurement cadence independently from weight and habit state.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Application/InBodyComparisonService.swift`: performs all previous/first baseline arithmetic and generates deterministic stage summaries outside SwiftUI.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Application/InBodyMeasurementReminder.swift`: defines supported measurement intervals, due-date planning, persisted schedule values, and the platform-neutral notification scheduler contract.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Infrastructure/InBodyOCRService.swift`: on-device Vision OCR adapter that extracts a reviewable draft from an uploaded report image without network access.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Infrastructure/InBodyAIAnalysisService.swift`: optional HTTPS product-owned backend adapter and default local fallback. It sends no provider API key from the app; `INBODY_AI_ENDPOINT` is the only client configuration.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/Infrastructure/InBodyMeasurementNotificationScheduler.swift`: UserNotifications adapter behind the application reminder protocol; it requests permission only after the user enables reminders and replaces/cancels the single pending measurement notification.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/UI/BodyTrendView.swift`: coordinates the InBody data dashboard, single photo upload, explicit remote-analysis consent, report-analysis state, cadence state, and modal presentation. Original report bytes are not persisted.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/UI/InBodyDesign.swift`: feature-local paper, ink, blue, sage, blush, gold, and divider tokens.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/UI/InBodyTrendComponents.swift`: latest previous/first comparison, four switchable core metric trends, deterministic stage analysis, and empty state.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/UI/InBodyHistoryViews.swift`: measurement history rows and full detail sheet with confirmed deletion.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/BodyTrend/UI/InBodyEntrySheet.swift`: parsed report draft, editable core/extended fields, field validation, duplicate detection, and confirmed snapshot creation.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Diet/Domain/DietModels.swift`: meal slots, record sources, recognition status, recognized food values, provider-neutral photo-analysis and energy-sample contracts, image metadata, `MealRecord`, and the derived `DietDaySummary` contract. HealthKit sample IDs remain optional and backward-compatible.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Diet/Application/DietStore.swift`: owns meal CRUD, local-day/month projections, kcal aggregation, image/payload limits, legacy meal-log migration, and HealthKit energy import with external-ID deduplication. Views do not write `UserDefaults` directly.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Diet/Infrastructure/DietPhotoAnalysisService.swift`: conservative device-side Vision text pass for meal photos; it extracts visible labels/kcal only and leaves uncertain values empty. A future GPT/backend adapter can replace the same handler contract.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Diet/UI/DietUIModels.swift`: diet display mode, upload-state presentation, feature palette, and surface styling.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Diet/UI/DietComponents.swift`: month calendar, photo mosaic, calorie overlays, day detail modal, and review card.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Diet/UI/DietView.swift`: coordinates month/mode/date selection, PhotosPicker loading, review-first analysis, and confirmed writes to `DietStore`.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Health/Domain/HealthModels.swift`: body-measurement and habit value objects, including source metadata and presentation labels.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/Health/Application/HealthStore.swift`: local persistence and use cases for body measurements and legacy daily habit completion. The new meal journal is owned by `DietStore`; the legacy habit records remain for migration/backward compatibility.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Infrastructure/HealthKitClient.swift`: the platform adapter for HealthKit authorization and read-only queries. The fallback implementation keeps macOS builds and previews independent from the iOS-only framework.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Infrastructure/HealthKitMapper.swift`: converts HealthKit quantities into app-level samples and keeps unit conversion out of stores and views.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/HealthKit/Application/HealthSyncCoordinator.swift`: coordinates authorization, a bounded 90-day import, deduplication, and fan-out into the weight, body-measurement, legacy habit, and diet stores.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Features/WeChatAuth/WeChatAuthCoordinator.swift`: owns WeChat authorization configuration, a short-lived per-request state, backend hand-off, callback validation, and user-visible login state. The backend must return a one-time ticket/session after code exchange; App secrets and access tokens stay outside the client.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/App/ZheBuDeShouSi.entitlements`: enables the HealthKit capability for iPhone and iPad signing.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi/Resources/Assets.xcassets/`: icons and image assets.
- `ZheBuDeShouSi-iOS/ZheBuDeShouSi.xcodeproj/`: Xcode targets, platforms, signing, and build settings.

## Current iOS presentation

- `HomeView` in `Shared/UI/ContentView.swift`: a two-part weight workspace modeled on the supplied references. The upper plan card shows current/goal weight and a linear progress rail with fixed start/current/end weight labels plus two proportional under-brace annotations; its former explanatory subtitle is removed, and a solar-term name plus classical greeting appears only when the current local day matches one of the 24 terms. A compact `今日饮食` entry shows only today's kcal/meal count and opens the dedicated diet tab; the full month calendar and photo mosaic stay on that tab. The lower area contains a compact trend preview and the `体重日历` month grid. The two home module headings now use a horizontal four-character layout (`体重趋势` / `体重日历`) matching the trend page's `身体趋势` typography; the old vertical rail and divider line are removed. Tapping the preview opens a centered detail modal without changing the bottom tab; only the plot inside that modal scrolls horizontally.
- The shared presentation palette remains compatible with the existing weight tone rules; the body-data workspace adds its own clean pink-white paper palette with mist blue, sage, blush, and champagne accents so the reference-inspired treatment stays local to that feature. `AppState.weightTone(_:)` remains the single source of truth for green/red weight-value tones.
- `BodyTrendView` in `Features/BodyTrend/UI/BodyTrendView.swift`: replaces the former 3D presentation with a data-first InBody journal. The latest verified report can be compared with the previous or first report; weight, body-fat percentage, body-fat mass, and skeletal muscle share a switchable chart; extended report values stay in the verification and history details. The header keeps one photo-upload action and no duplicate scan/manual-entry controls.
- `DietView` in `Features/Diet/UI/DietView.swift`: the second tab is now a dedicated food journal. It offers a month calendar and image mosaic, displays kcal per recorded day, opens a centered day detail modal, accepts up to six photos per upload, and requires review before a meal enters the total.
- The previous `HabitsView` and `HabitRecord` types remain in `Shared/UI/ContentView.swift`/`Features/Health` as compatibility code for existing snapshots and HealthKit imports; they are no longer a bottom-navigation destination.
- `ProfileView` in `Shared/UI/ContentView.swift`: the personal page opens directly with the avatar card; the former `MY KAWAII PLAN`/`我的可爱变轻计划` header is intentionally omitted. The main avatar opens `PhotosPicker` and persists selected image data through `AppState`; the settings surface exposes the app-wide `kg/g` display preference, Apple 健康, and app information. Tapping the about row invokes the root presentation boundary and shows the static Japanese quote in a centered `AboutQuoteModal`; the quote is presentation-only and is not persisted. The `WeChatAuthCoordinator` remains isolated as callback infrastructure for a future explicit re-entry, with its five-minute request state and one-time ticket validation unchanged.
- `BottomNav` in `Shared/UI/ContentView.swift`: persistent four-item navigation for home, diet, trend, and profile with equal-width slots. Weight recording is opened from the home and trend surfaces.
- Weight records and goals use `CenteredModalOverlay` and `WeightRulerPicker`: the ruler supports theme-colored `kg/g` display switching while retaining canonical kilogram values; daily records also use a sliding date wheel constrained to today and the previous two years. Body-circumference entry continues to use `DecimalWeightPicker` with `0.1 cm` precision. The home trend detail uses the same centered presentation boundary; its calendar projection never mutates persisted records.

## iOS state flow

`ZheBuDeShouSiApp` creates `AppState`, `HealthStore`, `HealthSyncCoordinator`, `BodyTrendStore`, and `DietStore` -> injects them into `ContentView` -> weight screens call `AppState` actions (canonical kilograms, persisted `WeightUnit`, and selected record date), the home preview raises an `onShowTrend` callback to the root for a centered `WeightTrendModal`, and `WeightCalendarView` derives a read-only local-date projection -> the diet tab calls `DietStore` for local-day/month projections and confirmed meal mutations -> selected PhotosPicker bytes pass through `DietPhotoAnalysisHandler` (default conservative on-device Vision text pass) -> an editable review card requires explicit confirmation -> `DietStore` persists the meal and derives kcal/calendar/mosaic projections. Apple Health dietary-energy samples fan out to `DietStore` with external-ID deduplication while legacy habit imports remain available. The body-data workspace continues to call `BodyTrendStore` through its review-first InBody pipeline. Enabling a cadence requests notification permission through `InBodyMeasurementReminderScheduling`; saving a new report reschedules the next reminder from that measurement date.

## Goal weight feature

- Owner: `AppState` in `Models.swift`.
- Persisted property: `goalWeight` in the app snapshot.
- Mutation API: `updateGoalWeight(_:)`; this is the only UI-facing way to change the goal.
- Presentation: `WeightHero` displays a tappable goal control and presents `GoalWeightModal` from `ContentView.swift`.
- Unit preference: `WeightUnit` is persisted by `AppState`; goal and daily weight selectors can switch the display between `kg` and `g` while all calculations remain in kilograms.
- Consumers: home progress/tone calculations, trend displays, and profile statistics read the same `AppState.goalWeight` value.

## Editing guide

- Visual-only changes belong in SwiftUI views in `Shared/UI/ContentView.swift` or the reusable components in `Shared/UI/NumericInputComponents.swift`, `Shared/UI/WeightTrendModal.swift`, and `Shared/UI/WeightCalendarView.swift`.
- Rules, validation, derived values, shared palette, and persistence belong in `Shared/Models/Models.swift`.
- New persisted fields must remain compatible with snapshots created by previous app versions.
- Weight records persist canonical kilograms plus a selected local calendar date; `WeightUnit` only changes presentation and ruler increments.
- Body measurements and habits use their own `HealthStore` snapshot key; HealthKit imports preserve the original source metadata and deduplicate by the external sample identifier.
- `DietStore` uses its own `zhebudeshousi.dietStore.v1` snapshot key. Meal photos are bounded (5 MB per image, six per meal, 16 MB total) and totals are derived from confirmed meal records. Legacy `ActivityLog` meal rows migrate once; HealthKit dietary-energy samples keep their sample IDs for idempotent re-sync.
- The diet page is review-first: device OCR may suggest visible text or kcal labels, but missing/uncertain values remain empty and never become an automatic calorie estimate. A future remote analyzer must be injected through `DietPhotoAnalysisHandler` and obtain its own privacy consent before upload.
- The first HealthKit slice imports body mass, waist circumference, dietary energy, dietary water, exercise time, sleep, and menstrual-flow samples. HealthKit does not provide standard values for every requested body circumference, nor a reliable general-purpose bowel-movement source; hips, arms, thighs, calves, bowel movement, and medication remain manual.
- BodyTrend report analysis is review-first. By default OCR is local and private; an optional backend can call GPT or another vision model without exposing its API key to the app. Missing or unreadable fields remain empty and must never be invented. Assessments are deterministic summaries of confirmed measurements with a non-medical disclaimer.
- InBody comparisons use only user-confirmed snapshots. `InBodyComparisonService` compares the current record with both the immediately preceding and first record; report recommendations such as target weight remain separate from measured metrics. The persisted cadence computes a due date, while any system notification implementation must stay behind `InBodyMeasurementReminderScheduling`.
- Weight calendar summaries are derived from local `Calendar.startOfDay` groups. Each day displays its latest record; changes compare with the previous day that has a record, not with the persisted `WeightRecord.change` field. Number hue continues to come from `AppState.weightTone(_:)`; calendar cell opacity communicates rise/decrease so the two meanings stay separate.
- The progress rail annotations use the actual clamped marker split for their brace widths, while their text stays in independent segment containers with a narrow-segment fallback. The left solid underbrace is `已减` with magnitude `current - start`; the right dashed mathematical-style underbrace is `距离目标体重还差` with magnitude `end - current`. Both use the selected `WeightUnit` (0.1 kg or 100 g), so normal weight loss never renders a confusing negative label.
- Cross-client changes must list iOS and mini-program verification separately.
