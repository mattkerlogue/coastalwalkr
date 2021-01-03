
library(tidyverse)

### Initial investigations -----

# get coastline
world_coastline <- rnaturalearth::ne_coastline(scale = 10, returnclass = "sf")

world_polygons <- world_coastline %>%
  sf::st_polygonize()

# London is roughly at 0ºE 51.5ºN
gb_ref_point <- sf::st_sfc(sf::st_point(x = c(-0.12768, 51.50739), dim = "XY"), crs = "WGS84")

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


### Tweet 2: DfT NaPTAN/NPTG data -----

# download NAPTAN data
naptan_url <- "https://naptan.app.dft.gov.uk/DataRequest/Naptan.ashx?format=csv"
dest_file <- paste0("data/source/naptan/naptan", Sys.Date(), "_download.zip")
unzip_loc <- paste0("data/source/naptan/", gsub(".zip", "", basename(dest_file)))
dir.create(unzip_loc)

download.file(naptan_url, dest_file)
unzip(dest_file, exdir = unzip_loc)

# read in data
stops <- read_csv(paste0(unzip_loc, "/Stops.csv"), 
                  col_types = cols(.default = col_character()))
stops_in_area <- read_csv(paste0(unzip_loc, "/StopsInArea.csv"), 
                          col_types = cols(.default = col_character()))
rail_ref <- read_csv(paste0(unzip_loc, "/RailReferences.csv"), 
                     col_types = cols(.default = col_character()))
metro_ref <- read_csv(paste0(unzip_loc, "/MetroReferences.csv"), 
                      col_types = cols(.default = col_character()))

# get stop types metadata from CSV of table 6-1 in reference PDF
stop_types <- read_csv("data/source/naptan/stop_types.csv")

# filter for active stops
live_stops <- stops %>%
  janitor::clean_names() %>%
  filter(status == "act") %>%
  select(atco_code, naptan_code, common_name, street, landmark, 
         locality_name, parent_locality_name, nptg_locality_code,
         longitude, latitude, stop_type) %>%
  left_join(stop_types, by = c("stop_type" = "type")) %>%
  filter(open_access)

# filter for rail and metro stops
rail_metro <- live_stops %>%
  filter(mode == "rail" | mode == "metro")

# rail data messy, use rail_ref for railway, but metro 
# (which includes tram & heritage rail) might still be useful
metro <- live_stops %>%
  filter(mode == "metro")


air_ferry <- live_stops %>%
  filter(mode == "air" | mode == "ferry")

# get bus stops
bus_stops <- live_stops %>%
  filter(mode == "bus")

