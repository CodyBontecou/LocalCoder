{
  "id": "db0d5fc9",
  "title": "Wrap non-Text hardcoded strings with String(localized:)",
  "tags": [
    "localization",
    "code-changes"
  ],
  "status": "open",
  "created_at": "2026-03-06T07:45:18.843Z"
}

## Description
Strings outside of `Text()` — in `.alert()`, `Button()`, `Label()`, accessibility labels, and string interpolation — are **not** auto-extracted by the String Catalog. These need to be explicitly wrapped in `String(localized:)`.

## Files & Locations
- **FilesView.swift**: `.alert("New File", ...)`, `.alert("New Folder", ...)`, `.alert("Rename", ...)`, `Label("Delete", ...)`, `Label("New File", ...)`, `Label("New Folder", ...)`, `Label("Rename", ...)`
- **ModelManagerView.swift**: `.alert("Delete Model?", ...)`, `Button("Delete", ...)`, `Button("Cancel", ...)`, `Button("OK", ...)`
- **ChatView.swift**: `Button("Cancel")`, `Button("Save")`, `.accessibilityLabel("Hide keyboard")`
- **GitView.swift**: `Button("Cancel")`, `Button("Clone")`, `Button("Done")`
- **CodeEditorView.swift**: `Button("Close", ...)`, `Button("Small (12)")`, `Button("Medium (14)")`
- **ConversationListView.swift**: `Label("Delete", ...)`

## Pattern
```swift
// Before
.alert("New File", isPresented: $showNewFileAlert)

// After
.alert(String(localized: "New File"), isPresented: $showNewFileAlert)
```
