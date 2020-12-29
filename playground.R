
library(tidyverse)

# get coastline
world_coastline <- rnaturalearth::ne_coastline(scale = 10, returnclass = "sf")

world_polygons <- world_coastline %>%
  sf::st_polygonize()

# London is roughly at 0ºE 51.5ºN
gb_ref_point <- sf::st_sfc(sf::st_point(x = c(0, 51.5), dim = "XY"), crs = "WGS84")

# extract gb coastline as corresponding linestring of the polygon 
# containing London
gb_coastline <- world_coastline[as.numeric(sf::st_within(gb_ref_point, world_polygons)),]

# convert gb coastline to OS grid
gb_coastline <- sf::st_transform(gb_coastline, sf::st_crs(27700))

# simplify coastline to reduce walking points
gb_coast_simplify <- sf::st_simplify(gb_coastline,
                                     dTolerance = 2000)

# convert coastlines back to WGS84 for easy plotting
gb_coast_simplify <- sf::st_transform(gb_coast_simplify, sf::st_crs(4326))
gb_coastline <- sf::st_transform(gb_coastline, sf::st_crs(4326))

# convert simple coast into 2km segments to simulate walking and get points
gb_simple_segments <- sf::st_segmentize(gb_coast_simplify, dfMaxLength = 2000)
gb_simple_points <- sf::st_cast(gb_simple_segments, "POINT")

# convert coastline into points
gb_coast_points <- sf::st_cast(gb_coastline, "POINT")

# get first three points on our walk
local_points <- gb_simple_points[1:3,]

# get forward stretch of coastline in a particular direction
local_coast <- gb_coast_points[1:20,] %>% 
  sf::st_coordinates() %>% 
  sf::st_linestring() %>%
  sf::st_sfc(crs = "WGS84")

# find the nearest real points on the coastline from our virtual walking path
nearest_coast <- sf::st_nearest_points(local_points, local_coast) %>%
  lwgeom::st_endpoint()

# plot points
ggplot() + 
  geom_sf(data = gb_coastline, colour = "grey80") +
  geom_sf(data = gb_simple_segments, colour = "blue") +
  geom_sf(data = gb_simple_points[1:3,], colour = "blue") +
  geom_sf(data = local_coast) +
  geom_sf(data = nearest_coast, colour = "red") +
  xlim(-3.4, -2.8) +
  ylim(56.3, 56.5)
