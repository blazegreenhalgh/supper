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
- Food photo editing: GPT Image 2.5 Sunburst, Images edits endpoint with a high-fidelity JPEG reference. Generate cover → Polish my photo accepts a Photos upload or the current recipe image. The prompt preserves the photographed food, portions, arrangement and plate while improving lighting, colour and framing. Original/Edited comparison is required before explicit acceptance; AI edits can still alter details and are labelled in Notes.
- Online covers: chat or Generate cover → Find online searches actual web-tool sources, or reads an explicit public HTTPS recipe/photo link. Photos come only from downloaded JSON-LD/Open Graph/Twitter metadata or a supplied image URL, never model-written image URLs. Downloads enforce public HTTPS on redirects, content/size limits and real image decoding; source and image links are retained in Notes. No generation fallback is used if search fails.
- Small ingredient formatting, tag suggestions and cookbook filter interpretation remain on-device. Manual editing, title-only saving, deterministic quantities and URL import do not require a key.

## Published recipes only

There is no Create with AI discovery mode. The API must run its web-search tool; URLs are accepted only from completed tool results, not fabricated prose or citations. A public HTTPS URL explicitly pasted in the current request can be read directly instead.

Supper downloads those recipe pages and requires complete structured ingredients/methods before accepting them. Search snippets are never used as recipe content. Selection is one bounded model request across downloaded candidates; the model returns indexes, not generated recipes. Hard requirements with missing evidence must be rejected. Missing/blocked sources produce an actionable error, never model-memory fallback.

For recipe edits, chat selects one supporting downloaded recipe, returns a bounded patch and passes source-evidence validation. New ingredient amounts must match complete source rows or literal user input. New method steps must match complete source steps or literal user input. Recipe patches cannot invent cooking times, omit parts of source steps, or overwrite photos, tags, collections, notes, original source URLs or reactions. Group labels and explicit user edits are permitted; departures from the source must be explained for review. Scaling in chat directs the user to the existing servings control rather than generating quantities.

One small structured request routes natural-language chat to recipe editing, online photos, generation or photo enhancement. Ambiguous photo requests show explicit choices. The photo menu bypasses routing when the user has already selected an action. Photo actions operate separately from recipe evidence validation and only change the image plus its credit after review.

A citation does not certify a recipe's safety or suitability. Users must still review matches, exclusions and any requested adaptations.

## Draft behavior and performance

Ask AI starts as a permanent collapsed Liquid Glass bar over the recipe editor on iOS 26, with a system material fallback. Tap the bar to expand/minimise; there is no separate entry button or close control. The editor renders behind the glass, with extra scroll-content margin so its last fields remain reachable above the bar. Ingredients, individual ingredient and method-step forms, tags, collections and notes remain navigable while chat is open. Minimising retains conversation, input, pending changes and undo history; ongoing requests continue. Stop or leaving the recipe editor cancels local work and ignores late results.

Discovery centres a glass input among soft animated colour, an orbiting halo and compact inspiration chips. Loading uses the same treatment with a short status tied to the actual search stage and a Cancel action that preserves the prompt. Canvas motion pauses when inactive and becomes static with Reduce Motion. Results retain source labels, counts and decisions, with source information in the options menu. Red/green swipe feedback belongs only to the translated top card; the stationary stack stays neutral.

Preview opens a read-only recipe page. Changes mode shows additions, the previous values of edits, and removed ingredients and steps with explicit labels and strikethrough. Recipe mode shows the proposed result, including source notes. Each preview targets a fixed suggestion; a newer response cannot silently replace the edit being approved.

Apply changes the unsaved draft, Save commits it; Cancel discards it. Suggestions remain previewable after manual changes, but Apply requires a matching draft and a new request starts from the latest manual edits. Apply and Undo are disabled while an individual ingredient or step form has unfinished input. Undo is also rejected after newer draft edits.

