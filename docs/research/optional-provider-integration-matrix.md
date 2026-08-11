# Optional provider integration matrix

Validated against current official documentation on 2026-08-11. This matrix distinguishes an ordinary inference key from administrative credentials. Spender must never label key validation or per-response accounting as account-wide spend history.

| Provider | Ordinary API key | Account-wide balance or spend API | Required connection for Spender | Current implementation |
|---|---|---|---|---|
| Kimi | Authenticates inference and the documented balance request. | `GET /v1/users/me/balance` returns available, voucher, and cash balances in CNY for the domestic platform. Domestic and international keys/endpoints are separate. No account-wide cost-history endpoint is documented. | API key plus matching domestic/international endpoint. | Planned; next balance connector candidate. |
| Qwen / Alibaba Cloud Model Studio | Authenticates model calls. The Base URL depends on region, Workspace ID, and plan type. | Model usage is available in the console. Billing queries use Alibaba Cloud BSS OpenAPI and Alibaba Cloud AccessKey/RAM permissions, not the Model Studio inference key. | Model Studio API key + official Base URL for validation. Full spend later needs Alibaba Cloud AccessKey ID/secret and billing scope. | API key and endpoint can be saved; `/models` verifies access without an inference charge. Financial metrics remain unavailable. |
| xAI / Grok | Authenticates inference; responses can include the exact cost of that request. | Management API exposes prepaid balance and team usage. | Management API key + team ID for account-wide data. | Planned. |
| Mistral AI | Authenticates inference. | Admin API `/v1/admin/usage` exposes billing usage and requires an Admin API key. | Admin API key; workspace filter is optional. | Planned. |
| OpenRouter | Authenticates inference and returns usage/cost per response. | Credits API returns total credits and total usage and requires a Management API key. | Management API key for balance; ordinary key alone is insufficient for the account credit report. | Planned. |
| Perplexity | Authenticates inference; responses include token and cost details for that request. | Official documentation exposes billing/usage in the console but does not document an account-wide billing API for ordinary API groups. | API key can validate access only. Account-wide history cannot be claimed unless Perplexity publishes a supported endpoint. | Planned. |

## Official references

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
