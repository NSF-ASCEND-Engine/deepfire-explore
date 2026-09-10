module Deepfire

using HTTP, JSON3, GeoJSON, Dates

const BASE = "https://api.deepfire.co"
const FEATURES = BASE * "/ogc/features/v1"
const COLLECTIONS = ("hotspots", "clusters", "satellite-perimeters", "static-heat-sources")

#-----------------------------------------------------------------------------# credentials
"Load `KEY=VALUE` lines from a `.env` file into `ENV`. Existing ENV entries win."
function loadenv!(path = normpath(joinpath(@__DIR__, "..", ".env")))
    isfile(path) || return nothing
    for line in eachline(path)
        line = strip(line)
        (isempty(line) || startswith(line, '#')) && continue
        k, v = split(line, '='; limit = 2)
        haskey(ENV, k) || (ENV[k] = strip(v))
    end
end

const _token = Ref(("", DateTime(0)))

"Bearer token minted from `DEEPFIRE_CLIENT_ID` / `DEEPFIRE_CLIENT_SECRET`, cached until it expires."
function token()
    tok, expiry = _token[]
    now(UTC) < expiry && return tok
    loadenv!()
    body = JSON3.write((client_id = ENV["DEEPFIRE_CLIENT_ID"], client_secret = ENV["DEEPFIRE_CLIENT_SECRET"]))
    r = HTTP.post(BASE * "/v1/token", ["Content-Type" => "application/json"], body)
    j = JSON3.read(r.body)
    _token[] = (String(j.access_token), now(UTC) + Second(j.expires_in) - Minute(5))
    return _token[][1]
end

headers() = ["Authorization" => "Bearer " * token()]

#-----------------------------------------------------------------------------# queries
"""
    items(collection; bbox, filter, limit=10_000, startindex=0, kw...)

One page of `deepfire:<collection>` features as a `GeoJSON.FeatureCollection`.

- `bbox`: `(minlon, minlat, maxlon, maxlat)` in WGS84.
- `filter`: CQL2 text, e.g. `"active = true AND n_hotspots > 10"`.
- `limit` is clamped server-side at 10,000.
"""
function items(collection; bbox = nothing, filter = nothing, limit = 10_000, startindex = 0, kw...)
    q = Dict{String,String}("f" => "application/geo+json", "limit" => string(limit), "startIndex" => string(startindex))
    bbox === nothing || (q["bbox"] = join(bbox, ','))
    if filter !== nothing
        q["filter-lang"] = "cql2-text"
        q["filter"] = filter
    end
    for (k, v) in kw
        q[string(k)] = string(v)
    end
    r = HTTP.get("$FEATURES/collections/deepfire:$collection/items", headers(); query = q, max_decompressed_size = 0)
    GeoJSON.read(r.body; numbertype = Float64)
end

"Every feature matching the query. Pages by `startIndex` until a short page (the API returns no total count)."
function allitems(collection; limit = 10_000, kw...)
    feats = GeoJSON.Feature{2,Float64}[]
    startindex = 0
    while true
        page = items(collection; limit, startindex, kw...)
        append!(feats, page)
        length(page) < limit && break
        startindex += limit
    end
    GeoJSON.FeatureCollection(; features = feats)
end

"One feature by id, e.g. `feature(\"clusters\", cluster_id)`."
function feature(collection, id)
    r = HTTP.get("$FEATURES/collections/deepfire:$collection/items/$collection.$id", headers(); query = Dict("f" => "application/geo+json"))
    GeoJSON.read(r.body; numbertype = Float64)
end

"Queryable (filterable) attributes of a collection, as the JSON Schema the API publishes."
function queryables(collection)
    r = HTTP.get("$FEATURES/collections/deepfire:$collection/queryables", headers(); query = Dict("f" => "application/schema+json"))
    JSON3.read(r.body)
end

#-----------------------------------------------------------------------------# perimeters
parsetime(s) = DateTime(first(s, 19))  # ISO 8601 with optional fractional seconds and Z

"Most recent perimeter snapshot per `cluster_id`."
function latest_snapshots(fc)
    best = Dict{String,eltype(fc)}()
    for f in fc
        t = parsetime(f.computed_at)
        cur = get(best, f.cluster_id, nothing)
        (cur === nothing || t > parsetime(cur.computed_at)) && (best[f.cluster_id] = f)
    end
    sort!(collect(values(best)); by = f -> -something(f.area_m2, 0.0))
end

"Snapshots grouped by `cluster_id`, each sorted oldest first."
function bycluster(fc)
    d = Dict{String,Vector{eltype(fc)}}()
    for f in fc
        push!(get!(d, f.cluster_id, eltype(fc)[]), f)
    end
    foreach(v -> sort!(v; by = f -> parsetime(f.computed_at)), values(d))
    d
end

"All perimeter snapshots for one cluster, oldest first."
function snapshots(cluster_id)
    fc = allitems("satellite-perimeters"; filter = "cluster_id = '$cluster_id'")
    sort(collect(fc); by = f -> parsetime(f.computed_at))
end

end
