# Supper development notes

- Keep the UI native SwiftUI-first. Avoid custom replicas of standard Apple controls.
- Prefer system materials, sheets, navigation transitions, context menus and SF Symbols.
- Keep recipe capture low-friction: image + title must always be enough to save.
- No meal history, cooked-state tracking, star ratings or last-cooked metadata.
- The shared household library and grocery list are CloudKit-backed.
- Reactions are per person; recipes themselves are shared.
- URL import should prefer structured recipe metadata and use AI only as a cleanup/fallback layer.
- Keep offline use functional and treat CloudKit as sync, not as the UI data source.
