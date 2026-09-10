# Colorado and Wyoming: every satellite perimeter since the collection began (2026-06-16),
# growth curves, and perimeter-growth animations.
#   figures/cowy_perimeters.png            -- latest snapshot per fire
#   figures/cowy_growth_curves.png         -- perimeter area vs time, 8 largest fires
#   figures/cowy_top_fires.md              -- table of the 8 largest fires (included by the site)
#   figures/animations/cowy_region.mp4     -- one frame per day, region-wide
#   figures/animations/cowy_fire_<k>.mp4   -- snapshot-by-snapshot growth, 4 largest fires
using Deepfire, GeoJSON, CairoMakie, GeoMakie, NaturalEarth, Dates
include("common.jl")

const ANIM = joinpath(FIG, "animations")
mkpath(ANIM)
const BBOX = (-111.06, 36.99, -102.04, 45.0)
const PROJ = "+proj=aea +lat_1=38 +lat_2=44 +lon_0=-106.5"
const MP = Makie.GeometryBasics.MultiPolygon{2,Float64}

fc = Deepfire.allitems("satellite-perimeters"; bbox = BBOX)
latest = Deepfire.latest_snapshots(fc)
history = Deepfire.bycluster(fc)
geoms = Dict(cid => basic(h) for (cid, h) in history)
times = Dict(cid => Deepfire.parsetime.(getproperty.(h, :computed_at)) for (cid, h) in history)
firstday = minimum(Date(t[1]) for t in values(times))
active = [f for f in latest if f.active === true]
inactive = [f for f in latest if f.active !== true]
@info "Colorado/Wyoming" snapshots = length(fc) fires = length(latest) active = length(active) firstday

#-----------------------------------------------------------------------------# 1. Regional map
fig = Figure(size = (900, 900))
ga = GeoAxis(fig[1, 1]; dest = PROJ, GRID..., limits = (BBOX[1], BBOX[3], BBOX[2], BBOX[4]),
    title = "Fires with a satellite perimeter since $firstday, Colorado and Wyoming ($(length(latest)) fires, $(length(active)) active)",
    subtitle = "Latest snapshot per fire; numbers rank the 8 largest. Deepfire, $(stamp())")
poly!(ga, GeoMakie.land(50); color = :gray95, strokecolor = :gray60, strokewidth = 0.5)
lines!(ga, statelines(); color = :gray50, linewidth = 0.7)
for (feats, col, edge) in ((inactive, :gray30, :gray20), (active, :red, :darkred))
    polys!(ga, basic(feats); color = (col, 0.8), strokecolor = edge, strokewidth = 0.5)
    c = center.(basic(feats))
    scatter!(ga, first.(c), last.(c); markersize = 3 .+ 1.2 .* sqrt.(km2.(feats)),
        color = :transparent, strokecolor = col, strokewidth = 0.8)
end
for (i, f) in enumerate(first(latest, 8))
    lon, lat = center(geoms[f.cluster_id][end])
    text!(ga, lon, lat; text = string(i), offset = (6, 6), fontsize = 13, font = :bold)
end
Legend(fig[1, 1], [MarkerElement(; marker = :circle, color = :transparent, strokecolor = c, strokewidth = 1.5, markersize = 12) for c in (:red, :gray30)],
    ["active", "inactive"], "cluster status"; tellheight = false, tellwidth = false, halign = :right, valign = :top, margin = (10, 10, 10, 10))
save(joinpath(FIG, "cowy_perimeters.png"), fig; px_per_unit = 2)

#-----------------------------------------------------------------------------# 2. Growth curves and table, 8 largest
top = first(latest, 8)
days(cid) = Dates.value.(times[cid] .- times[cid][1]) ./ 86_400_000
colors = Makie.to_colormap(:tab10)
fig = Figure(size = (1100, 600))
ax = Axis(fig[1, 1]; xlabel = "days since first snapshot", ylabel = "perimeter area (km²)",
    title = "Perimeter growth, 8 largest fires in Colorado and Wyoming since $firstday")
