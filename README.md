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

Scripts:

```sh
julia --project=. scripts/plot_perimeters.jl   # writes figures/*.png
```

## Layout

| Path | Contents |
|---|---|
| `src/Deepfire.jl` | Auth, paging, and `items`/`allitems` query helpers over the OGC API - Features endpoint |
| `scripts/` | One script per exploration; each writes to `figures/` |
| `figures/` | Rendered output (committed) |
| `docs/api-notes.md` | Condensed API reference from docs.deepfire.co |
| `data/` | Cached API responses (gitignored) |
