# Satellite perimeters from Deepfire:
#   1. figures/active_perimeters_california.png  -- latest snapshot per active fire, California bbox
#   2. figures/perimeter_growth_california.png   -- snapshot history of the 6 largest active fires in that bbox
#   3. figures/active_perimeters_global.png      -- every active fire, marker area ~ perimeter area
using Deepfire, GeoJSON, CairoMakie, GeoMakie, NaturalEarth, Dates
include("common.jl")

#-----------------------------------------------------------------------------# 1. California, latest snapshot per fire
bbox = (-125, 32, -114, 42)
fc = Deepfire.items("satellite-perimeters"; bbox, filter = "active = true")
latest = Deepfire.latest_snapshots(fc)
@info "California bbox" snapshots = length(fc) fires = length(latest)

fig = Figure(size = (800, 900))
ga = GeoAxis(fig[1, 1]; dest = "+proj=aea +lat_1=34 +lat_2=40.5 +lon_0=-120", GRID...,
    limits = (bbox[1], bbox[3], bbox[2], bbox[4]),
    title = "Active satellite perimeters, latest snapshot per fire ($(length(latest)) fires)",
    subtitle = "Deepfire deepfire:satellite-perimeters, $(stamp())")
poly!(ga, GeoMakie.land(50); color = :gray95, strokecolor = :gray60, strokewidth = 0.5)
lines!(ga, statelines(); color = :gray60, linewidth = 0.5)
polys!(ga, basic(latest); color = (:red, 0.8), strokecolor = :darkred, strokewidth = 0.5)
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
    scalebar!(ax, extent(geoms), lat)
end
Colorbar(fig[:, 4]; colormap = :viridis, limits = (0, 1), label = "fraction of elapsed time since first snapshot")
Label(fig[0, :], "Perimeter snapshot history, largest active fires in California bbox ($(stamp()))"; fontsize = 16)
save(joinpath(FIG, "perimeter_growth_california.png"), fig; px_per_unit = 2)

#-----------------------------------------------------------------------------# 3. Global overview
fcg = Deepfire.allitems("satellite-perimeters"; filter = "active = true")
latestg = Deepfire.latest_snapshots(fcg)
@info "Global" snapshots = length(fcg) fires = length(latestg)
cg = center.(basic(latestg))

fig = Figure(size = (1400, 750))
ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth", GRID...,
    title = "Active fires with a satellite perimeter ($(length(latestg)) fires)", subtitle = "Deepfire, $(stamp())")
poly!(ga, GeoMakie.land(); color = :gray95, strokecolor = :gray60, strokewidth = 0.3)
msize(a) = 1.5 + 0.6 * sqrt(a)
scatter!(ga, first.(cg), last.(cg); markersize = msize.(km2.(latestg)),
    color = (:red, 0.5), strokecolor = :darkred, strokewidth = 0.3)
areas = [1, 10, 100, 1000]
Legend(fig[1, 2], [MarkerElement(; marker = :circle, color = (:red, 0.5), strokecolor = :darkred, markersize = msize(a)) for a in areas],
    ["$a km²" for a in areas], "latest perimeter area")
save(joinpath(FIG, "active_perimeters_global.png"), fig; px_per_unit = 2)
