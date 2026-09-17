# SPM-007 — Provider statuses and status bar context menu

15 September 2026. Implementer: Frontend/testing `w2:p9`
(`openai-codex/gpt-5.6-sol`, high). This is the implementer's evidence report,
not independent review or acceptance.

## Findings

No known source or unit-test findings remain in the owned change. Native UI,
hover placement, VoiceOver speech and a physical status-item right click were
not exercised; those limitations remain open for independent review.

## Files changed

- `LLMSpendMonitor/UI/Providers/ProviderCard.swift`
  - Added a deterministic internal status presentation value.
  - Renamed `Current` to `Up to date`.
  - Mapped `.processing` to `Processing` with an hourglass and a short exact
    explanation instead of presenting it as current.
  - Split `.usageUnavailable` into `Usage unavailable` and `.partialData` into
    `Incomplete report` while retaining warning semantics.
  - Added native `.help`, a VoiceOver label and a VoiceOver hint to every
    status badge. The visible badge remains understandable without hover.
- `LLMSpendMonitor/App/StatusBarController.swift`
  - Routes primary and context clicks separately.
  - Builds a native `NSMenu` with exactly `Customize`, `Connections`,
    `Settings`, and `Quit Spender`.
  - Customize and Connections update `AppState` before showing the panel.
  - Settings requests the existing SwiftUI Settings scene; Quit shares the
    same terminate closure as the panel's existing Options action.
- `LLMSpendMonitor/UI/Dashboard/DashboardRootView.swift`
  - Minimal bridge from the AppKit context-menu request to SwiftUI's existing
    `openSettings` environment action.
- `LLMSpendMonitorTests/App/MenuBarShellTests.swift`
  - Covers status titles, explanations, semantic icons/tones, accessibility
    contract, left/right click routing, exact menu composition and actions.

`LLMSpendMonitorUITests/MenuBarLifecycleUITests.swift` was not changed because
the requested contracts are covered deterministically by unit tests and its
current app launcher does not isolate all Keychain, cache, and settings reads.
SPM-005/006 provider, Connections and research changes were preserved.

## UX approach

Applied `clarify` and `swiftui-ui-patterns` with the existing
`.impeccable.md` context. Status titles carry the primary meaning; hover and
VoiceOver provide one concise sentence without adding repeated expanded-card
copy or redesigning the card.

## Exact checks

Targeted unit gate:

```bash
xcodebuild test \
  -project LLMSpendMonitor.xcodeproj \
  -scheme LLMSpendMonitor \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:LLMSpendMonitorTests/MenuBarShellTests \
  -derivedDataPath /tmp/spm-007-targeted-final2.iBClbk/DerivedData \
  -resultBundlePath /tmp/spm-007-targeted-final2.iBClbk/SPM-007-targeted.xcresult
```

Result: `TEST SUCCEEDED`; 15 passed, 0 failed, 0 skipped.

Unsigned unit-only gate:

```bash
xcodebuild test \
  -project LLMSpendMonitor.xcodeproj \
  -scheme LLMSpendMonitor \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:LLMSpendMonitorTests \
  -derivedDataPath /tmp/spm-007-unit-final2.HV6j6u/DerivedData \
  -resultBundlePath /tmp/spm-007-unit-final2.HV6j6u/SPM-007-unit.xcresult
```

Result: `TEST SUCCEEDED`; 187 total, 185 passed, 0 failed, 2 skipped.
Both skips are the existing live Data Protection Keychain tests, which require
a signed application-identifier entitlement.

Whitespace:

```bash
git diff --check
```

Result: exit 0. Because this report is untracked, it was also checked directly:

```bash
! grep -nE '[[:blank:]]+$' docs/reviews/2026-09-15-provider-status-context-menu.md
python3 -c "from pathlib import Path; assert Path('docs/reviews/2026-09-15-provider-status-context-menu.md').read_bytes().endswith(b'\\n')"
```

Result: no trailing whitespace; final newline present.

## Not verified

- UI/visual behavior in a launched test app: badge wrapping and color in native
  light/dark/high-contrast appearances, hover help placement, VoiceOver speech,
  physical left/right clicking, menu placement, and the Settings window route.
- UI tests were not run: the current debug/test app does not prove isolation
  from real Keychain, cache, and settings, even though it isolates selected
  UserDefaults suites.
- No live API, credentials, installed `/Applications/Spender.app`, install,
  restart, signing update, commit, or push was used.
