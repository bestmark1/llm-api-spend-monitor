# Provider marks — source files

The `.svg` files here are the originals the asset catalog is generated from.
They are **not** bundled with the app; only the rendered PNGs in
`../ProviderMarks.xcassets` ship.

## Source

Most marks come from [Simple Icons](https://simpleicons.org) (v16.31.0),
released under **CC0-1.0**. `xai.svg` is not in that set and comes from
[@lobehub/icons-static-svg](https://www.npmjs.com/package/@lobehub/icons-static-svg)
(v1.95.0), released under **MIT**. Both sets are free to use; the marks
themselves remain the trademarks of their respective owners. Spender renders them unmodified in
shape, as single-colour templates, only to identify which provider a row
belongs to — it is an independent project, not affiliated with or endorsed by
any of them.

Anthropic's row carries the Claude mark rather than the corporate `A\` glyph: the
console it links to is platform.claude.com and that is the mark users recognise.
The source file `anthropic.svg` therefore holds the `claude` icon.

Every provider now ships a mark. `ProviderMarkView` still falls back to the
SF Symbol whenever `markAssetName` is nil or the asset is missing, which is
what a provider added without a mark will get.

## Regenerating

Each mark is a single-path 24x24 glyph. The asset catalog holds `@1x` (18px)
and `@2x` (36px) PNGs whose alpha channel is the inverted luminance of the
rendered glyph, so SwiftUI can tint them as template images.

The stored SVG must carry a `viewBox` and **no** `width`/`height`: with an
explicit 24x24 the rasteriser draws a 24px glyph and pads the rest with white,
and the mark comes out almost empty.

```bash
# fetch, e.g.
curl -o openai.svg https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/openai.svg

# render at high resolution
magick -background white openai.svg -resize 216x216 /tmp/mark_openai.png
```

Then downscale to 18 and 36 px and set `alpha = 255 - luminance`, writing the
result into `../ProviderMarks.xcassets/mark.<provider>.imageset/` alongside a
`Contents.json` carrying `"template-rendering-intent": "template"`.
