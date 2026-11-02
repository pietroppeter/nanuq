## The list of dev-log posts, oldest first. Everything that has to agree across
## posts comes from here: the page title, the dated file name, the eyebrow and meta
## lines, the summary the index shows, previous/next links, related posts and the
## link to the post's source.
##
## Adding a post: append an entry, start the post with
##   nbInit
##   nb.useDevlogPost("my-slug", epigraph = "...")
## and add it to the list in README.md. `docs/index.nim` refuses to build if a
## rendered post is missing from this list, a listed post was not rendered, or the
## README does not link it.

import std/strutils

type
  PostKind* = enum
    Walkthrough = "Walkthrough"
    Research = "Research"
    Explainer = "Explainer"
    ApiDesign = "API design"

  DevlogPost* = object
    slug*: string          ## file name without the date, e.g. "above-4000"
    date*: string          ## yyyy-MM-dd; the page is blog/<date>-<slug>.html
    titleHtml*: string     ## may contain `<em>` for the accented word
    kind*: PostKind
    release*: string       ## the Nanuq release the post is about
    source*: string        ## path of the nimib source, from the repo root
    summary*: string       ## one line, for the index and the description meta tag
    related*: seq[string]  ## slugs; the relation is made symmetric automatically

const devlogPosts*: seq[DevlogPost] = @[
  DevlogPost(slug: "how-nanuq-works", date: "2026-10-27", kind: Walkthrough, release: "0.1",
    titleHtml: "How <em>Nanuq</em> works", source: "docs/blog/how_nanuq_works.nim",
    summary: "How Nanuq wraps Polars for Nim through a small Rust C ABI, with a first tour of the API.",
    related: @["shipping-rust-binaries"]),
  DevlogPost(slug: "plotting-with-ggplotnim", date: "2026-10-27", kind: Walkthrough, release: "0.1",
    titleHtml: "Plotting with <em>ggplotnim</em>", source: "docs/blog/plotting_with_ggplotnim.nim",
    summary: "Plotting a Nanuq DataFrame with ggplotnim, and where a smoother bridge could go.",
    related: @["how-nanuq-works", "counting-el-ninos"]),
  DevlogPost(slug: "shipping-rust-binaries", date: "2026-10-27", kind: Research, release: "0.1",
    titleHtml: "Shipping the <em>Rust</em> half", source: "docs/blog/shipping_rust_binaries.nim",
    summary: "How other Polars bindings ship their Rust half, and the plan for Nanuq's prebuilt libraries."),
  DevlogPost(slug: "bear-census", date: "2026-10-31", kind: Explainer, release: "0.2",
    titleHtml: "The great <em>polar bear</em> census", source: "docs/blog/bear_census.nim",
    summary: "A season of messy ranger logs from Svalbard, cleaned and reported with everything new in Nanuq 0.2.",
    related: @["designing-0-2"]),
  DevlogPost(slug: "designing-0-2", date: "2026-10-31", kind: ApiDesign, release: "0.2",
    titleHtml: "Designing Nanuq <em>0.2</em>", source: "docs/blog/designing_0_2.nim",
    summary: "A look back at the API decisions of Nanuq 0.2: enums, casts, when/then, selectors, CSV options, fillNull and sample.",
    related: @["designing-0-3"]),
  DevlogPost(slug: "designing-0-3", date: "2026-10-31", kind: ApiDesign, release: "0.3",
    titleHtml: "Designing Nanuq <em>0.3</em>", source: "docs/blog/designing_0_3.nim",
    summary: "The API decisions behind Nanuq 0.3: temporal types, the str and dt namespaces, Parquet, errors and categoricals.",
    related: @["aged-19", "designing-0-4"]),
  DevlogPost(slug: "aged-19", date: "2026-11-01", kind: Explainer, release: "0.3",
    titleHtml: "Aged <em>19</em>", source: "docs/blog/aged_19.nim",
    summary: "Paul Seixas's 2026 season and the history of cycling's age and speed records, told with everything new in Nanuq 0.3."),
  DevlogPost(slug: "designing-0-4", date: "2026-11-01", kind: ApiDesign, release: "0.4",
    titleHtml: "Designing Nanuq <em>0.4</em>", source: "docs/blog/designing_0_4.nim",
    summary: "The API decisions behind Nanuq 0.4: math, rolling windows, pivot, time windows, Series, row objects, Arraymancer, and what the explainer and the book ports changed.",
    related: @["counting-el-ninos", "designing-0-5"]),
  DevlogPost(slug: "counting-el-ninos", date: "2026-11-01", kind: Explainer, release: "0.4",
    titleHtml: "Counting <em>El Niños</em>", source: "docs/blog/counting_el_ninos.nim",
    summary: "What El Niño is, how NOAA counts it, and what it does to rain in Peru and " &
             "to the temperature of the planet, told with everything new in Nanuq 0.4.",
    related: @["above-4000"]),
  DevlogPost(slug: "designing-0-5", date: "2026-11-01", kind: ApiDesign, release: "0.5",
    titleHtml: "Designing Nanuq <em>0.5</em>", source: "docs/blog/designing_0_5.nim",
    summary: "The API decisions behind Nanuq 0.5: nested data types, the list, struct and arr namespaces, JSON, SQL, Nim callbacks, and the smaller functions the book asked for.",
    related: @["above-4000", "designing-0-6"]),
  DevlogPost(slug: "above-4000", date: "2026-11-01", kind: Explainer, release: "0.5",
    titleHtml: "Above <em>4000</em>", source: "docs/blog/above_4000.nim",
    summary: "The Alpine four-thousanders, the great hut-to-hut treks around them and the " &
             "world's 8000-metre peaks, told with the lists, structs, JSON, SQL and Nim " &
             "callbacks new in Nanuq 0.5."),
  DevlogPost(slug: "designing-0-6", date: "2026-11-01", kind: ApiDesign, release: "0.6",
    titleHtml: "Designing Nanuq <em>0.6</em>", source: "docs/blog/designing_0_6.nim",
    summary: "The API decisions behind Nanuq 0.6: streaming and sinks, plan serialization, Binary and Decimal, the Arrow C Data Interface, Excel, SQLite, testing helpers, the py-polars 2.1 pin, cloud storage, thirty functions from the coverage map, and what the book still asked for.",
    related: @["how-nanuq-works", "plotting-with-ggplotnim"]),
  DevlogPost(slug: "move-37", date: "2026-11-02", kind: Explainer, release: "0.6",
    titleHtml: "Move <em>37</em>", source: "docs/blog/move_37.nim",
    summary: "Ninety-eight thousand professional games, 2.8 million amateur ones and the " &
             "champions of Italian go, told with the streaming, sinks, Decimal, Binary, " &
             "bitwise, serialization, database and Excel features new in Nanuq 0.6.",
    related: @["designing-0-6"]),
]

const
  repoUrl* = "https://github.com/pietroppeter/nanuq"
  sourceUrl* = repoUrl & "/blob/main/"

func fileName*(p: DevlogPost): string = p.date & "-" & p.slug & ".html"

func plainTitle*(p: DevlogPost): string =
  p.titleHtml.multiReplace(("<em>", ""), ("</em>", ""))

func findPost*(slug: string): int =
  for i, p in devlogPosts:
    if p.slug == slug: return i
  -1

func relatedTo*(slug: string): seq[int] =
  ## Posts related to `slug` in either direction, in dev-log order.
  let me = findPost(slug)
  for i, p in devlogPosts:
    if i != me and (p.slug in devlogPosts[me].related or slug in p.related):
      result.add i

static:
  for i, p in devlogPosts:
    doAssert findPost(p.slug) == i, "devlog: duplicate slug " & p.slug
    for r in p.related:
      doAssert findPost(r) >= 0, "devlog: " & p.slug & " is related to unknown post " & r
    if i > 0: doAssert devlogPosts[i - 1].date <= p.date, "devlog: posts must be oldest first"
