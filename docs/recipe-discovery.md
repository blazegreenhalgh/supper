# Recipe discovery and library cards

Tap **What are you craving?** on the library screen, or **Find new recipes** in the library/search menu.

- A centred glass input, short inspiration chips and warm kitchen illustration keep entry simple. Loading shows a smoothly stirring spoon, bubbles and rising steam; Reduce Motion shows a still illustration, and motion pauses outside the active scene.
- Discovery finds published recipes online using the configured OpenAI API key. It never generates recipes. GPT-5.6 Terra forms the search and selects up to five downloaded recipes; the app imports their structured ingredients, methods and publisher photos.
- Missing evidence, unsupported pages and requests with no matching recipes produce a retryable error. Source links stay attached.
- Tap a result to preview and edit its draft. Swipe right to keep or left to discard; buttons and VoiceOver actions offer the same decisions. Undo restores the last discarded draft.
- Red/green feedback moves with the top card. The stationary stack remains neutral.
- Stack and grid share the same drafts and decisions. Keep saves to the active household using Core Data/CloudKit. A failed save leaves the draft available; repeated decisions cannot create duplicate recipe IDs.
- Closing discovery retains its session while the library view remains alive. Cancel preserves the prompt. Unkept suggestions are transient.

## Library card actions

Long-press a saved recipe card for a native preview and menu: Open, Collection, Add to groceries, Edit, Share source (when available), and Delete. The Collection submenu shows current memberships as toggles. Membership changes save immediately; grocery selection and recipe editing use their existing sheets. Delete requires confirmation.

Drag a card from one home collection onto another collection section to move it. Only the source membership is removed; other memberships remain. Dragging from All recipes adds to the destination. Empty home collections remain visible as drop targets. Same-collection drops preserve membership. Deleted recipes, stale sources, unknown destinations and household mismatches are rejected. The context menu provides an accessible alternative to dragging.

## Privacy and verification

See [recipe-assistant.md](recipe-assistant.md) for API-key storage, data transfer, source requirements and billing. Recipe organisation uses local household data; discovering and editing recipe content uses online sources.

Domain and persistence tests cover source evidence, stable draft identities, collection proposal validation, membership persistence, drop semantics, stale-state protection and undo. UI fixtures exercise previews/actions, collection moves, chat draft/save behaviour, discovery cancellation, keep/discard and both result layouts. Fixtures never use a live API key.