Photo proposals use photo-only conflict checks, preserving recipe edits made while a photo loads. A newer manual photo blocks replacement. Chat photo acceptance has the same exact-draft Undo protection. Each photo preview targets one fixed result; previews display original/current comparisons, source credit or AI provenance. Cover tools also stage results until Use photo.

Research reads up to eight pages, three at a time, and batches relevance checks instead of running a model session per candidate. An in-memory cache retains up to 16 public recipe pages for ten minutes to speed follow-ups. It stores no keys or private drafts. Context/output sizes are bounded, with no silent truncation of accepted source recipes. Failed/partial/refused responses never apply. Automatic paid retries are intentionally avoided.

Method groups retain the existing readable Markdown representation in the CloudKit step text field. No production schema migration is required.

## Privacy and billing

Settings explains data transfer before saving a key. User-triggered AI sends relevant recipe content to OpenAI; online search also queries the web and Supper reads public publisher pages. New covers send title and ingredients. Photo enhancement sends an orientation-corrected, downsampled JPEG of the supplied food photo, without camera metadata; uploaded bytes are the reference for the edit, not a text-only replacement prompt. Requests use store:false on Responses, ephemeral URL sessions, and no API redirects. Provider error text is never displayed or logged, preventing echoed keys/private content from leaking. OpenAI's API retention policies still apply; store:false is not a zero-retention guarantee.

Implementation references: [image generation and editing guide](https://developers.openai.com/api/docs/guides/image-generation), [Images edits JSON request schema](https://developers.openai.com/api/reference/resources/images/methods/edit).

API billing is separate from ChatGPT. Show clear errors for invalid/restricted keys, model access, exhausted credits, rate limits, timeouts, and provider failures. Stopping a request does not necessarily prevent provider charges for work already processed.

## Verification

Mocked transport tests cover model IDs, structured output, required search, source provenance, malformed/refused/incomplete responses, sanitized billing errors, key input validation, connection testing and image responses. Evidence tests reject invented ingredient amounts and altered/incomplete method steps. Existing draft/undo, quantity, formatting and discovery regressions remain.

UI coverage includes opening AI settings, saving/replacing/removing a fixture key, persistence across app relaunch, chat alongside ingredient/step navigation, preview removals, stale and unfinished-edit protection, apply/undo, and existing discovery flows. A deterministic proposal is available only in DEBUG builds with both `--ui-testing` and `--recipe-chat-ui-testing`. No real key or live generation is needed for CI.

Photo tests cover metadata provenance, unsafe URLs, preservation of newer recipe edits, stale photo rejection, photo undo, image-edit request bytes/model/fidelity and action routing schema. DEBUG `--ui-testing --recipe-photo-ui-testing` stages image fixtures for native comparison, source-preview, apply/undo and upload-option UI coverage; it performs no paid requests.

CI ad-hoc-signs simulator builds with `Tests/UI/Simulator.entitlements` so real Keychain operations have an app identity. This simulator-only identity is passed by the workflow, never used by device or distribution builds. The focused Keychain test runs before the remaining UI suite for faster diagnostics; shipping signing and Keychain protection are unchanged.

Live acceptance after entering a funded key:
1. Test connection; find published recipes with exclusions and duration constraints. Verify each source.
2. Create “Naan bread pizza” with only its title. Ask for just naan ingredients and method, inspect the source/yield and unchanged pizza content, then Apply, Undo and Save.
3. Paste a recipe URL; try a blocked/non-recipe page and verify no recipe is invented.
4. Import recipe text/photo and check it against the original.
5. Generate a cover, dismiss without applying, generate again and explicitly accept.
   Ask chat to find an online photo, verify the source, preview and use it. Also try a direct photo URL and a blocked page. Upload a food photo via Generate cover → Polish my photo; compare original and edited food details, apply, save and reopen.
6. Check step ingredient references and exact recipe amounts.
7. Remove the key, test offline/manual entry and on-device formatting.

Live model quality/latency, account availability, credits and image verification cannot be established by mocked tests.
