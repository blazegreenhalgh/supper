# Cookbook and household update

Supper remains an image-and-title cookbook. Optional recipe details do not introduce meal tracking or ratings. The existing palette and system typography are retained.

## Editing and navigation

Search lives in a dedicated native search-role tab, attached to a persistent navigation stack. Homepage filters and search-tab filters keep independent state, so a hidden query cannot unexpectedly filter the homepage. Both use the same matching logic and picker. Active chips use native prominent blue buttons, with Clear outside the horizontal scroll area. Homepage Edit opens Collections; the options menu contains Pick something and Household.

The recipe editor keeps a single draft with focused ingredient, method, tag, collection and note screens. Individual ingredient/step sheets edit copies and only apply on Add/Done; Cancel Recipe still discards the entire draft. Reordering retains IDs. Source-group recovery remains reviewable inside Ingredients. Ingredient names wrap beside trailing amount capsules. Method offers a full-screen reader sharing its current step with the detail screen.

## Data and migration

The shipped programmatic model is preserved verbatim in `LegacyModel.swift`. `NSStagedMigrationManager` receives explicit v1 and current model references; all schema changes are additive and optional. Core Data performs an inferred migration in place, keeping its CloudKit mirroring metadata. There is no database reset, destructive recovery, or automatic replacement of an existing library. Regression tests create a real v1 SQLite store and reopen it through the current stack, checking recipe/ingredient IDs, image bytes and legacy reactions.

Ingredients store source recipe groups separately from shopping-category overrides. Recipe membership is a set of collection IDs; one collection row also stores its shared homepage visibility/order. Removing a collection tombstones it and hides memberships without deleting recipes. Recipe editing reconciles child rows by ID and never writes reactions.

## Quantities and grocery retries

Scaling always starts from saved base quantities. Numeric fractions, decimals, mixed fractions and simple ranges scale; unknown quantities remain text. Missing base servings stay unset until the user edits them.

Grocery rows are individual recipe contributions, projected into conservative totals for display. A selection sheet retains its operation UUID throughout save retries; each ingredient combines that UUID with its ingredient ID. Removed contributions remain tombstoned, so retries cannot re-add them. Each explicit new Add action creates a new batch. Checking, category corrections and deletion apply to every contributing row, including duplicate operation records. Weight and volume convert only within g/kg and ml/l. Cups, spoons, package sizes and unknown units are not combined across contributions because their standards may differ. The matcher uses a narrow plural/spelling allowlist and keeps preparation/form words.

## Identity and invitations

An installation has a stable Keychain identity, with an offline fallback. Successful CloudKit user-record resolution attaches an account identifier only to that installation's member row. Account aliases deduplicate reactions across devices without changing another person's reactions. A detected account switch gets a separate identity. Legacy `me` reactions have unknown authors and are never automatically claimed.

Private and shared stores are scoped by the selected root. New managed objects explicitly use the root's persistent store and relationship graph. Sharing reopens cached invitations using the server version, creates a share when needed, saves it on CloudKit, validates its HTTPS share URL, and persists the returned share before presenting `UICloudSharingController`. Callback operations have cancellation and timeout handling. App and scene delegates receive invitations at launch and while running. Acceptance records the exact share record and zone before activating the matching downloaded root. Other private libraries stay available in Household settings. Errors are surfaced for account, permission, revoked-access, loading and sharing failures.

## Import and local assistance

Structured URL recipe metadata is deterministic and preferred. Explicit ingredient headings in metadata or source HTML are mapped conservatively; recovering headings on an existing recipe requires review and never changes quantities or names. Generic HTML and WPRM recipe headings are supported; unsupported/ambiguous markup falls back to manual grouping.

Vision performs local text recognition for screenshots and cookbook photos. The Foundation Models implementation explicitly checks the on-device system model's availability. It supplies no tools or remote model/API, treats source content as untrusted, and accepts extracted ingredient lines and steps only when present verbatim in the source. Original text remains available in the draft. All generated output is reviewed before saving. Quantity calculation never uses AI. A food photograph without recipe text uses ordinary photo-and-title capture.

## Validation and release

`swift test` runs domain tests plus macOS Core Data integration and migration tests. The Xcode `Supper` scheme includes `SupperUITests` for native search-tab navigation (normal, interactive and cancelled back with an active filter), editor cancellation, ingredient editing/save, collection creation, active filter clearing and full-screen step navigation. GitHub Actions builds the iOS simulator app and runs these checks before delivery; Xcode Cloud retains the main-to-TestFlight pipeline.

Signed-device checks that require Apple accounts remain separate from simulator coverage:

1. Use an iCloud-enabled development build to populate the additive schema and create a development invitation, including `cloudkit.share`.
2. Deploy the development schema to Production in CloudKit Console. This adds schema; do not reset production data. The app cannot deploy a production schema using its client entitlement.
3. On two signed-in devices, verify owner invitation creation/reopening, recipient launch/running acceptance, both-way updates and offline edits. Check revocation and account switching. Verify recipes, images, ingredients, steps, reactions, collections and groceries in the selected household.
4. Confirm Xcode Cloud archive, TestFlight processing and group availability independently before reporting a build as installable.

Apple references: [Core Data sharing](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users), [staged migration](https://developer.apple.com/documentation/coredata/nsstagedmigrationmanager), and [Foundation Models](https://developer.apple.com/documentation/foundationmodels).
