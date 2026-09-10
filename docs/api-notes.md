# Deepfire API notes

Condensed from https://docs.deepfire.co (fetched 2026-09-10). See the docs for the full parameter reference at `/reference`.

## Endpoints

- Token: `POST https://api.deepfire.co/v1/token` with JSON `{client_id, client_secret}` -> `{access_token, expires_in (s, 180 days), token_type}`. No refresh tokens; re-exchange when expired.
- Features: `https://api.deepfire.co/ogc/features/v1` (OGC API - Features). All requests need `Authorization: Bearer <token>`.
- `GET /collections` lists collections. `GET /collections/deepfire:<name>/items` queries. `GET /collections/deepfire:<name>/queryables?f=application/schema+json` lists filterable fields.
- Read-only. CORS open. Also exposes an MCP server for AI clients (`/ai/connect-to-ai`).

## Collections (as of 2026-09-10)

| id | geometry | since | notes |
|---|---|---|---|
| `deepfire:hotspots` | Point | Jan 2025 | Per-satellite detections. `cluster_id`, `observed_at`, `source`, `confidence`, `fire_radiative_power`, `country`, `active` |
| `deepfire:clusters` | Point (centroid) | Jan 2025 | Candidate fires. `first_observed`, `last_observed`, `active` |
| `deepfire:satellite-perimeters` | MultiPolygon | Jun 2026 | Timestamped snapshots per cluster (see below) |
| `deepfire:static-heat-sources` | ? | | Persistent anomaly mask |
| `deepfire:pt-detections` | | | Portugal-specific; undocumented |

Coming soon per docs: fire spread, values at risk, official incidents, ML detections.

Satellites ingested: VIIRS, GOES, Sentinel-3, Himawari, Meteosat, MetOp, MODIS.

## Satellite perimeters

Estimated from hotspot clusters, algorithm `circle-union-v2`. Not surveyed boundaries. A cluster gets a new row whenever its geometry materially changes; older snapshots are kept, so "current perimeter" = latest `computed_at` per `cluster_id`.

| property | type |
|---|---|
| `id` | uuid (feature id `satellite-perimeters.<uuid>`) |
| `cluster_id` | uuid, joins to `deepfire:clusters` |
| `computed_at` | ISO 8601 |
| `observed_watermark` | ISO 8601, nullable; acquisition time of latest hotspot used |
| `n_hotspots` | int |
| `area_m2`, `perimeter_m` | float, nullable |
| `algo_version` | string |
| `active` | bool, whether the owning cluster is active |

## Query parameters

- `f=application/geo+json` (recommended; standard RFC 7946 envelope with `links`). Also `text/csv`, KML, GML, `application/json` (legacy envelope).
- `bbox=minlon,minlat,maxlon,maxlat` (WGS84, lon first).
- `filter=<CQL2 text>` with `filter-lang=cql2-text`. Full CQL2: comparisons, `AND/OR`, `IN`, `LIKE`, spatial ops, `TIMESTAMP('...')`.
- `datetime=` only accepts closed intervals; use CQL on `observed_at` instead.
- `limit` clamped at 10,000. `startIndex` for paging. No `numberMatched`; page until a short page.
- `sortby` is accepted but ignored; sort client-side.

## Limits

- 30 s per query, else HTTP 500 (retryable after narrowing: smaller bbox, time window, `active = true`).
- Shared concurrency cap; excess gets 503 with `Retry-After` and body `{"code":"ogc-busy"}`.
- Responses cached 60 s (`Cache-Control: private, max-age=60`).
- Deep `startIndex` offsets are slow; bulk export by windowing on `observed_at` (indexed) instead.
- 5 API keys per account.

## Observed 2026-09-10

- Active perimeter snapshots in the California bbox (-125,32,-114,42): 270.
- Active perimeter snapshots globally: 64,223 across 4,506 clusters (7 pages of 10,000; a 10,000-feature GeoJSON page is >64 MB decompressed).
- Largest active perimeter: 3,865 km² (Siberia). Largest in the California bbox: 136.5 km² near lon -121.39, lat 35.92 with 123 snapshots over 14 days.
