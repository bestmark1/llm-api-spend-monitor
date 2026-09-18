# Security

Spender stores API keys that can read billing data, and some of them are
administrative keys. A flaw that exposes them matters, so please report it
privately.

## Reporting a vulnerability

Use GitHub's private reporting:
**[Report a vulnerability](https://github.com/bestmark1/spender/security/advisories/new)**
(Security tab → Report a vulnerability).

Please do not open a public issue, pull request or discussion about it until a
fix is released.

Include what you can:

- what an attacker could do, and under which conditions;
- steps to reproduce, or a proof of concept;
- the Spender version or commit, and your macOS version.

**Never include a real API key**, yours or anyone else's. If a key has been
exposed, revoke it in the provider's console first.

You will get a reply as soon as possible. Once a fix is out, you will be
credited in the advisory unless you prefer not to be.

## What is in scope

- API keys leaving the macOS Keychain, or being written to logs, caches or
  disk in plain text.
- Requests reaching a host other than the provider's declared HTTPS origin.
- Anything that lets another app or website read what Spender stores.

## Supported versions

Spender has not had a versioned release yet. Fixes land on `main`, and the
latest build is the one supported.
