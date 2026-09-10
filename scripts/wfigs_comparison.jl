# Deepfire satellite perimeters against WFIGS (Wildland Fire Interagency Geospatial Services)
# official perimeters. Colorado and Wyoming, fires discovered since 2026-06-01.
#   figures/wfigs_detection.md      -- share of WFIGS fires that have a Deepfire perimeter, by size class
#   figures/wfigs_comparison.md     -- per-fire metrics, WFIGS fires >= 1000 acres
#   figures/wfigs_overlays.png      -- WFIGS and Deepfire perimeters, 8 largest WFIGS fires
#   figures/wfigs_area_scatter.png  -- Deepfire area against WFIGS area, all matched fires
using Deepfire, GeoJSON, CairoMakie, GeoMakie, NaturalEarth, Dates, HTTP, LibGEOS
include("common.jl")

const BBOX = (-111.06, 36.99, -102.04, 45.0)
const WFIGS = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters_YearToDate/FeatureServer/0/query"
const ACRE_KM2 = 0.00404686

#-----------------------------------------------------------------------------# data
function wfigs_perimeters()
    q = Dict(
        "where" => "attr_POOState IN ('US-CO','US-WY') AND attr_FireDiscoveryDateTime >= TIMESTAMP '2026-06-01 00:00:00'",
        "outFields" => "attr_IncidentName,attr_FireDiscoveryDateTime,attr_POOState,attr_POOCounty,poly_GISAcres,attr_UniqueFireIdentifier,poly_PolygonDateTime,attr_FireOutDateTime,poly_MapMethod",
        "returnGeometry" => "true", "outSR" => "4326", "f" => "geojson")
    fc = GeoJSON.read(HTTP.get(WFIGS; query = q).body; numbertype = Float64)
    length(fc) < 1000 || error("WFIGS page limit reached; page the query")
    fc
end
num(x) = x isa Number ? Float64(x) : NaN
epoch(ms) = ms isa Number ? unix2datetime(ms / 1000) : missing
hours(a, b) = (ismissing(a) || ismissing(b)) ? NaN : Dates.value(a - b) / 3_600_000

# LibGEOS geometry from any GeoInterface polygon/multipolygon; buffer(0) repairs self-intersections
deep(x::Tuple) = collect(Float64, x)
deep(x::AbstractVector{<:Real}) = collect(Float64, x)
deep(x) = map(deep, x)
function geos(g)
    c = deep(GeoInterface.coordinates(g))
    p = GeoInterface.geomtrait(g) isa GeoInterface.PolygonTrait ? LibGEOS.Polygon(c) : LibGEOS.MultiPolygon(c)
    LibGEOS.buffer(p, 0.0)
end
"Area of a lon/lat geometry in km², using the local scale at latitude `lat`."
area_km2(g, lat) = LibGEOS.area(g) * 111.32^2 * cosd(lat)

wf = wfigs_perimeters()
wfg = geos.(getproperty.(wf, :geometry))
fc = Deepfire.allitems("satellite-perimeters"; bbox = BBOX)
latest = Deepfire.latest_snapshots(fc)
dfg = geos.(getproperty.(latest, :geometry))
history = Deepfire.bycluster(fc)
@info "inputs" wfigs = length(wf) deepfire_fires = length(latest)

#-----------------------------------------------------------------------------# match each WFIGS fire to overlapping Deepfire perimeters
struct Match
    wi::Int                   # index into `wf`
    name::String; state::String; acres::Float64; discovered; polydate; method
    lon::Float64; lat::Float64
    idx::Vector{Int}          # indices into `latest`
    wf_km2::Float64; df_km2::Float64; inter_km2::Float64; union_km2::Float64
    first_hotspot; first_perimeter
