# Satellite perimeters from Deepfire:
#   1. figures/active_perimeters_california.png  -- latest snapshot per active fire, California bbox
#   2. figures/perimeter_growth_california.png   -- snapshot history of the 6 largest active fires in that bbox
#   3. figures/active_perimeters_global.png      -- every active fire, marker area ~ perimeter area
using Deepfire, GeoJSON, CairoMakie, GeoMakie, NaturalEarth, Dates
using GeoMakie.GeoInterface

const FIG = normpath(joinpath(@__DIR__, "..", "figures"))
mkpath(FIG)

basic(feats) = [GeoMakie.geo2basic(f.geometry) for f in feats if !ismissing(f.geometry)]
center(g) = (ext = GeoInterface.extent(g); (sum(ext.X) / 2, sum(ext.Y) / 2))
km2(f) = round(something(f.area_m2, 0.0) / 1e6; digits = 1)
stamp = Dates.format(now(UTC), "yyyy-mm-dd HH:MM") * " UTC"
grid = (xgridcolor = (:black, 0.1), ygridcolor = (:black, 0.1))

#-----------------------------------------------------------------------------# 1. California, latest snapshot per fire
bbox = (-125, 32, -114, 42)
fc = Deepfire.items("satellite-perimeters"; bbox, filter = "active = true")
latest = Deepfire.latest_snapshots(fc)
@info "California bbox" snapshots = length(fc) fires = length(latest)

states = naturalearth("admin_1_states_provinces_lines", 10)

fig = Figure(size = (800, 900))
ga = GeoAxis(fig[1, 1]; dest = "+proj=aea +lat_1=34 +lat_2=40.5 +lon_0=-120", grid...,
    limits = (bbox[1], bbox[3], bbox[2], bbox[4]),
    title = "Active satellite perimeters, latest snapshot per fire ($(length(latest)) fires)",
    subtitle = "Deepfire deepfire:satellite-perimeters, $stamp")
poly!(ga, GeoMakie.land(50); color = :gray95, strokecolor = :gray60, strokewidth = 0.5)
lines!(ga, GeoMakie.to_multilinestring.(basic(states)); color = :gray60, linewidth = 0.5)
poly!(ga, basic(latest); color = (:red, 0.8), strokecolor = :darkred, strokewidth = 0.5)
scatter!(ga, first.(center.(basic(latest))), last.(center.(basic(latest)));
    markersize = 4 .+ 2 .* sqrt.(km2.(latest)), color = :transparent, strokecolor = :red, strokewidth = 0.8)
save(joinpath(FIG, "active_perimeters_california.png"), fig; px_per_unit = 2)

#-----------------------------------------------------------------------------# 2. Growth history, 6 largest fires
top = first(latest, 6)
fig = Figure(size = (1200, 800))
for (i, f) in enumerate(top)
    hist = Deepfire.snapshots(f.cluster_id)
    geoms = basic(hist)
    lon, lat = center(geoms[end])
    t = [Deepfire.parsetime(h.computed_at) for h in hist]
    days = Dates.value.(t .- t[1]) ./ 86_400_000
    ax = GeoAxis(fig[fldmod1(i, 3)...]; dest = "+proj=laea +lon_0=$lon +lat_0=$lat",
        title = "$(km2(f)) km², $(length(hist)) snapshots over $(round(days[end]; digits=1)) d, $(f.n_hotspots) hotspots",
        subtitle = "$(Date(t[1])) to $(Date(t[end])), lon $(round(lon; digits=2)) lat $(round(lat; digits=2))",
        titlesize = 13, subtitlesize = 11)
    hidedecorations!(ax)
    for (g, d) in zip(geoms, days)
        poly!(ax, g; color = (:black, 0.0), strokecolor = get(cgrad(:viridis), d / max(days[end], 1)), strokewidth = 1.2)
    end
    poly!(ax, geoms[end]; color = (:red, 0.15), strokecolor = :red, strokewidth = 1.5)
    # scale bar along the parallel, below the lower-left corner of the union of snapshots
    exts = GeoInterface.extent.(geoms)
    x0, x1 = extrema(e.X[1] for e in exts)[1], maximum(e.X[2] for e in exts)
    y0, y1 = minimum(e.Y[1] for e in exts), maximum(e.Y[2] for e in exts)
    kmperdeg = 111.32 * cosd(lat)
    L = first(l for l in (0.5, 1, 2, 5, 10, 20, 50) if l >= (x1 - x0) * kmperdeg / 4)
    yb = y0 - 0.08 * (y1 - y0)
    lines!(ax, [x0, x0 + L / kmperdeg], [yb, yb]; color = :black, linewidth = 2)
    text!(ax, x0 + L / kmperdeg / 2, yb; text = "$L km", align = (:center, :top), fontsize = 11)
end
Colorbar(fig[:, 4]; colormap = :viridis, limits = (0, 1), label = "fraction of elapsed time since first snapshot")
Label(fig[0, :], "Perimeter snapshot history, largest active fires in California bbox ($stamp)"; fontsize = 16)
save(joinpath(FIG, "perimeter_growth_california.png"), fig; px_per_unit = 2)

#-----------------------------------------------------------------------------# 3. Global overview
fcg = Deepfire.allitems("satellite-perimeters"; filter = "active = true")
latestg = Deepfire.latest_snapshots(fcg)
@info "Global" snapshots = length(fcg) fires = length(latestg)
cg = center.(basic(latestg))

fig = Figure(size = (1400, 750))
ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth", grid...,
    title = "Active fires with a satellite perimeter ($(length(latestg)) fires)", subtitle = "Deepfire, $stamp")
poly!(ga, GeoMakie.land(); color = :gray95, strokecolor = :gray60, strokewidth = 0.3)
msize(a) = 1.5 + 0.6 * sqrt(a)
scatter!(ga, first.(cg), last.(cg); markersize = msize.(km2.(latestg)),
    color = (:red, 0.5), strokecolor = :darkred, strokewidth = 0.3)
areas = [1, 10, 100, 1000]
Legend(fig[1, 2], [MarkerElement(; marker = :circle, color = (:red, 0.5), strokecolor = :darkred, markersize = msize(a)) for a in areas],
    ["$a km²" for a in areas], "latest perimeter area")
save(joinpath(FIG, "active_perimeters_global.png"), fig; px_per_unit = 2)
