{
  "id": "aede85fa",
  "title": "Export localizations and set up translation workflow",
  "tags": [
    "localization",
    "workflow",
    "priority-low"
  ],
  "status": "open",
  "created_at": "2026-03-06T07:46:27.731Z"
}

## Description
Once all strings are in the String Catalog and code changes are complete, set up the export/import workflow for translators.

## Steps
1. Use `Product → Export Localizations...` in Xcode to generate `.xcloc` bundles
2. Decide on target languages for initial release (e.g., Spanish, Japanese, Chinese Simplified, German, French, Arabic)
3. Send `.xcloc` files to translators or use a service (Crowdin, Lokalise, POEditor, etc.)
4. Import completed translations via `Product → Import Localizations...`
5. Add translated languages to `knownRegions` in `project.pbxproj`

## Alternative: Community Translation
- Host strings on GitHub as a `.xcstrings` JSON file
- Accept PRs for new languages
- Lower cost, slower, but builds community

## Notes
- ~88 unique strings is a small translation job (~1-2 hours per language for a professional translator)
- Budget approximately $50-100 per language for professional translation of this volume
