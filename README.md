# Supper

Supper is a shared, visual cookbook for the meals you actually want to make again.

## Product direction

- Beautiful image-first recipe library
- Quick add: an image and title are enough
- Add from recipe URL
- Duration and tags
- Individual household reactions
- Shared grocery list generated from recipe ingredients
- CloudKit sharing, following the same private/shared-store approach used in Envelope
- Native SwiftUI UI with Apple-style materials, image bleed and minimal chrome

Explicitly out of scope: meal history, “cooked it” tracking, last-cooked dates and star ratings.

## Current starter build

The first pass includes:

- Recipes + Grocery tab structure
- Image-led recipe grid
- Recipe detail view
- Quick Add flow with PhotosPicker
- URL import using common Schema.org Recipe JSON-LD
- Core Data persistence configured for private + shared CloudKit stores
- Shared-library-ready data model for recipes, ingredients, steps, reactions and groceries

## CloudKit setup

Bundle identifier: `com.blazegreenhalgh.Supper`  
CloudKit container: `iCloud.com.blazegreenhalgh.Supper`

The app's signing profile includes this container. Production schema deployment
and multi-account sync still need verification.

## TestFlight

Pushes to `main` trigger Xcode Cloud builds and deliver successful archives to the
internal TestFlight **Testing** group. See [TestFlight and Xcode Cloud](docs/testflight.md)
for the workflow, tester instructions, and verification details.

## Recipe assistance

Add your personal OpenAI API key in Household settings → AI. GPT-5.6 Terra handles published recipe discovery, editor chat, text extraction and step ingredient matching; GPT Image 2.5 Flare creates optional covers. Keys stay in this device’s Keychain, not CloudKit. API billing is separate from ChatGPT. See [AI setup and sourcing guarantees](docs/recipe-assistant.md).

Discovery imports only published recipes, never generated ones. URL import prefers structured `Recipe` metadata and explicit ingredient headings. Vision recognizes recipe text in photos. Small formatting, tags and cookbook filter interpretation remain on-device. Manual capture and deterministic quantities remain available offline without a key; URL import needs internet but no key.

In the recipe editor, open Ingredients → Auto format to review sentence case, repaired brackets and recovered quantity/unit fields. Weight extraction uses source values, never model arithmetic. Existing amounts win; package sizes and conflicts remain readable. Model output cannot add or drop ingredient words, change quantities or replace IDs, groups or categories. Apply changes only the editor draft; Save commits the recipe.

`swift test` covers formatting, quantities, merging, groups, editing, filtering, identity and persistence migration. The iOS UI suite covers native navigation/search, formatting review/cancel, tags, grocery selection and full-screen method. Foundation Models generation itself also needs a supported physical device with Apple Intelligence enabled; simulator tests exercise the deterministic fallback.

Full-screen method steps use OpenAI to match references to earlier steps and ingredient groups. Only existing ingredient IDs are accepted; displayed names and scaled amounts come from saved ingredients. Amounts are recipe totals, not invented allocations for “half” or “remaining” instructions. Matching is cached while the method view remains open, cancels on dismissal, and falls back to explicit local mentions when unavailable. All ingredients remains accessible in a disclosure.
