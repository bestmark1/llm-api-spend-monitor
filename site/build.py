#!/usr/bin/env python3
"""Build site/index.html from the design canvas artboard.

The page and the canvas share one source. `design/Main.dc.html` is authored for
the Claude Design canvas, which imposes three things a real page cannot keep:
a `<x-dc>`/`<helmet>` wrapper, its own `support.js`, and image references as
bare filenames. This script strips those, gives the inline grids class hooks so
media queries can reach them, and adds the responsive layer.

Run it after editing the artboard:

    python3 site/build.py

It rewrites site/index.html in place and prints what it changed.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
ARTBOARD = ROOT / "design" / "Main.dc.html"
OUTPUT = ROOT / "index.html"

SITE_URL = "https://bestmark1.github.io/llm-api-spend-monitor/"
REPO_URL = "https://github.com/bestmark1/llm-api-spend-monitor"

# Inline `grid-template-columns` cannot be overridden by a media query, so each
# grid trades its inline style for a class.
GRID_CLASSES = [
    (
        '<div style="display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px;">',
        '<div class="grid grid-provenance">',
    ),
    (
        '<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 24px; margin-top: 38px;">',
        '<div class="grid grid-compare">',
    ),
    (
        '<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px;">',
        '<div class="grid grid-capability">',
    ),
    (
        '<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 44px;">',
        '<div class="grid grid-principles">',
    ),
]

SCREENSHOTS = ("panel-today-520", "panel-30days-520", "panel-deepseek-expanded-520")

RESPONSIVE = """
    /* --- Grids lifted out of inline styles so media queries can reach them --- */
    .grid { display: grid; }
    .grid-provenance  { grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; }
    .grid-compare     { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 24px; margin-top: 38px; }
    .grid-capability  { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
    .grid-principles  { grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 44px; }

    img { max-width: 100%; }

    /* --- Tablet --- */
    @media (max-width: 900px) {
      .wrap { padding: 0 32px; }
      .row { gap: 44px; }
      .grid-provenance { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .grid-principles { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 32px; }
      h1 { font-size: 46px !important; }
      .cta-band { padding: 40px 36px !important; }
    }

    /* --- Phone: one column throughout, following the Mobile 390 artboard --- */
    @media (max-width: 620px) {
      .wrap { padding: 0 20px; }
      .row { gap: 32px; }
      .grid-provenance,
      .grid-compare,
      .grid-capability,
      .grid-principles { grid-template-columns: minmax(0, 1fr); gap: 16px; }
      h1 { font-size: 34px !important; line-height: 1.08 !important; }
      h2 { font-size: 27px !important; }
      .lede { font-size: 17px; }

      /* The callouts are positioned as a percentage of the screenshot column.
         On a phone that column is narrow enough to push them off the edge. */
      .note { display: none !important; }

      /* The wordmark and the nav links shared one row with space-between. At
         375px "How it works" wrapped to two lines and sat 16px on top of the
         product's own name. On a single-column page the scroll is the
         navigation, so the section links stand down and GitHub — the only one
         that leaves the page — stays. */
      .nav-secondary { display: none; }

      /* These eight marks answer the one question a phone visitor has — is my
         provider here — and they answer it before anything else on the page.
         At 21px they read as speckle. A grid rather than a wrapping flex row:
         left to wrap, eight marks break 7 + 1 and the last one looks dropped. */
      .provider-row {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        justify-items: center;
        gap: 20px 12px;
        margin-top: 30px;
      }
      .provider-mark { width: 30px; height: 30px; opacity: 0.8; }

      /* The requirements line is four items long and lands a few pixels past the
         column, which drops "· MIT" onto a line of its own. A point smaller and
         it fits; the inline font-size is why this needs !important. */
      .meta-line { font-size: 12px !important; letter-spacing: -0.01em; }

      /* The button does not wrap and its label is wider than a phone, so on a
         narrow screen it takes the column instead of widening the page. */
      .btn {
        display: flex;
        width: 100%;
        justify-content: center;
        text-align: center;
        padding: 14px 18px;
      }

      /* 60px of side padding on a 335px column left the closing row no room to
         wrap, and it pushed the page sideways. */
      .cta-band {
        display: block !important;
        padding: 30px 22px !important;
      }
      .cta-band > div { margin-bottom: 22px; }
    }
"""

HEAD = f"""<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Spender — every LLM API bill in one macOS menu bar panel</title>
<meta name="description" content="Spender is a free, open source macOS menu bar app that reads your LLM API spend straight from OpenAI, Anthropic, DeepSeek, xAI and more. Keys stay in the macOS Keychain; there is no account and no server.">
<link rel="icon" href="assets/spender-icon-160.png" type="image/png">
<link rel="canonical" href="{SITE_URL}">

<meta property="og:type" content="website">
<meta property="og:title" content="Spender — every LLM API bill in one macOS menu bar panel">
<meta property="og:description" content="Free and open source. Reads official spend from your providers. Keys stay in the macOS Keychain — no account, no server.">
<meta property="og:image" content="{SITE_URL}assets/screenshots/panel-today.png">
<meta property="og:url" content="{SITE_URL}">
<meta name="twitter:card" content="summary_large_image">"""


def fail(message: str) -> None:
    print(f"build.py: {message}", file=sys.stderr)
    raise SystemExit(1)


def split_artboard(source: str) -> tuple[str, str]:
    """Return (head contents, body contents) from the canvas wrappers."""
    for marker in ("<helmet>", "</helmet>", "</x-dc>"):
        if source.count(marker) != 1:
            fail(f"expected exactly one {marker} in the artboard")

    helmet = source.split("<helmet>", 1)[1].split("</helmet>", 1)[0]
    body = source.split("</helmet>", 1)[1].split("</x-dc>", 1)[0]
    return helmet.strip(), body.strip()


def main() -> None:
    if not ARTBOARD.exists():
        fail(f"artboard not found: {ARTBOARD}")

    helmet, body = split_artboard(ARTBOARD.read_text())

    for old, new in GRID_CLASSES:
        if body.count(old) != 1:
            fail(f"grid markup changed, cannot rewrite: {old[:60]}…")
        body = body.replace(old, new)

    body = body.replace('src="spender-icon-160.png"', 'src="assets/spender-icon-160.png"')
    for shot in SCREENSHOTS:
        body = body.replace(f'src="{shot}.webp"', f'src="assets/screenshots/{shot}.webp"')

    # There is no release to download yet, so the page does not offer one.
    downloads = body.count("Download for Mac")
    if downloads:
        body = body.replace(f'href="{REPO_URL}/releases"', f'href="{REPO_URL}"')
        body = body.replace("Download for Mac", "Watch for the first release")

    if "support.js" in body or "<x-dc" in body:
        fail("canvas machinery leaked into the page body")

    page = (
        "<!doctype html>\n<html lang=\"en\">\n<head>\n"
        f"{HEAD}\n{helmet}\n<style>{RESPONSIVE}</style>\n"
        f"</head>\n<body>\n{body}\n</body>\n</html>\n"
    )
    OUTPUT.write_text(page)
    print(
        f"wrote {OUTPUT.relative_to(ROOT.parent)} — "
        f"{len(page.splitlines())} lines, {len(GRID_CLASSES)} grids classed, "
        f"{downloads} download CTA(s) rewritten"
    )


if __name__ == "__main__":
    main()