open(joinpath(FIG, "cowy_top_fires.md"), "w") do io
    println(io, "| rank | first snapshot | last snapshot | days | snapshots | hotspots | area (km²) | lon | lat | active |")
    println(io, "|---|---|---|---|---|---|---|---|---|---|")
    for (i, f) in enumerate(top)
        cid = f.cluster_id
        d, a = days(cid), km2.(history[cid])
        lon, lat = center(geoms[cid][end])
        lines!(ax, d, a; color = colors[i], linewidth = 2, label = "$i: $(Date(times[cid][1])), $(km2(f)) km²")
        scatter!(ax, d, a; color = colors[i], markersize = 5)
        println(io, "| $i | $(Date(times[cid][1])) | $(Date(times[cid][end])) | $(round(d[end]; digits=1)) | $(length(d)) | $(f.n_hotspots) | $(km2(f)) | $(round(lon; digits=3)) | $(round(lat; digits=3)) | $(f.active) |")
    end
end
Legend(fig[1, 2], ax)
save(joinpath(FIG, "cowy_growth_curves.png"), fig; px_per_unit = 2)

#-----------------------------------------------------------------------------# 3. Per-fire growth animations, 4 largest
function animate_fire(path, cid, label)
    g, t = geoms[cid], times[cid]
    d, a = days(cid), km2.(history[cid])
    lon, lat = center(g[end])
    ext = extent(g)
    mx, my = 0.15 * (ext[2] - ext[1]), 0.15 * (ext[4] - ext[3])
    k = Observable(1)
    frametitle(i) = "$(Dates.format(t[i], "yyyy-mm-dd HH:MM")) UTC, $(a[i]) km², snapshot $i of $(length(t))"
    fig = Figure(size = (1100, 520))
    ga = GeoAxis(fig[1, 1]; dest = "+proj=laea +lon_0=$lon +lat_0=$lat",
        limits = (ext[1] - mx, ext[2] + mx, ext[3] - my - 0.1 * (ext[4] - ext[3]), ext[4] + my),
        title = @lift(frametitle($k)))
    hidedecorations!(ga)
    poly!(ga, @lift(g[1:$k]); color = (:black, 0.0), strokecolor = (:gray40, 0.6), strokewidth = 0.8)
    poly!(ga, @lift(g[$k]); color = (:red, 0.35), strokecolor = :red, strokewidth = 1.5)
    scalebar!(ga, ext, lat)
    ax = Axis(fig[1, 2]; xlabel = "days since first snapshot", ylabel = "perimeter area (km²)", title = label)
    lines!(ax, d, a; color = :gray40)
    scatter!(ax, @lift(Point2f(d[$k], a[$k])); color = :red, markersize = 12)
    record(fig, path, 1:length(t); framerate = 4) do i
        k[] = i
    end
end
for (i, f) in enumerate(first(latest, 4))
    lon, lat = center(geoms[f.cluster_id][end])
    animate_fire(joinpath(ANIM, "cowy_fire_$i.mp4"), f.cluster_id,
        "Fire $i: lon $(round(lon; digits=2)) lat $(round(lat; digits=2)), $(f.n_hotspots) hotspots")
end

#-----------------------------------------------------------------------------# 4. Region-wide daily animation
"Perimeters as of `day`: (recent, older) where recent = updated within the last 2 days."
function asof(day)
    recent, older = MP[], MP[]
    for (cid, t) in times
        i = findlast(<=(day), Date.(t))
        i === nothing && continue
        push!(Date(t[i]) >= day - Day(2) ? recent : older, geoms[cid][i])
    end
    recent, older
end
title = Observable("")
fig = Figure(size = (1000, 900))
ga = GeoAxis(fig[1, 1]; dest = PROJ, GRID..., limits = (BBOX[1], BBOX[3], BBOX[2], BBOX[4]), title = title,
    subtitle = "red: perimeter updated within 2 days; gray: last known perimeter. Deepfire satellite perimeters")
poly!(ga, GeoMakie.land(50); color = :gray95, strokecolor = :gray60, strokewidth = 0.5)
lines!(ga, statelines(); color = :gray50, linewidth = 0.7)
layers = Makie.AbstractPlot[]
record(fig, joinpath(ANIM, "cowy_region.mp4"), firstday:Day(1):Date(now(UTC)); framerate = 6) do day
    foreach(p -> delete!(ga, p), layers)
    empty!(layers)
    recent, older = asof(day)
    title[] = "$day: $(length(recent) + length(older)) fires with a perimeter, $(length(recent)) updated recently"
    for (gs, col, edge) in ((older, :gray30, :gray20), (recent, :red, :darkred))
        isempty(gs) && continue
        c = center.(gs)
        push!(layers, poly!(ga, gs; color = (col, 0.8), strokecolor = edge, strokewidth = 0.5))
        push!(layers, scatter!(ga, first.(c), last.(c); markersize = 5, color = :transparent, strokecolor = col, strokewidth = 0.8))
    end
end
