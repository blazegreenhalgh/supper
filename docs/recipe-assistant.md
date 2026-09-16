# Recipe AI and personal API keys

## Setup

Open Household settings → AI. Create a personal key at https://platform.openai.com/api-keys, enable API billing, then save the key in Supper. Never put it in source control or send it in chat. Test connection uses GET /v1/models/gpt-5.6-terra, not a paid generation. Restricted keys need model-read permission for this test; actual calls also need Responses and, for covers, Images permissions. The test does not verify credits or image access.

The key uses a nonsynchronizing Keychain generic-password item with WhenUnlockedThisDeviceOnly accessibility. It is never stored in preferences, recipes, CloudKit, logs, or build configuration. Add a key separately on each device; replace/remove it in the same screen. Simulator UI tests use an isolated Keychain service and never send their fixture key.

This is personal bring-your-own-key, not a shared app-owner credential. Before distributing an app-funded key to other users, build an authenticated backend instead of bundling that key.

## Feature routing

- Recipe discovery and editor chat: GPT-5.6 Terra, OpenAI Responses API.
- Text/photo extraction: Vision OCR stays on-device, then Terra structures the recognized or pasted text; every extracted ingredient and step must be a literal source substring.
- Full-screen step ingredient matching: Terra selects existing ingredient indexes only. Displayed quantities come from existing deterministic scaling. Explicit local matches remain available without a key.
- Covers: GPT Image 2.5 Flare, medium-quality square image in a top-down editorial cookbook style, generated only on request, with preview and explicit acceptance. No existing photo is overwritten before acceptance. Generated covers are labelled and recorded in Notes.
- Covers from your photo: GPT Image 2.5 Sunburst, Images edits endpoint with the JPEG attached as an `image[]` multipart file, matching the official Sunburst upload example. No optional `input_fidelity` override is sent. Generate cover → Create from my photo accepts a Photos upload or the current recipe image as the food reference. The prompt requests an entirely new editorial cookbook photograph from directly overhead, with professional re-plating, new tableware, setting, lighting and composition. It retains the dish's main visible ingredients, characteristic appearance and relative proportions, rather than preserving the original scene. Original/Generated comparison is available before explicit acceptance; generated results can alter food details and are labelled in Notes.
- Online covers: chat or Generate cover → Find online searches actual web-tool sources, or reads an explicit public HTTPS recipe/photo link. Photos come only from downloaded JSON-LD/Open Graph/Twitter metadata or a supplied image URL, never model-written image URLs. Downloads enforce public HTTPS on redirects, content/size limits and real image decoding; source and image links are retained in Notes. No generation fallback is used if search fails.
- Small ingredient formatting, tag suggestions and cookbook filter interpretation remain on-device. Manual editing, title-only saving, deterministic quantities and URL import do not require a key.

## Published discovery and grounded recipe edits

There is no Create with AI discovery mode. The API must run its web-search tool; URLs are accepted only from completed tool results, not fabricated prose or citations. A public HTTPS URL explicitly pasted in the current request can be read directly instead.

Supper downloads those recipe pages and requires complete structured ingredients/methods before accepting them. Search snippets are never used as recipe content. Selection is one bounded model request across downloaded candidates; the model returns indexes, not generated recipes. Hard requirements with missing evidence must be rejected. Missing/blocked sources produce an actionable error, never model-memory fallback.

For recipe edits, chat first checks whether essential facts are missing (for example the yield or amount of meat when reconstructing a home dish). It asks one question before searching when needed, and retains earlier user details for follow-up answers. It searches for a compatible published base recipe with the right core ingredients and technique; herbs and condiments do not need to match exactly.

Exact imports and unadapted rows retain source-evidence validation. Modest adaptations can use a named user ingredient at the source amount, or a clearly labelled conservative seasoning estimate. Each adapted ingredient identifies the source row (or an added seasoning); each changed method identifies its source steps and explains the departure. Core quantity/unit changes cannot pass as substitutions, and unannotated changes still require exact source or literal user evidence. No generated recipe fallback is used when a suitable base cannot be downloaded.

A separate model request checks adapted proposals against the downloaded base and complete resulting recipe: base suitability, core ratios, cooking technique, disclosed changes, ingredient/method consistency and yield. All checks must pass before a proposal is shown. A missing fact becomes a normal clarification; a rejected adaptation does not change the draft or replace an earlier pending proposal. This semantic check is model-based and does not establish that the adaptation works in a kitchen.

