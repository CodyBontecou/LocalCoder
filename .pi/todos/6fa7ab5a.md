{
  "id": "6fa7ab5a",
  "title": "Add in-app debug panel for generation failures",
  "tags": [
    "ios",
    "debug",
    "swiftui"
  ],
  "status": "closed",
  "created_at": "2026-03-06T00:53:30.066Z"
}

Added an in-app debug panel and generation instrumentation.

Implemented:
- `LocalCoder/Services/DebugConsole.swift`: shared persisted debug log store with categories/levels, JSON persistence in Documents/Debug, memory warning logging, clear/export support.
- `LocalCoder/Views/DebugPanelView.swift`: collapsible in-app debug console UI with copy/clear, autoscroll, event/error counts.
- `LocalCoder/LocalCoderApp.swift`: injected `DebugConsole.shared` into the environment.
- `LocalCoder/Views/ChatView.swift`: embedded the debug panel in chat and added a toolbar toggle.
- `LocalCoder/Services/LLMService.swift`: logged model load/unload, generation start/progress/finish/failure/cancellation with richer error details.
- `LocalCoder/ViewModels/ChatViewModel.swift`: logged chat send flow, tool-call parsing/execution, cancellation, and surfaced cancellation more cleanly.

Validation:
- `xcodebuild -project LocalCoder.xcodeproj -scheme LocalCoder -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO` ✅
