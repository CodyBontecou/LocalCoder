{
  "id": "33cfa7ea",
  "title": "Audit and fix uppercase text style for international compatibility",
  "tags": [
    "localization",
    "code-changes",
    "design"
  ],
  "status": "open",
  "created_at": "2026-03-06T07:46:05.756Z"
}

## Description
The app extensively uses uppercase hardcoded strings for UI labels: `"HISTORY"`, `"SIGN IN"`, `"MODELS"`, `"GENERATING"`, etc. This is problematic for localization because:

1. Some languages (Japanese, Chinese, Korean, Arabic, Hebrew) have no concept of uppercase
2. Uppercase can change meaning in some languages (e.g., German nouns are always capitalized)
3. Turkish has special uppercase rules (`i` → `İ`, not `I`)

## Recommended Fix
Store strings in natural case and apply `.textCase(.uppercase)` via SwiftUI modifier or the theme system:

```swift
// Before
Text("HISTORY")

// After
Text("History")
    .textCase(.uppercase)
```

This way translators provide natural-case translations, and the uppercase styling is applied only where appropriate. The `.textCase(.uppercase)` modifier respects locale rules.

## Scope
~60+ uppercase strings across all view files. The theme system (`LocalCoderTheme.swift`) may already have font styles where `.textCase(.uppercase)` could be applied globally.
