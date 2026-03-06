{
  "id": "5fb0cccd",
  "title": "Build and run LocalCoder on connected iPhone",
  "tags": [
    "ios",
    "device",
    "xcode"
  ],
  "status": "blocked",
  "created_at": "2026-03-06T01:00:43.181Z"
}

Tried to build and run `LocalCoder` on the connected device `Cody Bontecou’s iPhone` using the ios-device-build workflow.

Results:
- Project detection: `LocalCoder.xcodeproj`
- Scheme: `LocalCoder`
- Platform support: `iphoneos iphonesimulator`
- Connected device found: `Cody Bontecou’s iPhone (00008150-001405DA2188401C)`
- Bundle ID: `com.localcoder.app`

Blocked by signing:
- `Signing for "LocalCoder" requires a development team. Select a development team in the Signing & Capabilities editor.`

Next step needed:
- Configure a Development Team in Xcode for the `LocalCoder` target, then rerun the build/install step.