end
firstobserved(cid) = Deepfire.parsetime(Deepfire.feature("clusters", cid).first_observed)
matches = Match[]
for (i, f) in enumerate(wf)
    lon, lat = center(GeoMakie.geo2basic(f.geometry))
    idx = [j for j in eachindex(latest) if LibGEOS.intersects(wfg[i], dfg[j])]
    if isempty(idx)
        wa = area_km2(wfg[i], lat)
        push!(matches, Match(i, string(f.attr_IncidentName), string(f.attr_POOState), num(f.poly_GISAcres), epoch(f.attr_FireDiscoveryDateTime),
            epoch(f.poly_PolygonDateTime), f.poly_MapMethod, lon, lat, idx, wa, 0.0, 0.0, wa, missing, missing))
        continue
    end
    dfu = reduce(LibGEOS.union, dfg[idx])
    inter = LibGEOS.intersection(wfg[i], dfu)
    cids = [latest[j].cluster_id for j in idx]
    push!(matches, Match(i, string(f.attr_IncidentName), string(f.attr_POOState), num(f.poly_GISAcres), epoch(f.attr_FireDiscoveryDateTime),
        epoch(f.poly_PolygonDateTime), f.poly_MapMethod, lon, lat, idx,
        area_km2(wfg[i], lat), area_km2(dfu, lat), area_km2(inter, lat), area_km2(LibGEOS.union(wfg[i], dfu), lat),
        minimum(firstobserved.(cids)), minimum(Deepfire.parsetime(history[c][1].computed_at) for c in cids)))
end
sort!(matches; by = m -> -m.acres)
matched(m) = !isempty(m.idx)
iou(m) = m.inter_km2 / m.union_km2
@info "matched" n = count(matched, matches) of = length(matches)

#-----------------------------------------------------------------------------# detection rate by size class
bins = [(0, 100), (100, 1000), (1000, 10_000), (10_000, Inf)]
open(joinpath(FIG, "wfigs_detection.md"), "w") do io
    println(io, "| WFIGS perimeter size (acres) | WFIGS fires | with a Deepfire perimeter | share | median IoU of matched |")
    println(io, "|---|---|---|---|---|")
    for (lo, hi) in bins
        ms = [m for m in matches if lo <= m.acres < hi]
        mm = filter(matched, ms)
        med = isempty(mm) ? NaN : sort(iou.(mm))[(length(mm) + 1) ÷ 2]
        println(io, "| $(lo) to $(hi == Inf ? "" : hi) | $(length(ms)) | $(length(mm)) | $(isempty(ms) ? "" : round(Int, 100 * length(mm) / length(ms)))% | $(isnan(med) ? "" : round(med; digits=2)) |")
    end
    println(io, "\nWFIGS fires in Colorado and Wyoming discovered since 2026-06-01 with a mapped perimeter; checked $(stamp()).")
end

#-----------------------------------------------------------------------------# per-fire table, >= 1000 acres
fmt(x; d = 1) = isnan(x) ? "" : string(round(x; digits = d))
fmtd(t) = ismissing(t) ? "" : Dates.format(t, "yyyy-mm-dd")
open(joinpath(FIG, "wfigs_comparison.md"), "w") do io
    println(io, "| fire | state | discovered | WFIGS km² (poly date) | Deepfire km² | clusters | IoU | recall | precision | first hotspot (h) | first perimeter (h) |")
    println(io, "|---|---|---|---|---|---|---|---|---|---|---|")
    for m in matches
        m.acres >= 1000 || continue
        wfcol = "$(fmt(m.acres * ACRE_KM2)) ($(fmtd(m.polydate)))"
        if matched(m)
            println(io, "| $(m.name) | $(m.state[4:end]) | $(fmtd(m.discovered)) | $wfcol | $(fmt(m.df_km2)) | $(length(m.idx)) | $(fmt(iou(m); d=2)) | $(fmt(m.inter_km2 / m.wf_km2; d=2)) | $(fmt(m.inter_km2 / m.df_km2; d=2)) | $(fmt(hours(m.first_hotspot, m.discovered))) | $(fmt(hours(m.first_perimeter, m.discovered))) |")
        else
            println(io, "| $(m.name) | $(m.state[4:end]) | $(fmtd(m.discovered)) | $wfcol | none | 0 | | | | | |")
        end
    end
    println(io, "\nIoU = intersection over union of the WFIGS polygon and the union of overlapping Deepfire perimeters (latest snapshot per cluster). Recall = intersection / WFIGS area. Precision = intersection / Deepfire area. Hours are measured from the WFIGS discovery time to the first hotspot in the matched clusters and to the first perimeter snapshot. Areas from geometry in an equal-area approximation; WFIGS acres converted at 0.004047 km² per acre.")
