# Optional provider integration matrix

Rows for Kimi, Qwen / Alibaba Cloud, Mistral AI, OpenRouter and Perplexity are a historical snapshot of 2026-08-11 and were not re-verified. OpenCode Zen, OpenCode Go and xAI reflect the accepted SPM-002 research of 2026-09-12 and the local check of 2026-09-14; see Current scopes below. This matrix distinguishes an ordinary inference key from administrative credentials. Spender must never label key validation or per-response accounting as account-wide spend history. An endpoint absent from checked sources is not proof that no such API exists anywhere.

| Provider | Ordinary API key | Account-wide balance or spend API | Required connection for Spender | Current implementation |
|---|---|---|---|---|
| Kimi | Authenticates inference and the documented balance request. | `GET /v1/users/me/balance` returns available, voucher, and cash balances in CNY for the domestic platform. Domestic and international keys/endpoints are separate. No account-wide cost-history endpoint is documented. | API key plus matching domestic/international endpoint. | Planned; next balance connector candidate. |
| Qwen / Alibaba Cloud Model Studio | Authenticates model calls. The Base URL depends on region, Workspace ID, and plan type. | Model usage is available in the console. `QueryAccountBill` exposes official daily billing with Alibaba Cloud AccessKey/RAM permissions, not the Model Studio inference key. | Model Studio API key + official Base URL for validation; AccessKey ID/secret with read-only BSS permission and the Model Studio Product Code from Billing Details for spend. | `/models` verifies model access. Separate billing credentials retrieve official daily payable amounts; both secret types stay in Keychain. |
| xAI / Grok (API account) | Authenticates inference; responses can include the exact cost of that request. | Management API exposes prepaid balance (`prepaid/balance`, USD cents as string) and team usage (`usage`, USD as number). A consumer Grok subscription and payments to an intermediary are a different account and are not shown by this API. | Management API key (separate from the inference key) + team scope; exact minimal billing-read ACLs unconfirmed. | Implemented; live unverified (see Current scopes). |
| Mistral AI | Authenticates inference. | Admin API `/v1/admin/usage` exposes billing usage and requires an Admin API key. | Admin API key; workspace filter is optional. | Planned. |
| OpenRouter | Authenticates inference and returns usage/cost per response. | Credits API returns total credits and total usage and requires a Management API key. | Management API key for balance; ordinary key alone is insufficient for the account credit report. | Planned. |
| Perplexity | Authenticates inference; responses include token and cost details for that request. | Official documentation exposes billing/usage in the console but does not document an account-wide billing API for ordinary API groups. | API key can validate access only. Account-wide history cannot be claimed unless Perplexity publishes a supported endpoint. | Planned. |
| OpenCode Zen | The opencode CLI itself is not a billing account: it has no balance. A console API key authenticates inference through the Zen gateway. | No supported public balance or USD spend-history API found in checked official documentation (2026-09-12); not proof of absolute absence. | Console API key for inference validation only. Account-wide balance/history cannot be claimed unless a supported endpoint is published. | Not implemented. |
| OpenCode Go | Console API key with `Authorization: Bearer` (as seen in console source). | Route `GET /zen/go/v1/usage` exists in console `dev` source and returns subscription quota windows (`rolling`/`weekly`/`monthly` with `status`, `percent`, `resetsAt`): quota percent, not Zen wallet/USD and not account-wide spend. Dev source does not guarantee a stable public contract; live availability unconfirmed. | Console API key for quota status only. | Not implemented. |

## Current scopes (research 2026-09-12, local check 2026-09-14)

Short README-ready wordings for a future README. They cover billing-provider support only, not a universal list of unsupported LLMs.

### OpenCode Zen — checked 2026-09-12

