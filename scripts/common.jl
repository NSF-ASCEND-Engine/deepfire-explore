# Shared helpers for the plotting scripts. Include after
# `using Deepfire, GeoJSON, CairoMakie, GeoMakie, NaturalEarth, Dates`.
using GeoMakie.GeoInterface

const FIG = normpath(joinpath(@__DIR__, "..", "figures"))
mkpath(FIG)
const GRID = (xgridcolor = (:black, 0.1), ygridcolor = (:black, 0.1))

basic(feats) = [GeoMakie.geo2basic(f.geometry) for f in feats if !ismissing(f.geometry)]
center(g) = (ext = GeoInterface.extent(g); (sum(ext.X) / 2, sum(ext.Y) / 2))
km2(f) = round(something(f.area_m2, 0.0) / 1e6; digits = 1)
stamp() = Dates.format(now(UTC), "yyyy-mm-dd HH:MM") * " UTC"
statelines() = GeoMakie.to_multilinestring.(basic(naturalearth("admin_1_states_provinces_lines", 10)))

"`poly!` that skips empty inputs (Makie cannot convert an empty polygon vector)."
polys!(ax, geoms; kw...) = isempty(geoms) ? nothing : poly!(ax, geoms; kw...)

"(minlon, maxlon, minlat, maxlat) covering all geometries."
function extent(geoms)
    exts = GeoInterface.extent.(geoms)
    (minimum(e.X[1] for e in exts), maximum(e.X[2] for e in exts), minimum(e.Y[1] for e in exts), maximum(e.Y[2] for e in exts))
end

"Scale bar along a parallel, below the lower-left corner of the extent."
function scalebar!(ax, (x0, x1, y0, y1), lat)
    kmperdeg = 111.32 * cosd(lat)
    L = first(l for l in (0.5, 1, 2, 5, 10, 20, 50, 100) if l >= (x1 - x0) * kmperdeg / 4)
    yb = y0 - 0.08 * (y1 - y0)
    lines!(ax, [x0, x0 + L / kmperdeg], [yb, yb]; color = :black, linewidth = 2)
    text!(ax, x0 + L / kmperdeg / 2, yb; text = "$L km", align = (:center, :top), fontsize = 11)
end
