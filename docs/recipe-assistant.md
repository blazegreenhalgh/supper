# Recipe AI and personal API keys

## Setup

Open Household settings → AI. Create a personal key at https://platform.openai.com/api-keys, enable API billing, then save the key in Supper. Never put it in source control or send it in chat. Test connection uses GET /v1/models/gpt-5.6-terra, not a paid generation. Restricted keys need model-read permission for this test; actual calls also need Responses and, for covers, Images permissions. The test does not verify credits or image access.

The key uses a nonsynchronizing Keychain generic-password item with WhenUnlockedThisDeviceOnly accessibility. It is never stored in preferences, recipes, CloudKit, logs, or build configuration. Add a key separately on each device; replace/remove it in the same screen. Simulator UI tests use an isolated Keychain service and never send their fixture key.

This is personal bring-your-own-key, not a shared app-owner credential. Before distributing an app-funded key to other users, build an authenticated backend instead of bundling that key.

## Feature routing

- Recipe discovery and editor chat: GPT-5.6 Terra, OpenAI Responses API.
- Text/photo extraction: Vision OCR stays on-device, then Terra structures the recognized or pasted text; every extracted ingredient and step must be a literal source substring.
- Full-screen step ingredient matching: Terra selects existing ingredient indexes only. Displayed quantities come from existing deterministic scaling. Explicit local matches remain available without a key.
- Covers: GPT Image 2.5 Flare, medium-quality square image, generated only on request, with preview and explicit acceptance. No existing photo is overwritten before acceptance. Generated covers are labelled and recorded in Notes.
- Small ingredient formatting, tag suggestions and cookbook filter interpretation remain on-device. Manual editing, title-only saving, deterministic quantities and URL import do not require a key.

## Published recipes only

There is no Create with AI discovery mode. The API must run its web-search tool; URLs are accepted only from completed tool results, not fabricated prose or citations. A public HTTPS URL explicitly pasted in the current request can be read directly instead.

Supper downloads those recipe pages and requires complete structured ingredients/methods before accepting them. Search snippets are never used as recipe content. Selection is one bounded model request across downloaded candidates; the model returns indexes, not generated recipes. Hard requirements with missing evidence must be rejected. Missing/blocked sources produce an actionable error, never model-memory fallback.

Editor chat selects one supporting downloaded recipe, returns a bounded patch and passes source-evidence validation. New ingredient amounts must match complete source rows or literal user input. New method steps must match complete source steps or literal user input. The assistant cannot invent cooking times, omit parts of source steps, or overwrite photos, tags, collections, notes, original source URLs or reactions. Group labels and explicit user edits are permitted; departures from the source must be explained for review. Scaling in chat directs the user to the existing servings control rather than generating quantities.

A citation does not certify a recipe's safety or suitability. Users must still review matches, exclusions and any requested adaptations.

## Draft behavior and performance

Ask AI belongs to the editor session. Closing/reopening retains conversation, input, pending changes and undo history. Apply changes the unsaved draft, Save commits it; Cancel discards it. Stale proposals and undo are rejected if the draft has changed. Closing/stopping requests cancels local work and ignores late results.

Research reads up to eight pages, three at a time, and batches relevance checks instead of running a model session per candidate. An in-memory cache retains up to 16 public recipe pages for ten minutes to speed follow-ups. It stores no keys or private drafts. Context/output sizes are bounded, with no silent truncation of accepted source recipes. Failed/partial/refused responses never apply. Automatic paid retries are intentionally avoided.

Method groups retain the existing readable Markdown representation in the CloudKit step text field. No production schema migration is required.

## Privacy and billing

Settings explains data transfer before saving a key. User-triggered AI sends relevant recipe content to OpenAI; online search also queries the web and Supper reads public publisher pages. Covers send title and ingredients, not the existing photo. Requests use store:false on Responses, ephemeral URL sessions, and no API redirects. Provider error text is never displayed or logged, preventing echoed keys/private content from leaking. OpenAI's API retention policies still apply; store:false is not a zero-retention guarantee.

API billing is separate from ChatGPT. Show clear errors for invalid/restricted keys, model access, exhausted credits, rate limits, timeouts, and provider failures. Stopping a request does not necessarily prevent provider charges for work already processed.

## Verification

Mocked transport tests cover model IDs, structured output, required search, source provenance, malformed/refused/incomplete responses, sanitized billing errors, key input validation, connection testing and image responses. Evidence tests reject invented ingredient amounts and altered/incomplete method steps. Existing draft/undo, quantity, formatting and discovery regressions remain.

UI coverage includes opening AI settings, saving/replacing/removing a fixture key, persistence across app relaunch, and existing chat/discovery flows. No real key or live generation is needed for CI.

CI ad-hoc-signs simulator builds with `Tests/UI/Simulator.entitlements` so real Keychain operations have an app identity. This simulator-only identity is passed by the workflow, never used by device or distribution builds. The focused Keychain test runs before the remaining UI suite for faster diagnostics; shipping signing and Keychain protection are unchanged.

Live acceptance after entering a funded key:
1. Test connection; find published recipes with exclusions and duration constraints. Verify each source.
2. Create “Naan bread pizza” with only its title. Ask for just naan ingredients and method, inspect the source/yield and unchanged pizza content, then Apply, Undo and Save.
3. Paste a recipe URL; try a blocked/non-recipe page and verify no recipe is invented.
4. Import recipe text/photo and check it against the original.
5. Generate a cover, dismiss without applying, generate again and explicitly accept.
6. Check step ingredient references and exact recipe amounts.
7. Remove the key, test offline/manual entry and on-device formatting.

Live model quality/latency, account availability, credits and image verification cannot be established by mocked tests.
