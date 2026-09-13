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

After opening the project in Xcode, enable the iCloud / CloudKit capability for the Supper target and ensure the container exists in the Apple Developer account.

## AI import direction

URL import first uses structured `Recipe` JSON-LD because it is deterministic and cheap. Apple Foundation Models can then be used as a cleanup/fallback layer for messy pages, screenshots and cookbook photos. The service boundary is already separated so that can be added without changing the UI.