clean_bus_stops <- bus_stops %>%
  mutate(
    across(c(street, landmark), ~na_if(., "---")),
    across(c(street, landmark), ~na_if(., "*")),
    across(c(street, landmark), ~na_if(., "-")),
    across(c(street, landmark), ~na_if(., "N/A")),
    across(c(street, landmark), ~na_if(., "NA")),
    across(c(street, landmark), ~na_if(., "Unknown")),
    across(c(street, landmark), 
           ~if_else(str_detect(tolower(.), "not known"), NA_character_, .)),
    across(c(common_name, street, landmark), str_squish),
    across(c(street, landmark), str_to_title),
    landmark = na_if(landmark, "Bus Stop"),
    street = na_if(street, "Airport"),
    divider_flag = str_detect(common_name, "-|/"),
    common_name_words = str_count(common_name, "\\s"),
    landmark_words = str_count(landmark, "\\s"),
    stop_name = case_when(
      str_detect(common_name, "^Outside No\\W+\\d+$") ~ 
        paste(common_name, street, locality_name, sep = ", "),
      landmark == "The Pool Dam PH" ~
        paste(landmark, street, locality_name, sep = ", "),
      atco_code == "3800C515701" ~
        paste(common_name, street, locality_name, sep = ", "),
      atco_code == "64804097" ~
        paste(landmark, street, locality_name, sep = ", "),
      atco_code == "64802181" ~
        paste(common_name, street, locality_name, sep = ", "),
      str_detect(common_name, "^Bus Stop No\\W+\\d+$") ~ 
        paste(common_name, street, locality_name, sep = ", "),
      str_detect(common_name, "^Road No\\W+\\d+$") ~ 
        paste(landmark, street, locality_name, sep = ", "),
      str_detect(common_name, "^Mill No\\W+\\d+$") ~ 
        paste(common_name, street, locality_name, sep = ", "),
      str_detect(common_name, "^No\\W+\\d+$") & is.na(landmark) ~
        paste(common_name, street, locality_name, sep = ", "),
      str_detect(common_name, "^No\\W+\\d+$") & (landmark == street) ~
        paste(common_name, street, locality_name, sep = ", "),
      str_detect(common_name, "^No\\W+\\d+$") & (landmark != street) ~
        paste(common_name, street, locality_name, sep = ", "),
      (common_name == street) & (common_name == locality_name) & !is.na(landmark) ~
        paste(landmark, common_name, locality_name, sep = ", "),
      (common_name == street) & (common_name == locality_name) & 
        !is.na(parent_locality_name) ~
        paste(common_name, parent_locality_name, sep = ", "),
      is.na(landmark) & is.na(street) ~
        paste(common_name, locality_name, sep = ", "),
      is.na(landmark) ~
        paste(common_name, street, locality_name, sep = ", "),
      is.na(street) & (common_name == landmark) ~
        paste(common_name, locality_name, sep = ", "),
      is.na(street) & !is.na(landmark) ~
        paste(common_name, landmark, locality_name, sep = ", "),
      (common_name == street) & (common_name == landmark) ~
        paste(common_name, locality_name, sep = ", "),
      (common_name == street) & (common_name != landmark) ~
        paste(landmark, street, locality_name, sep = ", "),
      (common_name == landmark) ~
        paste(common_name, street, locality_name, sep = ", "),
      divider_flag ~
        paste(common_name, street, locality_name, sep = ", "),
      (landmark_words == common_name_words) ~
        paste(common_name, street, locality_name, sep = ", "),
      (landmark_words > common_name_words) ~
        paste(landmark, street, locality_name, sep = ", "),
      (common_name_words > landmark_words) ~
        paste(common_name, street, locality_name, sep = ", "),
      (common_name_words == landmark_words) & (common_name == street) ~
        paste(landmark, street, locality_name, sep = ", "),
      (common_name_words == landmark_words) & (common_name == street) ~
        paste(landmark, street, locality_name, sep = ", "),
      TRUE ~ NA_character_
  )) %>%
  select(atco_code, stop_name, longitude, latitude)

clean_bus_stop_names <- clean_bus_stops %>%
  separate_rows(stop_name, sep = ", ") %>%
  group_by(atco_code) %>%
  mutate(id = row_number()) %>%
  distinct(stop_name) %>%
  summarise(stop_name = paste(stop_name, collapse = ", ")) %>%
  ungroup()

clean_bus_stops_final <- clean_bus_stops %>%
  select(atco_code, longitude, latitude) %>%
  left_join(clean_bus_stops_2, by = "atco_code")

clean_bus_stops_geo <- clean_bus_stops_final %>%
  mutate(across(c(longitude, latitude), as.numeric)) %>%
  sf::st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

rail_geo <- rail_ref %>%
  janitor::clean_names() %>%
  select(atco_code, station_name, station_code = crs_code, easting, northing) %>%
  mutate(across(c(easting, northing), as.numeric)) %>%
  sf::st_as_sf(coords = c("easting", "northing"), crs = 27700)

rail_geo_wgs84 <- sf::st_transform(rail_geo, crs = sf::st_crs(4326))

nearby_bus_stops <- sf::st_crop(clean_bus_stops_geo, xmin = -3.4, xmax = -2.8, 
                                ymin = 56.3, ymax = 56.5)

ggplot() + 
  geom_sf(data = gb_coastline, colour = "grey80") +
  geom_sf(data = gb_simple_segments, colour = "blue") +
  geom_sf(data = gb_simple_points[1:3,], colour = "blue") +
  geom_sf(data = local_coast) +
  geom_sf(data = nearest_coast, colour = "red") +
  geom_sf(data = nearby_bus_stops, shape = 17, colour = "green") +
  geom_sf(data = rail_geo, shape = 17, colour = "blue") +
  xlim(-3.4, -2.8) +
  ylim(56.3, 56.5)
