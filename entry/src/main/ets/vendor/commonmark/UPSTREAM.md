# CommonMark parser used by explicit Markdown long posts

- Upstream: https://github.com/commonmark/commonmark.js
- Version: `commonmark@0.31.2` (BSD-2-Clause; upstream source header names BSD3, but the distributed LICENSE has two conditions), installed from its npm package.
- Tarball: https://registry.npmjs.org/commonmark/-/commonmark-0.31.2.tgz
- Dependencies included by the parser-only bundle: `entities@3.0.1` (BSD-2-Clause) and `mdurl@1.0.1` (MIT). Adjacent files retain their full licenses.
- No HTML renderer, CLI/minimist, eval, remote loading or HTML execution is used.
- The emitted `commonmark.js` is an ES module generated with `esbuild@0.25.12`, `--bundle --format=esm --target=es2017 --minify --legal-comments=inline --sourcemap=external` from `commonmark/lib/blocks.js` plus the small inline helper described below.

Local source adaptations before bundling:

1. In `lib/blocks.js` `processInlines`, retain `node.markdownSource = node._string_content` immediately before `inlineParser.parse(node)`. Only paragraph/heading leaf source is retained, so GFM table/task adapters do not copy whole ancestor documents or guess source columns inside lists/quotes.
2. `lib/inlines.js` adds `~` and `|` delimiter kinds to the existing delimiter stack (minimum run length two), their own opener lower-bound slots, and emits `strikethrough` / `spoiler` container nodes. Escapes/code spans use unchanged upstream rules. No nested regex parser is added.
3. `lib/node.js` recognizes those two new kinds as containers, keeping the existing iterative node walker correct.
4. The ESM entry exports the default Parser and `inlineMarkdown(parser, source)`, which creates a paragraph and asks that parser's inline engine to parse it using the same reference definition map. GFM table cells therefore retain references without reparsing the whole document for every cell.

Markdown tables/task lists and TDLib input object conversion live in `util/markdownRichInput.ets`, outside the vendor parser. Containers and inline traversal use explicit stacks; effective repeated inline styles use fixed counters rather than copied ancestor subtrees.

The parser never turns raw HTML into an executable Web surface. HTML is preserved as literal text. Remote Markdown images require the explicit send-time media resolver; neither remote URLs nor unfinished media placeholders are disguised as TDLib file IDs. Input `richTextIcon` is forbidden by TDLib, so images inside native table cells retain a link and their actual uploaded media immediately after the table.

The npm integrity and generated-file SHA256 values are recorded in the adjacent `provenance.json`. Source/schema evidence and focused host fixtures are retained in `build/checklist-markdown-20261119/` for this development run.

The external source map keeps source content and normalizes source paths to `upstream/` / `petrel-commonmark-entry.js`; it does not publish a developer filesystem path.
