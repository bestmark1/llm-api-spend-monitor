# SPM-008 — independent source review

17 September 2026. Reviewer: Senior developer (Claude Opus 5), Desktop mode.
Read-only review of work implemented by Frontend/testing `w2:p9`. The
implementer's own evidence is
[`2026-09-16-provider-tooltip-fix.md`](2026-09-16-provider-tooltip-fix.md); this
document is the independent check required before acceptance, and it does not
accept the task on the owner's behalf.

## Scope

SPM-008 only: the hover-help area of the provider card. `ProviderStatusPresentation`
and the status-item context menu belong to SPM-007, which was reviewed and
accepted for source and unit on 15 September; they are not re-reviewed here.

The working tree also carries this reviewer's own uncommitted changes to
`ProviderCard.swift` and `DashboardRootView.swift` (provider marks, composition
bar, panel sizing). Every check below was run against that combined tree, and
each SPM-008 criterion was verified in the tree as it now stands rather than in
isolation.

## Criteria

| Criterion | Result | Evidence |
|---|---|---|
| Badge hover shows its own `explanation` | Pass (source) | `ProviderCard.swift:772` — `.help(presentation.explanation)` on `statusBadge` |
| Drag help only on the six dots | Pass | `ProviderCard.swift:295` is the sole `.help("Drag to reorder providers")` in the target; it sits on the 12×30 handle, after `.contentShape(Rectangle())` |
| No card-wide help remains | Pass | `grep` for `.help("Drag` across `ProviderCard.swift` and `DashboardRootView.swift` returns one hit, the handle |
| Whole card still draggable and a drop target | Pass | `DashboardRootView.swift:213-214` — `.draggable(provider.id.rawValue)` and `.dropDestination(for: String.self)` unchanged |
| VoiceOver meaning preserved | Pass | Handle keeps `accessibilityLabel("Drag <provider> to reorder")` (`:297`); badge keeps `accessibilityLabel`/`accessibilityHint` from `ProviderStatusPresentation` (`:772-775`) |
| Targeted test/build | Pass, reproduced | `MenuBarShellTests` 15 passed / 0 failed / 0 skipped |
| `git diff --check` | Pass, reproduced | exit 0 |

Additionally reproduced on the combined tree: full unsigned gate —
`LLMSpendMonitorTests` 187 passed / 2 skipped / 0 failures,
`LLMSpendMonitorUITests` 8 passed / 0 failures, `** TEST SUCCEEDED **`.

## Findings

**F1 / P2 — the stated root cause is not proven, only the fix is.**
The implementation report explains the defect as an ancestor `.help` covering
descendants and outranking the badge's own help. The removal demonstrably
eliminates the competing modifier, and with it the only possible source of the
wrong tooltip text; that much is verifiable in source. The precedence claim
itself is not, because native hover cannot be observed from here: Spender is an
`LSUIElement` accessory app and its panel is not reachable by UI automation. The
outcome is therefore sound regardless of whether the explanation is exact, but
the explanation should not be treated as established.

**F2 / P3 — discoverability narrowed, by design.**
The whole card remains draggable while only the handle now advertises it. A
person who never hovers the six dots gets no hint that rows can be reordered.
This follows directly from what SPM-008 asked for and is not a defect, but it is
a deliberate trade the owner should be aware of.

**F3 / P3 — no regression test, and none is currently possible.**
The implementer's reasoning is correct: `.help` is a native tooltip that the unit
harness cannot read, and XCUITest has no assertion for it either. The existing
tests protect the status presentation and accessibility contract, not the
tooltip. Worth recording as a known blind spot rather than treating as an
omission.

## Verdict

**Accepted for source and unit.** The change is minimal, matches its stated
diff exactly, and no unrelated behaviour moved with it.

**Not accepted for visual behaviour**, which remains outstanding per the task's
own criterion. Native hover over an `Incomplete report` badge must be checked in
a running build. The demo build can satisfy this without an install: launch with
`--demo-data` and hover a badge. Installation, restart and commit remain the
owner's calls and were not performed.
