# SPM-006 — Qwen connection help

15 September 2026. Implementer: Middle `w2:pA`
(`opencode/muse-spark-1.3-contributor-free`, high).
Reviewer is a different agent; this report does not declare acceptance.

## Findings fixed (reviewer w2:p9, F1)

- P1: removed the unproven instruction to copy the request ProductCode from
  Billing Details / User Center and the claim that it reliably yields
  product-filtered spend. The official QueryAccountBill reference describes
  the User Center code as response `PipCode`, while the client sends a
  mandatory request `ProductCode`; the correspondence is unproven and no
  value was guessed. The UI now states that this Spender version requires a
  QueryAccountBill ProductCode, that Alibaba publishes no reliable mapping
  from the visible User Center code, that guessing is not allowed, and that
  billing spend may stay unavailable until the integration is updated.
- P2: `credentialHelp` now states explicitly that the pay-as-you-go Model
  Studio key with same-region API Host is only for model access validation
  and gives no billing access; money metrics need the separate RAM user
  AccessKey pair with the exact read-only actions. The regression test
  asserts this separation and the absence of the product-filtered promise
  and the Billing Details instruction.

## Exact boundary of this fix

- Only Qwen help strings and the Qwen regression test changed. No change to
  `QwenProvider`, `ConnectionViewModel`, fields, validation, backend,
  billing logic, Keychain, xAI SPM-005 lines, other providers, or
  coordinator documents (`CLAUDE.md`, backlog, handoff untouched).

## What changed (Qwen help only) — F1 final state

- `LLMSpendMonitor/Providers/ProviderRegistry.swift` — Qwen `credentialHelp`
  only: pay-as-you-go Model Studio key with same-region API Host for model
  access validation only; Token Plan and Coding Plan keys unsupported; this
  key alone gives no billing access — money metrics need the separate RAM
  user AccessKey pair with the exact read-only actions.
- `LLMSpendMonitor/UI/Connections/ProviderConnectionView.swift` — Qwen-only
  block (`viewModel.id == .qwen`) with two clickable official guide links
  and stable identifiers `connection.qwen.modelStudioGuide` /
  `connection.qwen.ramGuide`; billing section states where the RAM-user
  AccessKey is created, exact read-only permissions and the one-time secret.
  It requires a QueryAccountBill ProductCode without naming Billing
  Details / User Center as its source, warns against guessing, and notes
  billing spend may stay unavailable until the integration is updated.
  No new fields, no redesign.
- `LLMSpendMonitorTests/Providers/ProviderRegistryTests.swift` — regression
  test `testQWENHelpExplainsSeparateModelAndBillingCredentials`.
- SPM-005 xAI lines preserved byte-for-byte; `QwenProvider`, billing,
  Keychain, `ConnectionViewModel`, validation and other providers untouched.

## Official sources (all opened 2026-09-15)

- [Model Studio API key](https://help.aliyun.com/en/model-studio/get-api-key):
  pay-as-you-go key per region with API Host shown at creation (shown once
  for new `sk-ws-` keys); Token/Coding Plan keys (`sk-sp-`) are separate.
- [RAM AccessKey pair](https://www.alibabacloud.com/help/en/ram/user-guide/create-an-accesskey-pair):
  RAM console → Users → username → Credential → AccessKey; secret shown
  only once; RAM user recommended, account key not recommended.
- [QueryAccountBill](https://help.aliyun.com/en/user-center/developer-reference/api-bssopenapi-2017-12-14-queryaccountbill):
  RAM action `bss:QueryAccountBill` on All Resources; the doc ties the visible
  User Center code to response `PipCode`, but no reliable mapping to the
  mandatory request `ProductCode` is published (value not guessed here).
- [QueryAccountBalance](https://help.aliyun.com/en/user-center/developer-reference/api-bssopenapi-2017-12-14-queryaccountbalance):
  RAM action `bss:DescribeAcccount` on All Resources (provider balance call).
- Microcopy guided by the `clarify` skill with `.impeccable.md` context
  (calm, specific, consistent terms).

## Checks

- `git diff --check`: clean.
- Unit tests (unique temp derivedData/resultBundle, no live API, no Keychain,
  no installed app):
  `xcodebuild test -project LLMSpendMonitor.xcodeproj -scheme LLMSpendMonitor -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:LLMSpendMonitorTests/ProviderRegistryTests -only-testing:LLMSpendMonitorTests/ConnectionViewModelTests -only-testing:LLMSpendMonitorTests/QwenProviderTests`
  → TEST SUCCEEDED, 26 tests, 0 failures, 0 skipped.
  Re-run after F1 fix in a new unique /tmp dir: TEST SUCCEEDED, 26 tests,
  0 failures, 0 skipped; `git diff --check` clean.

## Not verified

- Visual layout of the Qwen card in the running app (links, wrapping,
  identifiers) — no native UI inspection was available.
- Live Alibaba Cloud responses and the exact Model Studio product-code value
  for this account — never requested; credentials were not read.
- Whether any visible User Center code equals the required request
  ProductCode — unproven; the UI says so honestly instead of instructing.
