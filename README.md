# Spender

Spender is a native macOS menu bar app that brings LLM API spend, token usage, and balances into one compact dashboard.

It connects directly to provider APIs, keeps credentials in macOS Keychain, and stores cached metrics locally. There is no Spender account, backend, or credential proxy.

> **Status:** early personal-use release. Provider billing APIs differ significantly, so the metrics available for each connection are intentionally explicit.

## What it does

- Shows today, yesterday, and 30-day spend in a menu bar panel.
- Combines supported USD reports into a provider breakdown and daily trend.
- Displays official balances where a provider exposes them.
- Tracks DeepSeek spend locally from balance decreases and clearly labels it as estimated.
- Shows token and model usage when the provider has an official reporting API.
- Lets you reorder and hide providers without removing saved credentials.
- Refreshes in the background, retains the last good snapshot, and supports launch at login.

## Supported providers

| Provider | Connection | Metrics in Spender |
| --- | --- | --- |
| OpenAI | Organization Admin API key | Official cost, tokens, and models |
| Anthropic | Console Admin API key | Official cost, tokens, and models |
| DeepSeek | Standard API key | Official balance; estimated daily spend from saved balance decreases |
| Kimi | Standard API key and matching API host | Official balance |
| Qwen / Alibaba Cloud | Model Studio API key; optional read-only BSS AccessKey credentials | Key validation; official Alibaba Cloud balance and Qwen billing when BSS is configured |
| xAI / Grok | Team-scoped Management API key | Official prepaid balance, usage, and model breakdown |
| Mistral AI | Enterprise Admin API key | Official remaining monthly spending limit |
| OpenRouter | Management API key | Official remaining credits |

Gemini and Perplexity are currently hidden because their ordinary API keys do not provide a practical account-wide spend report for this app. Spender does not present key validation as billing integration.

### DeepSeek accuracy

DeepSeek's public API returns the current balance but not historical cost buckets. Spender therefore compares consecutive saved balance observations:

- a decrease is recorded as estimated spend on the day of the newer observation;
- an increase is treated as a top-up and is not counted as negative spend;
- the estimate starts after Spender has saved its first balance observation;
- usage between widely separated observations, grant expiry, or an intervening top-up can make the estimate differ from DeepSeek's Usage export.

For authoritative history, use the CSV export on the DeepSeek Usage page.

## Privacy and security

- API keys and administrative secrets are stored in macOS Keychain.
- Provider requests are restricted to declared HTTPS origins.
- Cached snapshots and preferences remain in the user's local Application Support and UserDefaults data.
- The repository contains no telemetry backend and no shared credential service.

Use the narrowest read-only administrative credential each provider supports. Do not reuse inference keys outside their intended provider.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- A personal Apple Development team selected under **Signing & Capabilities** for a signed local install

## Build and run

1. Clone the repository:

   ```bash
   git clone https://github.com/bestmark1/llm-api-spend-monitor.git
   cd llm-api-spend-monitor
   ```

2. Open `LLMSpendMonitor.xcodeproj` in Xcode.
3. Select the **LLMSpendMonitor** scheme and **My Mac** destination.
4. Choose your Development Team in **Signing & Capabilities**.
5. Press **Run**.

To build and install a signed Release copy in `/Applications/Spender.app`:

```bash
./scripts/install-local.zsh
```

The installer builds from the current checkout, replaces only `/Applications/Spender.app`, verifies its code signature, and launches it. Enable **Options → Settings → Launch at Login** if desired.

## Tests

Run the unit test suite from the command line:

```bash
xcodebuild test \
  -project LLMSpendMonitor.xcodeproj \
  -scheme LLMSpendMonitor \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

UI tests require macOS Accessibility permission for the Xcode test runner.

## Project structure

```text
LLMSpendMonitor/
├── App/              app and menu bar lifecycle
├── Domain/           money, metrics, and provider snapshots
├── Features/         dashboard, connections, and customization state
├── Infrastructure/   networking, Keychain, and local persistence
├── Providers/        provider-specific API clients
├── Services/         refresh, aggregation, and notifications
└── UI/               SwiftUI menu bar interface
```

Provider API notes and contract validation material live in [`docs/research`](docs/research).
