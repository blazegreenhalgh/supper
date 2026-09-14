# Recipe discovery

Tap **What are you craving?** on the library screen, or **Find new recipes** in the library/search menu.

- **Find online** searches RecipeTin Eats, Budget Bytes and Skinnytaste, using Apple Intelligence to form searches and check imported recipes against the request. Recipe pages provide the title, image, ingredients, quantities, method, duration and servings when present. A source link remains attached. Unsupported pages are skipped instead of producing incomplete cards.
- **Create with AI** writes three original recipe drafts on device, with metric quantities and cooking instructions. These are labelled as AI-created and have no invented photo or source link. Requires Apple Intelligence enabled on a supported device; creation also works offline.
- Tap a card to open the normal recipe detail screen. **Edit → Done** changes only the suggestion. Keep/discard decisions remain on the results screen.
- Swipe right to keep or left to discard. The labelled buttons and VoiceOver actions provide the same controls. Undo restores the last discarded recipe, including edits.
- The toolbar switches between the stack and a normal grid. Both use the same drafts and decisions; the view preference is remembered.
- **Keep** saves to the active shared household using the existing Core Data/CloudKit store. A failed save leaves the card available to retry. Repeated decisions cannot create duplicate recipe IDs. A household switch blocks saving into a different household.
- Closing the sheet retains the current session while the library view remains alive. Starting a new request asks before clearing unreviewed drafts. Unkept suggestions are transient and are not restored after terminating the app.

## Service and privacy

The online path sends food search queries to the public recipe search indexes of RecipeTin Eats, Budget Bytes and Skinnytaste and downloads recipe pages/images from publishers. It does not send household recipes or member information. AI generation and matching use Apple's on-device Foundation Models. Without Apple Intelligence, online keyword matches are explicitly labelled and creation is unavailable.

The publishers’ public WordPress search endpoints are key-free and have no availability guarantee. This searches these three publishers, not the entire web. Search failures, offline access and pages without usable recipe metadata produce retryable messages; the app never presents generated content as an online result. The online search adapter is isolated in `RecipeDiscoveryService` so a production search API can replace it without changing the review UI. Publisher-specific extraction still uses the existing structured-data importer.

A fresh model session is used for each recipe to fit [Apple's on-device context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window).

## Verification

Domain tests cover source parsing, unsafe/duplicate links, malformed responses, draft edits, stable identities, keep idempotency and undo. UI tests use explicit debug-only fixtures to cover preview/edit without saving, keep/discard from both layouts, session reopening and horizontal swipes. Live AI output requires a supported physical device; simulator fixtures do not validate model output quality.