Chat and the native review sheet distinguish the published foundation from substitutions, estimated seasonings and method changes, with a clear statement that adaptations have not been kitchen-tested. Applying retains the source links, adaptation notes and assumptions in recipe Notes, including when the base source URL was already present. Apply/Save/Cancel, stale-draft protection and Undo continue to work as before. Photos, tags, collections, original source URLs and household metadata remain outside the recipe patch. Scaling continues to use the deterministic servings control.

One small structured request routes natural-language chat to recipe editing, collections, online photos, generation from the recipe or generation from a food reference. A request to generate a new image using the user's photo takes the food-reference route. Ambiguous photo requests show explicit choices. The photo menu bypasses routing when the user has already selected an action. Photo actions operate separately from recipe evidence validation and only change the image plus its credit after review.

Collection requests use the active household's actual collection IDs and names. Add preserves other memberships; move removes only the named source; remove affects only the named collections. A separate proposal lists additions and removals. Applying it updates `RecipeDraft.collectionIDs`, and the app generates the confirmation from that result. Save persists the selection; Cancel discards it. Changed selections, missing IDs, conflicting operations and household changes block application. Recipe content can continue to be edited while this request runs. Collection organisation does not need web research; recipe content edits still require a downloaded foundation and evidence or disclosed adaptations. Creating or deleting collections stays in Manage collections.

A citation does not certify a recipe's safety or suitability. Users must still review matches, exclusions and any requested adaptations.

## Draft behavior and performance

Chat starts as a compact Liquid Glass input at the editor's bottom safe area. Tapping opens a native SwiftUI sheet at the large detent. Its system grabber switches between medium and large heights or dismisses it; there are no custom offsets, drag recognizers, panel backgrounds or spring transitions. Focusing the composer selects the large detent. Conversation scrolling prioritises content and uses interactive keyboard dismissal; a keyboard toolbar also offers Hide keyboard. Sending keeps focus. The system Close control offers an alternative to dragging, without an Ask AI title bar.

The composer is inset above the keyboard, supports up to six visible lines, and derives its minimum height from the actual native Send/Stop control rather than an outer hit-area frame. Single-line input and button therefore share a visible height. Close chat before returning to the editor; reopen it from any ingredient, method or details screen. The editor owns the conversation, unsent input, pending changes and undo history. Closing the chat preserves these and lets ongoing requests continue. Stop or leaving the recipe editor cancels local work and ignores late results. The recipe form retains extra bottom scroll clearance for its compact launcher.

Discovery uses the existing Supper canvas, system typography, an inset grouped form, full-width suggestion rows and a native Find recipes button. Loading uses an animated system ProgressView with the actual search stage and a Cancel action that preserves the prompt. There is no custom illustration, colour palette or continuous Canvas rendering. Results retain source labels, counts and decisions, with source information in the options menu. Red/green swipe feedback belongs only to the translated top card; the stationary stack stays neutral.

Preview opens a read-only recipe page. Changes mode shows additions, the previous values of edits, and removed ingredients and steps with explicit labels and strikethrough. Recipe mode shows the proposed result, including source notes. Each preview targets a fixed suggestion; a newer response cannot silently replace the edit being approved.

Apply changes the unsaved draft, Save commits it; Cancel discards it. Suggestions remain previewable after manual changes, but Apply requires a matching draft and a new request starts from the latest manual edits. Apply and Undo are disabled while an individual ingredient or step form has unfinished input. Undo is also rejected after newer draft edits.

Photo proposals use photo-only conflict checks, preserving recipe edits made while a photo loads. A newer manual photo blocks replacement. Chat photo acceptance has the same exact-draft Undo protection. Each photo preview targets one fixed result; previews display original/current comparisons, source credit or AI provenance. Cover tools also stage results until Use photo.

Research reads up to eight pages, three at a time, and batches relevance checks instead of running a model session per candidate. An in-memory cache retains up to 16 public recipe pages for ten minutes to speed follow-ups. It stores no keys or private drafts. Context/output sizes are bounded, with no silent truncation of accepted source recipes. Failed/partial/refused responses never apply. Automatic paid retries are intentionally avoided.

Method groups retain the existing readable Markdown representation in the CloudKit step text field. No production schema migration is required.

## Privacy and billing

