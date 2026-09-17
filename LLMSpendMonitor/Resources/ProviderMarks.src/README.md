# Provider marks — source files

The `.svg` files here are the originals the asset catalog is generated from.
They are **not** bundled with the app; only the rendered PNGs in
`../ProviderMarks.xcassets` ship.

## Source

Marks come from [Simple Icons](https://simpleicons.org) (v16.31.0), released
under **CC0-1.0**. The SVG files are free to use; the marks themselves remain
the trademarks of their respective owners. Spender renders them unmodified in
shape, as single-colour templates, only to identify which provider a row
belongs to — it is an independent project, not affiliated with or endorsed by
any of them.

Anthropic's row carries the Claude mark rather than the corporate `A\` glyph: the
console it links to is platform.claude.com and that is the mark users recognise.
The source file `anthropic.svg` therefore holds the `claude` icon.

xAI has no mark in the set, so it keeps its SF Symbol. `ProviderMarkView`
falls back automatically whenever `markAssetName` is nil or the asset is
missing.

## Regenerating

Each mark is a single-path 24x24 glyph. The asset catalog holds `@1x` (18px)
and `@2x` (36px) PNGs whose alpha channel is the inverted luminance of the
rendered glyph, so SwiftUI can tint them as template images.

```bash
# fetch, e.g.
curl -o openai.svg https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/openai.svg

# render at high resolution
magick -background white openai.svg -resize 216x216 /tmp/mark_openai.png
```

Then downscale to 18 and 36 px and set `alpha = 255 - luminance`, writing the
result into `../ProviderMarks.xcassets/mark.<provider>.imageset/` alongside a
`Contents.json` carrying `"template-rendering-intent": "template"`.
