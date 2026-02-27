library(sf)
library(dplyr)
library(h3jsr)

# 1. Define the Lognormal parameters (using Chicago as an example)
# mu = 0.33, sigma = 0.66 (in miles)
mu_log <- 0.33
sd_log <- 0.66
miles_to_meters <- 1609.34

# 2. Add H3 addresses to all buildings once (Resolution 8 or 9)
buildings_h3 <- buildings |> 
  mutate(h3_addr = point_to_cell(geometry, res = 8))

# 3. Start with weighted Destinations
set.seed(42)
destinations <- buildings_h3 |> 
  slice_sample(n = 20000, weight_by = volume_m3, replace = TRUE) |> 
  mutate(trip_id = row_number())

# 4. Generate random target distances for each trip
# We draw from the lognormal and convert to meters
destinations <- destinations |> 
  mutate(
    target_dist_m = rlnorm(n(), meanlog = mu_log, sdlog = sd_log) * miles_to_meters
  )

# 5. Function to find a nearby Origin
find_origin <- function(dest_h3, target_m, pool) {
  # Estimate H3 ring size based on target distance
  # (H3 Res 8 edge length is ~460m)
  ring_radius <- ceiling(target_m / 460)
  
  # Get H3 cells in that specific ring (not the whole disk)
  # This creates a "donut" of potential origins
  potential_cells <- get_ring(dest_h3, ring_radius) |> unlist()
  
  # Filter pool to these cells
  candidates <- pool[pool$h3_addr %in% potential_cells, ]
  
  if(nrow(candidates) == 0) return(NA) # Fallback if ring is empty
  
  # Sample one building (Unweighted, as you requested)
  candidates |> slice_sample(n = 1) |> pull(geometry)
}

# 6. Map the origins (Example on a subset for speed)
# result <- destinations |> mutate(origin_geom = map2(h3_addr, target_dist_m, ~find_origin(.x, .y, buildings_h3)))