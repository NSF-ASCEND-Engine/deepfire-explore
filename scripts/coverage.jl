# What the API holds, by region and time. Writes
#   figures/coverage.md                      -- markdown table of probe results (included by the site)
#   figures/cowy_new_clusters_per_month.png  -- new candidate fires per month, Colorado and Wyoming
using Deepfire, GeoJSON, CairoMakie, Dates

const FIG = normpath(joinpath(@__DIR__, "..", "figures"))
const COWY = (-111.06, 36.99, -102.04, 45.0)
const CONUS = (-125.0, 24.0, -66.0, 50.0)
const MARSHALL = (-105.30, 39.90, -105.10, 40.02)   # Boulder County, CO; the Marshall Fire burned 2021-12-30

window(a, b) = "observed_at >= TIMESTAMP('$(a)T00:00:00Z') AND observed_at < TIMESTAMP('$(b)T00:00:00Z')"
probes = [
    ("Global", nothing, "2025-01-01", "2025-07-01"),
    ("Global", nothing, "2025-07-01", "2026-01-01"),
    ("Global", nothing, "2026-01-01", "2026-02-01"),
    ("CONUS", CONUS, "2025-01-01", "2026-01-01"),
    ("CONUS", CONUS, "2026-01-01", "2026-02-01"),
    ("Colorado/Wyoming", COWY, "2025-01-01", "2026-02-01"),
    ("Colorado/Wyoming", COWY, "2026-02-01", "2026-02-10"),
    ("Marshall Fire bbox", MARSHALL, "2021-12-29", "2022-01-03"),
    ("Marshall Fire bbox", MARSHALL, "2025-01-01", "2027-01-01"),
]
uniq(fc, k) = join(sort(unique(string.(coalesce.(getproperty.(fc, k), "?")))), ", ")
open(joinpath(FIG, "coverage.md"), "w") do io
    println(io, "| region | observed_at window | hotspots (first 1000) | earliest | sources | countries |")
    println(io, "|---|---|---|---|---|---|")
    for (name, bbox, a, b) in probes
        fc = Deepfire.items("hotspots"; bbox, filter = window(a, b), limit = 1000)
        n = length(fc)
        earliest = n == 0 ? "" : string(minimum(Deepfire.parsetime.(getproperty.(fc, :observed_at))))
        println(io, "| $name | $a to $b | $n | $earliest | $(n == 0 ? "" : uniq(fc, :source)) | $(n == 0 ? "" : uniq(fc, :country)) |")
    end
    println(io, "\nChecked $(Dates.format(now(UTC), "yyyy-mm-dd HH:MM")) UTC.")
end
println(read(joinpath(FIG, "coverage.md"), String))

#-----------------------------------------------------------------------------# new clusters per month, CO/WY
clusters = Deepfire.allitems("clusters"; bbox = COWY)
months = [Date(Deepfire.parsetime(c.first_observed)) |> firstdayofmonth for c in clusters]
u = sort(unique(months))
counts = [count(==(m), months) for m in u]
fig = Figure(size = (900, 450))
ax = Axis(fig[1, 1]; xticks = (1:length(u), Dates.format.(u, "yyyy-mm")), ylabel = "new clusters", ytickformat = v -> string.(round.(Int, v)),
    title = "New hotspot clusters (candidate fires) per month, Colorado and Wyoming ($(length(clusters)) total)")
barplot!(ax, 1:length(u), counts; color = :firebrick)
save(joinpath(FIG, "cowy_new_clusters_per_month.png"), fig; px_per_unit = 2)
println("clusters per month: ", collect(zip(u, counts)))
