# WebPuppet

WebPuppet is a private, developer-signed iOS web automation app for personal use.

## Why this exists
This project rebuilds the core product behavior of a reverse-engineered abandoned iOS app:
- embedded browser automation with `WKWebView`
- JavaScript injection and message handlers
- record taps/interactions into reusable flows
- replay with multi-signal locators and fallback matching
- local-first persistence and JSON flow import/export

## Current architecture
- `Telescopure/App`: app entry and root flow editor UI
- `Telescopure/Features/Browser`: SwiftUI `WKWebView` wrapper and controls
- `Telescopure/Features/Runner`: flow replay engine
- `Telescopure/Features/Documents`: `.webpuppetflow` document support
- `Telescopure/Core/Models`: flow/step/locator/run data models
- `Telescopure/Core/WebBridge`: JS ↔ native bridge
- `Telescopure/Core/Persistence`: JSON repository
- `Telescopure/Core/Logging`: in-app visible logs
- `Telescopure/Resources/InjectedJS/Recorder.js`: recording/replay JS helpers
- `Telescopure/Features/Scanning`, `Features/OCR`, `Features/Intents`, `Core/Utils/AIService`: extension scaffolds

## MVP behavior
1. Open arbitrary websites in an embedded browser.
2. Toggle Record mode.
3. Tap elements; injected JS captures metadata and sends it via:
   - `writeLog`
   - `didClickElement`
4. Save captured click steps into a flow.
5. Replay the flow with fallback locator matching.
6. See logs and extracted outputs.
7. Export/import JSON-based `.webpuppetflow` files.

## Flow format
The flow file is plain JSON (easy to inspect).

Top-level:
- `id`, `name`, `startURL`, `createdAt`, `updatedAt`
- `steps`
- `inputDefinitions`
- `outputDefinitions`

Each step includes:
- `order`, `type` (`click`, `typeText`, `wait`, `extractText`)
- `locator`
- `inputValue` or `inputBindingKey`
- `outputKey`
- `options` (`continueOnFailure`, delay)

Locator stores multiple matching signals:
- id
- CSS selector
- tag/classes
- aria-label
- `data-*`
- text snippet
- sibling index
- parent trail
- frame/shadow metadata placeholders

## Replay strategy
Current fallback order:
1. exact id
2. CSS selector
3. tag + classes
4. aria-label
5. text snippet match

Additional fallbacks (data attributes, ancestor constraints, sibling heuristics, iframe path) are already represented in model fields and can be expanded in JS helper logic.

## Limitations (current)
- Recorder currently creates click steps automatically.
- Flow step editing UI is minimal.
- Barcode/OCR/AI/App Intents are scaffolded, not fully implemented.
- iOS build must be run on macOS/Xcode (this environment cannot execute `xcodebuild`).

## Local development notes
- App uses broad ATS allowances for practical personal-use browsing.
- Camera permission text is included for barcode flow inputs.
- Custom document type and URL scheme are configured:
  - extension: `.webpuppetflow`
  - URL scheme: `webpuppet://`
