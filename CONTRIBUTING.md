# Contributing to Spender

Thanks for wanting to help. Spender is a small app with a narrow job: show
what your LLM API providers themselves report you have spent and have left.
Changes that keep it small, honest and fast are the ones that land.

## Start with an issue

Open an issue before you write code, and say what you want to change and why.
A short discussion first saves you from building something that will not be
merged. Typos and obvious one-line fixes can go straight to a pull request.

Found a security problem? Do not open an issue — see [SECURITY.md](SECURITY.md).

## What fits

- Bug fixes, with the cause explained.
- A new provider, if it has a **documented, public API** for spend or balance
  that an ordinary account can use. Spender does not call undocumented or
  internal endpoints; the README explains
  [why some providers are missing](README.md#why-some-providers-are-not-here).
- Accessibility, performance and documentation improvements.

What does not fit: features beyond spend and balance tracking, telemetry or
any server, and anything that shows an estimate as if it were an official
figure.

## Rules the code keeps

- **Missing is not zero.** A value a provider did not report stays empty; it
  is never shown as `$0`.
- **Official and estimated stay apart.** An estimate is labelled as one.
- **Secrets stay in the Keychain.** Never log, print or commit an API key —
  including in tests, screenshots and issue text. Tests use made-up fixtures.
- **Requests go only to the provider's declared HTTPS hosts.**

## Pull requests

1. One change per pull request.
2. Run the tests from [README — Tests](README.md#tests) and say in the pull
   request what you ran and what passed.
3. For anything visible, attach before and after screenshots — of the app
   window only, with demo data rather than your real accounts
   (`--demo-data --dashboard-preview`).
4. Keep to the existing style: match the code around your change.

## License

By opening a pull request you agree that your contribution is released under
the [MIT License](LICENSE) that covers this project.
