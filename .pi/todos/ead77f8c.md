{
  "id": "ead77f8c",
  "title": "RTL (right-to-left) layout testing and fixes",
  "tags": [
    "localization",
    "testing",
    "RTL"
  ],
  "status": "open",
  "created_at": "2026-03-06T07:46:16.138Z"
}

## Description
Test the app with RTL languages (Arabic, Hebrew) and fix any layout issues. SwiftUI handles most RTL automatically, but custom layouts may break.

## Testing Steps
1. In Xcode scheme, set `Application Language` to `Right-to-Left Pseudolanguage`
2. Run through every screen: Chat, Files, Git, Settings, Model Manager, Code Editor, Debug Panel
3. Check for layout issues

## Known Risk Areas
- **ChatView.swift**: User messages aligned `.trailing`, assistant `.leading` — should flip for RTL ✅ (SwiftUI handles this)
- **GitView.swift:159**: `.frame(width: 50, alignment: .leading)` — fixed width + alignment, verify it flips
- **ChatView.swift:335/352**: `.frame(width: 60, alignment: .leading)` — same concern
- **ConversationListView.swift:143**: Chevron right icon `"chevron.right"` — should flip to `"chevron.left"` in RTL, or use `.environment(\.layoutDirection, .rightToLeft)`
- **Swipe actions**: `swipeActions(edge: .trailing)` — verify swipe direction feels natural in RTL

## Notes
- SF Symbols auto-mirror for RTL if using `.symbolRenderingMode(.hierarchical)` or similar
- No `.flipsForRightToLeftLayoutDirection` calls found — may need to add some