- Status: no supported public balance or USD spend-history API found in the checked official documentation. Not proof of absolute absence.
- Key: console API key validates inference access only.
- Metrics: per-response token usage is a provider-reported observation. Converting it to money using local prices yields a client-local estimate, not account-wide spend or wallet balance.
- Limitation reason: no supported public balance or USD spend-history endpoint was found in the checked official documentation; this does not establish absolute API absence.
- Sources: [OpenCode Zen docs](https://opencode.ai/docs/zen/), [accepted research](opencode-xai-feasibility.md#14-поддерживаемый-billing-api-в-проверенной-документации-не-найден).
- README-ready: `OpenCode Zen: official balance/spend API not found in checked docs; inference key validates access only.`

### OpenCode Go — checked 2026-09-12 (source, not a public contract)

- Status: quota route `GET /zen/go/v1/usage` present in console `dev` source; live availability and stability unconfirmed.
- Key: console API key with `Authorization: Bearer`.
- Metrics: subscription quota percent per window (`rolling`/`weekly`/`monthly`); no money amounts.
- Limitation reason: answers how much of the subscription window is used, not how much money is left; dev source does not guarantee a stable public contract.
- Sources: [Go quota route source](https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/console/app/src/routes/zen/go/v1/usage.ts), [accepted research](opencode-xai-feasibility.md#13-квота-go-маршрут-есть-в-исходниках-консоли).
- README-ready: `OpenCode Go: quota percent only, from an undocumented source route; not money, not a public contract.`

### xAI API account — research 2026-09-12, local check 2026-09-14

- Status: provider implemented in Spender; live account data not independently verified by us. History: a 2026-09-14 owner screenshot showed a visible saved-credential-rejected message (key type, refusal reason and a fresh live request were unknown at the time). Owner later reported replacing the xAI credential with a Management key and now seeing spend — owner report, not independent live verification.
- Key: Management API key created via Console → Settings → Management Keys (see Using Management API guide), separate from the inference key; team scope. Exact minimal billing-read ACLs unconfirmed.
- Note: if IP restrictions are configured on the key, check that the current outgoing public IP is allowed; VPN or network changes may affect it. An IP allowlist is not established as mandatory — the auth docs show `ipRanges`, so do not assume it is always required, and do not weaken or remove IP protection to diagnose.
- Metrics: prepaid balance (USD cents, string, negative on top-up) and team usage (USD, number, per model and call type); the key-validation endpoint carries no `/v1` prefix.
- Limitation reason: a consumer Grok subscription and payments to an intermediary are a different account and are not shown by the Management API.
- Sources: [Using Management API](https://docs.x.ai/developers/management-api-guide), [Billing Management](https://docs.x.ai/developers/rest-api-reference/management/billing), [Accounts and Authorization](https://docs.x.ai/developers/rest-api-reference/management/auth), [local diagnostics](../reviews/2026-09-14-xai-local-check.md).
- README-ready: `xAI: Management key with team scope shows prepaid balance and team usage; consumer Grok subscription is a separate account.`

## Official references

### OpenCode

- https://opencode.ai/docs/zen/
- https://opencode.ai/docs/go/
- https://raw.githubusercontent.com/anomalyco/opencode/dev/packages/console/app/src/routes/zen/go/v1/usage.ts
- https://github.com/anomalyco/opencode/issues/44189

### Kimi

- https://platform.kimi.com/docs/api/balance
- https://platform.kimi.com/docs/api/chat

### Qwen / Alibaba Cloud

- https://help.aliyun.com/en/model-studio/get-api-key
- https://help.aliyun.com/en/model-studio/first-api-call-to-qwen
- https://help.aliyun.com/en/model-studio/model-usage-statistics
- https://help.aliyun.com/en/model-studio/bill-query-and-cost-management
- https://help.aliyun.com/en/user-center/developer-reference/api-bssopenapi-2017-12-14-queryaccountbill

### xAI

- https://docs.x.ai/developers/rest-api-reference/management
- https://docs.x.ai/developers/management-api-guide
- https://docs.x.ai/developers/rest-api-reference/management/auth
- https://docs.x.ai/developers/rest-api-reference/management/billing
- https://docs.x.ai/developers/cost-tracking

### Mistral AI

- https://docs.mistral.ai/admin/admin-api/usage-metrics

### OpenRouter

- https://openrouter.ai/docs/api/api-reference/credits/get-credits
- https://openrouter.ai/docs/cookbook/administration/usage-accounting

### Perplexity

- https://docs.perplexity.ai/docs/getting-started/api-groups
- https://docs.perplexity.ai/docs/resources/changelog
