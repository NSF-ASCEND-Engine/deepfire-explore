# deepfire-explore

Exploration of the [Deepfire](https://docs.deepfire.co/) wildfire intelligence API: satellite hotspots, hotspot clusters (candidate fires), and satellite-derived fire perimeters.

## Setup

1. Create an API client at [app.deepfire.co](https://app.deepfire.co) (Settings -> API clients).
2. Copy `.env.example` to `.env` and fill in the client id and secret. `.env` is gitignored; do not commit credentials or tokens.
3. Instantiate the Julia project:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Usage

```julia
using Deepfire   # src/Deepfire.jl; reads .env, mints and caches the bearer token on first request

fc = Deepfire.items("satellite-perimeters"; bbox = (-125, 32, -114, 42), filter = "active = true")
latest = Deepfire.latest_snapshots(fc)           # one feature per cluster_id
hist = Deepfire.snapshots(latest[1].cluster_id)  # every snapshot of the largest fire, oldest first
Deepfire.queryables("hotspots")                  # filterable attributes
```

Scripts (each writes to `figures/`):

```sh
julia --project=. scripts/plot_perimeters.jl    # California and global perimeters
julia --project=. scripts/colorado_wyoming.jl   # Colorado/Wyoming maps, growth curves, mp4 animations
julia --project=. scripts/coverage.jl           # what the API holds, by region and time
```

## Site

The `.qmd` pages plus `docs/api-notes.md` form a [Quarto](https://quarto.org) website. `quarto preview` serves it locally; `quarto render` writes `_site/`.

`.github/workflows/site.yml` renders the site on every push to `main` and uploads it as the `github-pages` artifact. The deploy job is off because GitHub Pages is not offered for private repos on the org's free plan. To turn it on: enable Pages (Settings, Pages, Source: GitHub Actions) and set the repository variable `DEPLOY_PAGES` to `true`.

## Layout

| Path | Contents |
|---|---|
| `src/Deepfire.jl` | Auth, paging, and `items`/`allitems` query helpers over the OGC API - Features endpoint |
| `scripts/` | One script per exploration; `common.jl` holds shared plotting helpers |
| `figures/` | Rendered output, committed; `figures/animations/` holds mp4 files |
| `*.qmd`, `_quarto.yml` | Website pages |
| `docs/api-notes.md` | Condensed API reference from docs.deepfire.co |
| `data/` | Cached API responses (gitignored) |
