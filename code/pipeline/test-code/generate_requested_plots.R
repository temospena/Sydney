library(dplyr)
library(ggplot2)
library(sf)
library(tidyr)
library(stringr)
library(ggrepel)
library(maps)

# Load configuration if possible, but we'll use paths directly
proj_root <- "/home/rosa/GIS/Sydney"
data_dir <- file.path(proj_root, "data/pipeline")

# Cities lists provided by user
target_cities <- c(
    "Amsterdam", "Austin", "Barcelona", "Beijing", "Berlin", "Bogota",
    "Bologna", "Brussels", "Buenos Aires", "Cairo", "Cape Town",
    "Chicago", "Christchurch", "Curitiba", "Dublin", "Gent", "Glasgow",
    "Graz", "Hamburg", "Helsinki", "Hong Kong", "Kyoto", "Leeds",
    "Lisbon", "Ljubljana", "London", "Lyon", "Madrid", "Melbourne",
    "Mexico City", "Milan", "Minneapolis", "Montpellier", "Montréal",
    "Munich", "Nantes", "New York", "Oslo", "Paris", "Portland",
    "San Francisco", "Santiago", "Sao Paulo", "Seattle", "Seoul",
    "Seville", "Shanghai", "Stockholm", "Strasbourg", "Sydney", "Taipei",
    "Tokyo", "Turin", "Vancouver", "Vienna", "Warsaw", "Zurich"
)
cities_less_100k <- c("Cairo", "Cape Town", "Hong Kong")
cities_weired_tagging <- c("Lisbon", "Munich", "Ljubljana")
cities_no_data <- c()
cities_no_10pct_growth <- c("Amsterdam", "Stockholm")
target_cities_clean <- setdiff(
    target_cities,
    c(
        cities_less_100k,
        cities_weired_tagging,
        cities_no_data,
        cities_no_10pct_growth
    )
)

# Continent/Region mapping (simplified for coloring)
continent_lookup <- data.frame(
    city = target_cities,
    continent = c(
        "Europe", "North America", "Europe", "Asia", "Europe", "South America",
        "Europe", "Europe", "South America", "Africa", "Africa",
        "North America", "Oceania", "South America", "Europe", "Europe", "Europe",
        "Europe", "Europe", "Europe", "Asia", "Asia", "Europe",
        "Europe", "Europe", "Europe", "Europe", "Europe", "Oceania",
        "North America", "Europe", "North America", "Europe", "North America",
        "Europe", "Europe", "North America", "Europe", "Europe", "North America",
        "North America", "South America", "South America", "North America", "Asia",
        "Europe", "Asia", "Europe", "Europe", "Oceania", "Asia",
        "Asia", "Europe", "North America", "Europe", "Europe", "Europe"
    )
)

# Function to get city center from bbox or data
get_city_coords <- function(city) {
    city_dir <- tolower(city)
    city_dir <- gsub(" ", "_", city_dir)
    bbox_file <- file.path(data_dir, city_dir, paste0(city_dir, "_bbox.txt"))

    if (file.exists(bbox_file)) {
        bbox_text <- readLines(bbox_file, n = 1)
        bbox_coords <- as.numeric(strsplit(bbox_text, ",")[[1]])
        lon <- (bbox_coords[1] + bbox_coords[3]) / 2
        lat <- (bbox_coords[2] + bbox_coords[4]) / 2
        return(data.frame(city = city, lon = lon, lat = lat))
    } else {
        origins_file <- file.path(data_dir, city_dir, "origins.gpkg")
        if (file.exists(origins_file)) {
            origins <- st_read(origins_file, quiet = TRUE)
            bbox <- st_bbox(origins)
            lon <- as.numeric((bbox["xmin"] + bbox["xmax"]) / 2)
            lat <- as.numeric((bbox["ymin"] + bbox["ymax"]) / 2)
            return(data.frame(city = city, lon = lon, lat = lat))
        }
    }

    # Fallback manual lookups
    if (city == "Buenos Aires") {
        return(data.frame(city = city, lon = -58.3816, lat = -34.6037))
    }
    if (city == "Mexico City") {
        return(data.frame(city = city, lon = -99.1332, lat = 19.4326))
    }
    if (city == "Hong Kong") {
        return(data.frame(city = city, lon = 114.1694, lat = 22.3193))
    }
    if (city == "Cape Town") {
        return(data.frame(city = city, lon = 18.4233, lat = -33.9249))
    }
    if (city == "Sao Paulo") {
        return(data.frame(city = city, lon = -46.6333, lat = -23.5505))
    }
    if (city == "Bogota") {
        return(data.frame(city = city, lon = -74.0721, lat = 4.7110))
    }
    if (city == "Montreal" || city == "Montréal") {
        return(data.frame(city = city, lon = -73.5673, lat = 45.5017))
    }

    return(data.frame(city = city, lon = NA, lat = NA))
}

