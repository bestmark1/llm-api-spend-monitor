# Provider contract validation

Status: documented baseline confirmed on 2026-07-16; live dashboard reconciliation is pending.

This gate exists to prevent the app from silently showing financially incorrect totals. Do not finalize `ProviderSnapshot`, cache schema, or provider decoders until the live checks below pass with sanitized organization data.

## Safety boundary

- Never paste an Admin API key into chat, source files, fixtures, shell history, logs, or screenshots.
- Export credentials only in the local terminal session as `OPENAI_ADMIN_KEY` and `ANTHROPIC_ADMIN_KEY`, then `unset` them after collection.
- Store raw and sanitized captures only under `.local/provider-contract-validation/`; `.local/` is gitignored.
- Fixtures may contain only sanitized response bodies. Remove organization, workspace, project, user, and API-key identifiers before copying anything into `LLMSpendMonitorTests/Fixtures/Contract/`.
- Use a fully closed UTC interval. Do not reconcile a still-changing current-day bucket.

## Documented baseline

### OpenAI

- Authentication: Organization Admin API key in `Authorization: Bearer`.
- Costs: `GET https://api.openai.com/v1/organization/costs`.
- Completion usage: `GET https://api.openai.com/v1/organization/usage/completions`.
- Time boundary: inclusive Unix `start_time`, exclusive Unix `end_time`.
- Pagination: request `page` from the previous response's `next_page` until `has_more` is false.
- Costs support daily buckets, up to 180 buckets per request. The response documents `amount.value` as a JSON number in major currency units and `amount.currency` as a lowercase ISO 4217 code.
- Completion usage supports `1m`, `1h`, and `1d` buckets; a daily request is limited to 31 buckets. Token fields are integer counts, and model detail requires `group_by=model`.
- Cost is authoritative. The app must not recompute money from tokens and a local pricing table.

Official references:

- https://developers.openai.com/api/reference/administration/overview
- https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs
- https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions

### Anthropic

- Authentication: Claude Console Admin API key in `x-api-key`, plus `anthropic-version: 2023-06-01`.
- Cost: `GET https://api.anthropic.com/v1/organizations/cost_report`.
- Message usage: `GET https://api.anthropic.com/v1/organizations/usage_report/messages`.
- Time boundary: inclusive RFC 3339 `starting_at`, exclusive `ending_at`.
- Pagination: request `page` from `next_page` until `has_more` is false.
- Daily usage supports at most 31 buckets. Usage and cost data usually appears within five minutes, but may arrive later.
- Cost amounts are decimal strings in the lowest USD unit. For example, `"123.45"` means 123.45 cents, or USD 1.2345; conversion must use `Decimal` and divide by 100 exactly.
- Priority Tier costs are absent from the cost endpoint. Priority usage may be shown separately but must not be folded into an allegedly complete money total.
- The Admin Usage and Cost API is unavailable for individual accounts and for Claude Platform on AWS.

Official references:

- https://platform.claude.com/docs/en/manage-claude/usage-cost-api
- https://platform.claude.com/docs/en/api/admin/cost_report
- https://platform.claude.com/docs/en/manage-claude/admin-api

## Live capture procedure

Choose one fully closed UTC day with known activity. Record the same start and end boundary in the provider dashboard before running the requests.

The preferred path is the checked local collector. It prompts for both keys without echoing them, keeps credentials out of process arguments, follows pagination with a 20-page safety cap, and writes raw plus sanitized captures under the gitignored `.local/` directory:

```bash
./scripts/collect-provider-contract-samples.zsh
```

By default it captures the previous fully closed UTC day. Override the interval only when that day has no representative activity:

```bash
START_UTC='2026-07-14T00:00:00Z' \
END_UTC='2026-07-15T00:00:00Z' \
./scripts/collect-provider-contract-samples.zsh
```

The collector follows `next_page` with unchanged interval parameters until `has_more` is false. At least one sanitized two-page sample is required across the two providers; if the selected day does not paginate naturally, use a longer closed interval for the pagination case.

## Sanitization

The collector redacts non-null organization, workspace, project, user and API-key identifiers, plus pagination cursors. It preserves nulls because nullability is part of the provider contract. Inspect every `*.sanitized.json` file manually before moving it into a tracked fixture directory.

Reject a sanitized file if it contains a credential prefix, email address, person name, organization name, or an unredacted identifier.

## Dashboard reconciliation record

For each provider, record:

| Check | OpenAI | Anthropic |
|---|---|---|
| Closed UTC interval | Pending | Pending |
| All pages captured | Pending | Pending |
| API money total | Pending | Pending |
| Dashboard money total for same interval | Pending | Pending |
| Difference explained and accepted | Pending | Pending |
| Token total reconciled | Pending | Pending |
| Freshness delay observed | Pending | Pending |
| Sanitized fixtures reviewed | Pending | Pending |

Acceptance requires exact agreement at the provider's displayed precision, or a written provider-specific explanation for tax, credits, discounts, omitted Priority Tier cost, or reporting lag. A mismatch must not be hidden with rounding.

## Schema decisions still blocked

Do not implement `ProviderSnapshot` or the disk cache schema until live samples answer all of these questions:

1. Whether OpenAI cost values arrive with enough decimal precision that decoding a JSON number directly as `Decimal` preserves the dashboard total.
2. Which fields are absent, null, or unknown in real ungrouped and model-grouped responses.
3. How both APIs behave when pagination ends early, a later page fails, or the most recent bucket is incomplete.
4. Which timestamp best represents `coverageThrough` and which timestamp can honestly power `last updated` in the UI.

## Local signing prerequisite

The production credential store uses `kSecUseDataProtectionKeychain=true`, `kSecAttrSynchronizable=false`, and `WhenUnlockedThisDeviceOnly`. Apple Development signing and the Keychain access group are configured; the signed app contains `com.apple.application-identifier`, and all 16 Keychain/domain tests pass without skips.

Do not add a legacy Keychain fallback if signing changes later. A missing entitlement must fail visibly rather than silently weakening credential storage.

Apple references:

- https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain
- https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
