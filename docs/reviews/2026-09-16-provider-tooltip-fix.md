# SPM-008 — Provider tooltip hover-area fix

16 September 2026. Implementer: Frontend/testing `w2:p9`
(`openai-codex/gpt-5.6-sol`, high). This is implementation evidence, not
independent review or acceptance.

## Finding and fix

The owner screenshot matches the source hierarchy: in
`LLMSpendMonitor/UI/Dashboard/DashboardRootView.swift`, the provider card had
`.help("Drag to reorder providers")` after its card-wide `draggable` and
`dropDestination` modifiers. That outer help covered descendants, including
the SPM-007 status badge help.

The fix removes only the card-wide `.help`. The card-wide `draggable` and
`dropDestination` behavior is unchanged. `ProviderCard` still owns:

- `Drag to reorder providers` help on the six-dot drag handle;
- `ProviderStatusPresentation.explanation` help on the status badge;
- the existing drag-handle VoiceOver label and status VoiceOver label/hint.

No regression test was added: the bug is SwiftUI hover hit-testing/modifier
precedence, which the current unit harness cannot observe. Existing targeted
shell/status tests compile the changed hierarchy and protect the status
presentation/accessibility contract.

## Exact SPM-008 diff

```diff
                         .dropDestination(for: String.self) { values, _ in
                             guard
                                 let rawValue = values.first,
                                 let draggedProviderID = ProviderID(rawValue: rawValue)
                             else { return false }
                             return moveProvider(draggedProviderID, provider.id)
                         }
-                        .help("Drag to reorder providers")
```

No other source or test file was changed for SPM-008. Existing dirty-worktree
changes for SPM-005/006/007 and unrelated work were preserved.

## Exact checks

Targeted unsigned unit test/build:

```bash
xcodebuild test \
  -project LLMSpendMonitor.xcodeproj \
  -scheme LLMSpendMonitor \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:LLMSpendMonitorTests/MenuBarShellTests \
  -derivedDataPath /tmp/spm-008.TPUChj/DerivedData \
  -resultBundlePath /tmp/spm-008.TPUChj/SPM-008-targeted.xcresult
```

Result: `TEST SUCCEEDED`; 15 passed, 0 failed, 0 skipped.
Result bundle: `/tmp/spm-008.TPUChj/SPM-008-targeted.xcresult`.

Whitespace:

```bash
git diff --check
```

Result: exit 0.

## Not verified

- Native hover behavior was not rechecked in a launched app; the owner-provided
  screenshot is the reproduction, while the fix is source-verified.
- No UI suite was run, because no isolated UI test currently asserts native
  tooltip text without touching the broader debug app environment.
- No installation, restart, live API, credentials, Keychain, commit, or push
  was performed.