end
println(read(joinpath(FIG, "wfigs_comparison.md"), String))

#-----------------------------------------------------------------------------# overlays, 8 largest WFIGS fires
top = first(matches, 8)
fig = Figure(size = (1400, 800))
for (i, m) in enumerate(top)
    wfpoly = GeoMakie.geo2basic(wf[m.wi].geometry)
    dfpolys = [GeoMakie.geo2basic(latest[j].geometry) for j in m.idx]
    ext = extent([wfpoly; dfpolys])
    ax = GeoAxis(fig[fldmod1(i, 4)...]; dest = "+proj=laea +lon_0=$(m.lon) +lat_0=$(m.lat)",
        title = "$(m.name) ($(m.state[4:end])): WFIGS $(fmt(m.acres * ACRE_KM2)) km², Deepfire $(fmt(m.df_km2)) km²",
        subtitle = matched(m) ? "IoU $(fmt(iou(m); d=2)), recall $(fmt(m.inter_km2 / m.wf_km2; d=2)), precision $(fmt(m.inter_km2 / m.df_km2; d=2)), $(length(m.idx)) cluster$(length(m.idx) == 1 ? "" : "s")" : "no Deepfire perimeter",
        titlesize = 12, subtitlesize = 11)
    hidedecorations!(ax)
    polys!(ax, dfpolys; color = (:red, 0.25), strokecolor = :red, strokewidth = 1.2)
    poly!(ax, wfpoly; color = (:black, 0.0), strokecolor = :black, strokewidth = 1.5)
    scalebar!(ax, ext, m.lat)
end
Legend(fig[0, :], [PolyElement(; color = (:black, 0.0), strokecolor = :black, strokewidth = 1.5), PolyElement(; color = (:red, 0.25), strokecolor = :red, strokewidth = 1.2)],
    ["WFIGS perimeter (latest)", "Deepfire perimeter (latest snapshot per cluster)"]; orientation = :horizontal, framevisible = false)
save(joinpath(FIG, "wfigs_overlays.png"), fig; px_per_unit = 2)

#-----------------------------------------------------------------------------# area scatter, all matched fires
mm = filter(matched, matches)
fig = Figure(size = (800, 650))
ax = Axis(fig[1, 1]; xscale = log10, yscale = log10, xlabel = "WFIGS perimeter area (km²)", ylabel = "Deepfire perimeter area (km²)",
    title = "Deepfire against WFIGS, $(length(mm)) matched fires in Colorado and Wyoming")
lo, hi = 0.01, 1.2 * maximum(max(m.wf_km2, m.df_km2) for m in mm)
lines!(ax, [lo, hi], [lo, hi]; color = :gray50, linestyle = :dash, label = "1:1")
scatter!(ax, [m.wf_km2 for m in mm], [m.df_km2 for m in mm]; color = iou.(mm), colormap = :viridis, colorrange = (0, 1), markersize = 10, strokecolor = :black, strokewidth = 0.5)
for m in first(mm, 8)
    text!(ax, m.wf_km2, m.df_km2; text = m.name, offset = (6, 4), fontsize = 10)
end
xlims!(ax, nothing, 4hi)
Colorbar(fig[1, 2]; colormap = :viridis, limits = (0, 1), label = "IoU")
save(joinpath(FIG, "wfigs_area_scatter.png"), fig; px_per_unit = 2)