city_coords_df <- do.call(rbind, lapply(target_cities, get_city_coords))

# Maps package fallback for missing
missing <- city_coords_df %>% filter(is.na(lon))
if (nrow(missing) > 0) {
    data(world.cities)
    for (i in 1:nrow(missing)) {
        match <- world.cities %>%
            filter(name == missing$city[i]) %>%
            arrange(desc(pop)) %>%
            head(1)
        if (nrow(match) > 0) {
            city_coords_df$lon[city_coords_df$city == missing$city[i]] <- match$long
            city_coords_df$lat[city_coords_df$city == missing$city[i]] <- match$lat
        }
    }
}

# Plot 1: Map
world <- map_data("world")
city_coords_df <- city_coords_df %>%
    mutate(in_model = city %in% target_cities_clean)

p1 <- ggplot() +
    geom_polygon(data = world, aes(x = long, y = lat, group = group), fill = "#f9f9f9", color = "#cccccc", size = 0.1) +
    geom_point(data = city_coords_df, aes(x = lon, y = lat, color = in_model), size = 2) +
    geom_text_repel(
        data = city_coords_df,
        aes(
            x = lon, y = lat, label = city,
            color = in_model, fontface = ifelse(in_model, "bold", "italic")
        ),
        size = 3.5, alpha = 0.8, segment.size = 0.2
    ) +
    scale_color_manual(values = c("TRUE" = "#d95f02", "FALSE" = "grey40")) +
    theme_void() +
    labs(
        title = "Global Distribution of Selected Cities",
        subtitle = "Bold orange: Included in model | Italic grey: Excluded"
    ) +
    theme(
        legend.position = "none",
        plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
        plot.subtitle = element_text(hjust = 0.5, size = 12)
    )

ggsave(file.path(proj_root, "images/city_map_points.png"), p1, width = 14, height = 8, bg = "white")

# Plot 2: CI evolution colored by continent
final_estimations <- read.csv(file.path(data_dir, "final_city_estimations.csv"))

ci_data <- final_estimations %>%
    filter(city %in% target_cities_clean) %>%
    mutate(total_ci_km = total_ci_m / 1000) %>%
    # Convert year to numeric and handle if it's short (e.g., 16) or full (e.g., 2016)
    mutate(year_val = as.numeric(as.character(year))) %>%
    mutate(year_num = ifelse(year_val < 100, 2000 + year_val, year_val)) %>%
    group_by(city, year_num) %>%
    summarise(total_ci_km = mean(total_ci_km, na.rm = TRUE), .groups = "drop") %>%
    left_join(continent_lookup, by = "city")

ci_avg <- ci_data %>%
    group_by(year_num) %>%
    summarise(avg_ci_km = mean(total_ci_km, na.rm = TRUE), .groups = "drop") %>%
    arrange(year_num) %>%
    mutate(
        prev_avg = lag(avg_ci_km),
        growth_pct = (avg_ci_km / prev_avg - 1) * 100,
        label = ifelse(is.na(growth_pct), "", paste0("+", round(growth_pct, 1), "%")),
        # Position label at midpoint between years
        mid_year = (year_num + lag(year_num)) / 2,
        mid_val = (avg_ci_km + lag(avg_ci_km)) / 2
    )

p2 <- ggplot(ci_data, aes(x = year_num, y = total_ci_km)) +
    geom_jitter(aes(color = continent), width = 0.3, alpha = 0.6, size = 2.5) +
    # Trend line for average
    geom_line(
        data = ci_avg, aes(x = year_num, y = avg_ci_km, group = 1),
        color = "black", size = 1.2, alpha = 0.5
    ) +
    # Growth labels
    geom_label(
        data = filter(ci_avg, label != ""),
        aes(x = mid_year, y = mid_val, label = label),
        fill = "white", color = "black", fontface = "bold", size = 4,
        label.padding = unit(0.2, "lines"), alpha = 0.8
    ) +
    # Average points
    geom_point(
        data = ci_avg, aes(x = year_num, y = avg_ci_km),
        color = "black", fill = "white", size = 6, shape = 23, stroke = 1.5
    ) +
    scale_color_brewer(palette = "Set2") +
    scale_x_continuous(breaks = c(2016, 2019, 2021, 2024, 2026)) +
    theme_minimal(base_size = 14) +
    labs(
        title = "Evolution of Cycling Infrastructure Length by City",
        subtitle = "Individual cities colored by continent | Global average (% growth between steps)",
        x = "Year",
        y = "Total CI length (km)",
        color = "Continent"
    ) +
    theme(
        plot.title = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "bottom"
    )

ggsave(file.path(proj_root, "images/ci_evolution_km_continent.png"), p2, width = 12, height = 8, bg = "white")

cat("Plots saved to images/city_map_points.png and images/ci_evolution_km_continent.png\n")