Settings explains data transfer before saving a key. User-triggered AI sends relevant recipe content to OpenAI; online search also queries the web and Supper reads public publisher pages. Covers generated from a recipe send title and ingredients. Create from my photo sends an orientation-corrected, downsampled JPEG of the supplied food photo, without camera metadata; uploaded bytes provide the food reference for a newly generated cookbook photograph. Requests use store:false on Responses, ephemeral URL sessions, and no API redirects. Provider error text is never displayed or logged, preventing echoed keys/private content from leaking. OpenAI's API retention policies still apply; store:false is not a zero-retention guarantee.

Implementation references: [image generation and editing guide, including the Sunburst multipart upload example](https://developers.openai.com/api/docs/guides/image-generation), [Images edits reference](https://developers.openai.com/api/reference/resources/images/methods/edit).

API billing is separate from ChatGPT. Show clear errors for invalid/restricted keys, model access, exhausted credits, rate limits, timeouts, and provider failures. Stopping a request does not necessarily prevent provider charges for work already processed.

Rejected requests include the HTTP status, allowlisted API error code/type and parameter, and a validated OpenAI request ID when available. The photo alert offers Copy details. Provider prose, unrecognized diagnostic field contents, prompts, image data and keys are never copied into diagnostics. A generic HTTP 400 does not establish a billing or model-access failure; the server's safe diagnostic fields are needed to distinguish causes. Known moderation and organization-verification failures get specific explanations.

## Verification

Mocked transport tests cover model IDs, structured output, required search, source provenance, malformed/refused/incomplete responses, sanitized billing errors, key input validation, connection testing and image responses. Evidence tests reject invented core amounts and undisclosed method changes. Grounded-edit tests cover the cream/stock sauce case, missing and fabricated sources, invalid adaptation references, follow-up ingredient facts, clarification without mutation, review rejection and persisted adaptation notes with Undo. Mocked transport tests exercise planning, normal clarification and the separate adaptation reviewer without paid requests. Existing draft/undo, quantity, formatting and discovery regressions remain.

UI coverage includes opening AI settings, saving/replacing/removing a fixture key, persistence across app relaunch, chat dismissal/reopening across ingredient/step navigation, native detent resizing, composer sizing and keyboard clearance, preview removals, stale and unfinished-edit protection, apply/undo, and existing discovery flows. A deterministic proposal is available only in DEBUG builds with both `--ui-testing` and `--recipe-chat-ui-testing`. No real key or live generation is needed for CI.

Photo tests cover metadata provenance, unsafe URLs, preservation of newer recipe edits, stale photo rejection, photo undo, multipart image-edit fields and unmodified JPEG bytes, Unicode prompts, safe error diagnostics, no automatic retries, deadlines/cancellation and action routing schema. DEBUG `--ui-testing --recipe-photo-ui-testing` stages a portrait original and a distinct square result for repeated Original/Generated switching, source-preview, apply/undo and upload-option UI coverage; it performs no paid requests. The display-only preview ignores hit testing so scaled-to-fill image content cannot intercept the comparison control.

CI ad-hoc-signs simulator builds with `Tests/UI/Simulator.entitlements` so real Keychain operations have an app identity. This simulator-only identity is passed by the workflow, never used by device or distribution builds. Editor interactions run separately from library checks; the library job runs the focused Keychain test first. Shipping signing and Keychain protection are unchanged.

Live acceptance after entering a funded key:
1. Test connection; find published recipes with exclusions and duration constraints. Verify each source.
2. Start a home recipe and ask for ingredients/method using cream, beef stock, soy sauce, flour, pepper and rosemary. Answer any yield question. Verify the published foundation, preserved core amounts, labelled seasoning estimates and explanation of method changes. Review, Apply, Save and reopen to check source/adaptation Notes. Request a structural substitution or incompatible yield and verify it asks for clarification or declines.
3. Create “Naan bread pizza” with only its title. Ask for just naan ingredients and method, inspect the source/yield and unchanged pizza content, then Apply, Undo and Save.
4. Paste a recipe URL; try a blocked/non-recipe page and verify no recipe is invented.
5. Import recipe text/photo and check it against the original.
6. Generate a cover, dismiss without applying, generate again and explicitly accept.
   Ask chat to find an online photo, verify the source, preview and use it. Also try a direct photo URL and a blocked page. Upload a portrait food photo via Generate cover → Create from my photo; verify the result is a new top-down cookbook scene depicting the reference food, switch repeatedly between Original and Generated, apply, save and reopen.
7. Check step ingredient references and exact recipe amounts.
8. Remove the key, test offline/manual entry and on-device formatting.

Live model quality/latency, account availability, credits and image verification cannot be established by mocked tests.
