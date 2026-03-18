# Coordinate Manipulation Tools
# Port of Access VBA module V7mdlCoordTools with enhancements
# Critical: All functions handle NA/NULL explicitly (Access Nz() pattern)

# ============================================================================
# Core Conversions: DMS ↔ DD
# ============================================================================

#' Convert DMS to Decimal Degrees
#' 
#' Port of ConvertLongLatToDeg from V7mdlCoordTools
#' Handles NULL/NA values as Access Nz() does - returns NA if degrees is NA/NULL
#' 
#' @param degrees Numeric, degrees component
#' @param minutes Numeric, minutes component (default 0)
#' @param seconds Numeric, seconds component (default 0)
#' @param direction Character, one of "N", "S", "E", "W" (case-insensitive)
#' @return Numeric decimal degrees, or NA if invalid
#' @examples
#' dms_to_dd(49, 15, 30, "N")  # 49.2583
#' dms_to_dd(123, 45, 15, "W") # -123.7542
#' dms_to_dd(NA, 30, 0, "N")   # NA
dms_to_dd <- function(degrees, minutes = 0, seconds = 0, direction = NULL) {
  # Access pattern: If IsNull(Deg) Then ConvertLongLatToDeg = Null
  if (is.null(degrees) || length(degrees) == 0 || is.na(degrees)) {
    return(NA_real_)
  }
  
  # Coalesce missing/NA components to 0 (Access: If IsNull(Sec) Then Sec = 0)
  deg <- replace(degrees, is.na(degrees), 0)
  min <- replace(minutes, is.na(minutes), 0)
  sec <- replace(seconds, is.na(seconds), 0)
  
  # Calculate decimal degrees
  # Access: Deg + ((Min + (Sec / 60)) / 60)
  dd <- deg + (min + sec / 60) / 60
  
  # Apply direction sign if provided
  if (!is.null(direction) && length(direction) > 0 && !is.na(direction)) {
    dir_lower <- tolower(trimws(direction))
    if (dir_lower %in% c("s", "w")) {
      dd <- -abs(dd)  # Ensure negative
    } else if (dir_lower %in% c("n", "e")) {
      dd <- abs(dd)   # Ensure positive
    }
  }
  
  dd
}

#' Convert Decimal Degrees to DMS Components
#' 
#' Port of GetLatDMS/GetLongDMS from V7mdlCoordTools
#' Returns a list with d, m, s components
#' 
#' @param decimal_degrees Numeric, decimal degrees (can be negative)
#' @param is_latitude Logical, TRUE for latitude (affects hemisphere detection)
#' @return List with components: d (degrees), m (minutes), s (seconds), direction (N/S/E/W)
#' @examples
#' dd_to_dms(49.2583, TRUE)   # list(d=49, m=15, s=29.88, direction="N")
#' dd_to_dms(-123.7542, FALSE) # list(d=123, m=45, s=15.12, direction="W")
dd_to_dms <- function(decimal_degrees, is_latitude = TRUE) {
  # Access pattern: If IsNull(LatIn) Then GetLatDMS.d = Null
  if (is.null(decimal_degrees) || length(decimal_degrees) == 0 || is.na(decimal_degrees)) {
    return(list(d = NA_integer_, m = NA_integer_, s = NA_real_, direction = NA_character_))
  }
  
  # Determine direction based on sign
  direction <- if (is_latitude) {
    if (decimal_degrees < 0) "S" else "N"
  } else {
    if (decimal_degrees < 0) "W" else "E"
  }
  
  # Work with absolute value (Access: If LatIn < 0 Then LatIn = LatIn * -1)
  abs_val <- abs(decimal_degrees)
  
  # Extract degrees (Access: d = Int(LatIn))
  d <- as.integer(floor(abs_val))
  
  # Extract minutes (Access: TempVal = LatIn - d; m = Int(TempVal * 60))
  temp_val <- abs_val - d
  m <- as.integer(floor(temp_val * 60))
  
  # Extract seconds (Access: TempVal = (TempVal * 60) - m; s = TempVal * 60)
  temp_val <- (temp_val * 60) - m
  s <- temp_val * 60
  
  list(d = d, m = m, s = s, direction = direction)
}

#' Extract Degrees Component from Decimal Degrees
#' 
#' Port of GetLatLongDeg from V7mdlCoordTools
#' 
#' @param decimal_degrees Numeric
#' @return Integer degrees component, or NA if input is NA/NULL
get_degrees <- function(decimal_degrees) {
  # Access: If IsNull(ValIn) Then GetLatLongDeg = Null Else GetLatLongDeg = Int(ValIn)
  if (is.null(decimal_degrees) || length(decimal_degrees) == 0 || is.na(decimal_degrees)) {
    return(NA_integer_)
  }
  as.integer(floor(abs(decimal_degrees)))
}

#' Extract Minutes Component from Decimal Degrees
#' 
#' Port of GetLatLongMin from V7mdlCoordTools
#' 
#' @param decimal_degrees Numeric
#' @return Integer minutes component, or NA if input is NA/NULL
get_minutes <- function(decimal_degrees) {
  # Access: If IsNull(ValIn) Then GetLatLongMin = Null
  if (is.null(decimal_degrees) || length(decimal_degrees) == 0 || is.na(decimal_degrees)) {
    return(NA_integer_)
  }
  abs_val <- abs(decimal_degrees)
  d <- floor(abs_val)
  temp_val <- abs_val - d
  as.integer(floor(temp_val * 60))
}

#' Extract Seconds Component from Decimal Degrees
#' 
#' Port of GetLatLongSec from V7mdlCoordTools
#' 
#' @param decimal_degrees Numeric
#' @return Numeric seconds component, or NA if input is NA/NULL
get_seconds <- function(decimal_degrees) {
  # Access: If IsNull(ValIn) Then GetLatLongSec = Null
  if (is.null(decimal_degrees) || length(decimal_degrees) == 0 || is.na(decimal_degrees)) {
    return(NA_real_)
  }
  abs_val <- abs(decimal_degrees)
  d <- floor(abs_val)
  temp_val <- abs_val - d
  m <- floor(temp_val * 60)
  temp_val <- (temp_val * 60) - m
  temp_val * 60
}

# ============================================================================
# UTM Conversions (not in Access VBA - new functionality)
# ============================================================================

#' Convert UTM Coordinates to Latitude/Longitude
#' 
#' Uses simple inverse Mercator approximation suitable for BC (mid-latitudes)
#' For production use, consider rgdal/sf for precise transformations
#' 
#' @param easting Numeric, UTM easting in meters
#' @param northing Numeric, UTM northing in meters
#' @param zone Integer, UTM zone (7-11 typical for BC)
#' @param hemisphere Character, "N" or "S" (default "N")
#' @return List with lat (latitude) and lon (longitude) in decimal degrees, or NA if invalid
utm_to_latlon <- function(easting, northing, zone, hemisphere = "N") {
  # NULL handling
  if (is.null(easting) || is.null(northing) || is.null(zone) ||
      is.na(easting) || is.na(northing) || is.na(zone)) {
    return(list(lat = NA_real_, lon = NA_real_))
  }
  
  # Simplified UTM to Lat/Lon (WGS84) - for precise work, use sf/rgdal
  # This is a basic inverse Mercator projection approximation
  
  # Constants
  k0 <- 0.9996  # UTM scale factor
  a <- 6378137  # WGS84 equatorial radius (m)
  e <- 0.0818191908426  # WGS84 eccentricity
  e_sq <- e^2
  
  # Adjust for hemisphere
  if (toupper(hemisphere) == "S") {
    northing <- 10000000 - northing
  }
  
  # Central meridian for zone
  lon_origin <- (zone - 1) * 6 - 180 + 3
  
  # Relative easting
  x <- easting - 500000
  y <- northing
  
  # Footpoint latitude (simplified)
  M <- y / k0
  mu <- M / (a * (1 - e_sq/4 - 3*e_sq^2/64 - 5*e_sq^3/256))
  
  # More accurate footpoint latitude
  e1 <- (1 - sqrt(1 - e_sq)) / (1 + sqrt(1 - e_sq))
  
  phi1 <- mu + 
    (3*e1/2 - 27*e1^3/32) * sin(2*mu) +
    (21*e1^2/16 - 55*e1^4/32) * sin(4*mu) +
    (151*e1^3/96) * sin(6*mu)
  
  # Calculate latitude
  C1 <- e_sq * cos(phi1)^2 / (1 - e_sq)
  T1 <- tan(phi1)^2
  N1 <- a / sqrt(1 - e_sq * sin(phi1)^2)
  R1 <- a * (1 - e_sq) / (1 - e_sq * sin(phi1)^2)^1.5
  D <- x / (N1 * k0)
  
  lat <- phi1 - 
    (N1 * tan(phi1) / R1) * 
    (D^2/2 - (5 + 3*T1 + 10*C1 - 4*C1^2 - 9*e_sq) * D^4/24 +
       (61 + 90*T1 + 298*C1 + 45*T1^2 - 252*e_sq - 3*C1^2) * D^6/720)
  
  lon <- lon_origin + 
    (D - (1 + 2*T1 + C1) * D^3/6 + 
       (5 - 2*C1 + 28*T1 - 3*C1^2 + 8*e_sq + 24*T1^2) * D^5/120) / cos(phi1)
  
  # Convert from radians to degrees
  lat <- lat * 180 / pi
  lon <- lon * 180 / pi
  
  list(lat = lat, lon = lon)
}

#' Convert Latitude/Longitude to UTM Coordinates
#' 
#' Auto-detects UTM zone from longitude
#' Uses WGS84 datum, Northern hemisphere assumed for BC
#' 
#' @param latitude Numeric, decimal degrees (-90 to 90)
#' @param longitude Numeric, decimal degrees (-180 to 180)
#' @return List with easting, northing, zone, hemisphere
latlon_to_utm <- function(latitude, longitude) {
  # NULL handling
  if (is.null(latitude) || is.null(longitude) || is.na(latitude) || is.na(longitude)) {
    return(list(easting = NA_real_, northing = NA_real_, zone = NA_integer_, hemisphere = NA_character_))
  }
  
  # Determine hemisphere
  hemisphere <- if (latitude >= 0) "N" else "S"
  
  # Calculate UTM zone (0° = zone 31)
  zone <- floor((longitude + 180) / 6) + 1
  
  # Constants
  k0 <- 0.9996
  a <- 6378137
  e <- 0.0818191908426
  e_sq <- e^2
  
  # Central meridian
  lon_origin <- (zone - 1) * 6 - 180 + 3
  
  # Convert to radians
  lat_rad <- latitude * pi / 180
  lon_rad <- longitude * pi / 180
  lon_origin_rad <- lon_origin * pi / 180
  
  # Calculate UTM coordinates
  N <- a / sqrt(1 - e_sq * sin(lat_rad)^2)
  T <- tan(lat_rad)^2
  C <- e_sq * cos(lat_rad)^2 / (1 - e_sq)
  A <- (lon_rad - lon_origin_rad) * cos(lat_rad)
  
  # Meridional arc
  M <- a * ((1 - e_sq/4 - 3*e_sq^2/64 - 5*e_sq^3/256) * lat_rad -
              (3*e_sq/8 + 3*e_sq^2/32 + 45*e_sq^3/1024) * sin(2*lat_rad) +
              (15*e_sq^2/256 + 45*e_sq^3/1024) * sin(4*lat_rad) -
              (35*e_sq^3/3072) * sin(6*lat_rad))
  
  easting <- k0 * N * (A + (1 - T + C) * A^3/6 +
                         (5 - 18*T + T^2 + 72*C - 58*e_sq) * A^5/120) + 500000
  
  northing <- k0 * (M + N * tan(lat_rad) * (A^2/2 + (5 - T + 9*C + 4*C^2) * A^4/24 +
                                              (61 - 58*T + T^2 + 600*C - 330*e_sq) * A^6/720))
  
  # Adjust for southern hemisphere
  if (hemisphere == "S") {
    northing <- northing + 10000000
  }
  
  list(easting = easting, northing = northing, zone = zone, hemisphere = hemisphere)
}

# ============================================================================
# Format Detection & Parsing
# ============================================================================

#' Detect Coordinate Format
#' 
#' @param coord_string Character string containing coordinate
#' @return Character: "DMS", "DD", "UTM", or "UNKNOWN"
detect_coord_format <- function(coord_string) {
  if (is.null(coord_string) || length(coord_string) == 0 || is.na(coord_string)) {
    return("UNKNOWN")
  }
  
  str <- trimws(as.character(coord_string))
  if (!nzchar(str)) return("UNKNOWN")
  
  # Check if it's a simple decimal number first (more strict)
  if (grepl("^-?[0-9]+(\\.[0-9]+)?$", str)) {
    return("DD")
  }
  
  # Check for UTM pattern (large numbers, often paired with zone)
  if (grepl("^[0-9]{6,7}\\s+[0-9]{6,7}", str)) {
    return("UTM")
  }
  
  # Check for DMS indicators (degrees symbol, direction letters, multiple numbers with spaces)
  # Must have at least some numeric content AND valid DMS markers
  has_dms_markers <- grepl("[°'\"]|\\b[NSEW]\\b", str, ignore.case = TRUE)
  has_numbers <- grepl("[0-9]", str)
  
  if (has_dms_markers && has_numbers) {
    return("DMS")
  }
  
  # If it has multiple numbers separated by spaces, it might be DMS without symbols
  # But only if it looks reasonable (2-3 numeric parts)
  parts <- strsplit(gsub("[^0-9.\\s-]", " ", str), "\\s+")[[1]]
  parts <- parts[nzchar(parts)]
  if (length(parts) >= 2 && length(parts) <= 4 && all(grepl("^-?[0-9]+(\\.[0-9]+)?$", parts))) {
    # Likely DMS if first number is in reasonable lat/lon range
    first_num <- suppressWarnings(as.numeric(parts[1]))
    if (!is.na(first_num) && abs(first_num) <= 180) {
      return("DMS")
    }
  }
  
  "UNKNOWN"
}

#' Parse Coordinate String Auto-Detecting Format
#' 
#' Attempts to parse various coordinate formats
#' 
#' @param coord_string Character string
#' @param is_latitude Logical, hint for validation (default TRUE)
#' @return Numeric decimal degrees, or NA if unparseable
parse_coordinate <- function(coord_string, is_latitude = TRUE) {
  format <- detect_coord_format(coord_string)
  
  if (format == "DD") {
    val <- suppressWarnings(as.numeric(coord_string))
    return(val)
  }
  
  if (format == "DMS") {
    # Parse DMS format
    str <- toupper(trimws(coord_string))
    
    # Detect direction
    direction <- if (grepl("[SW]", str)) {
      if (grepl("S", str)) "S" else "W"
    } else if (grepl("[NE]", str)) {
      if (grepl("N", str)) "N" else "E"
    } else {
      NA_character_
    }
    
    # Extract numeric components
    cleaned <- gsub("[^0-9.+-]", " ", str)
    parts <- strsplit(cleaned, "\\s+")[[1]]
    parts <- parts[nzchar(parts)]
    
    if (length(parts) == 0) return(NA_real_)
    
    nums <- suppressWarnings(as.numeric(parts))
    nums <- nums[!is.na(nums)]
    
    if (length(nums) == 0) return(NA_real_)
    
    # Extract D, M, S
    deg <- abs(nums[1])
    min <- if (length(nums) >= 2) abs(nums[2]) else 0
    sec <- if (length(nums) >= 3) abs(nums[3]) else 0
    
    # Convert using our NULL-safe function
    dd <- dms_to_dd(deg, min, sec, direction)
    return(dd)
  }
  
  # Unknown or UTM - return NA (UTM needs zone info)
  NA_real_
}

# ============================================================================
# Validation
# ============================================================================

#' Validate Coordinate Value
#' 
#' Checks if coordinate is within valid range
#' BC-specific ranges: Lat 48-60°N, Lon 114-139°W
#' 
#' @param value Numeric, coordinate in decimal degrees
#' @param type Character, "latitude" or "longitude"
#' @param strict Logical, if TRUE uses BC-specific bounds, else global bounds
#' @return List with valid (logical) and message (character)
validate_coordinate <- function(value, type = c("latitude", "longitude"), strict = FALSE) {
  type <- match.arg(type)
  
  if (is.null(value) || is.na(value)) {
    return(list(valid = FALSE, message = "Coordinate is missing or NA"))
  }
  
  if (!is.numeric(value)) {
    return(list(valid = FALSE, message = "Coordinate must be numeric"))
  }
  
  if (type == "latitude") {
    if (value < -90 || value > 90) {
      return(list(valid = FALSE, message = sprintf("Latitude %.4f is out of range (-90 to 90)", value)))
    }
    if (strict && (value < 48 || value > 60)) {
      return(list(valid = FALSE, message = sprintf("Latitude %.4f is outside BC range (48 to 60°N)", value)))
    }
  } else {
    if (value < -180 || value > 180) {
      return(list(valid = FALSE, message = sprintf("Longitude %.4f is out of range (-180 to 180)", value)))
    }
    if (strict && (value < -139 || value > -114)) {
      return(list(valid = FALSE, message = sprintf("Longitude %.4f is outside BC range (-139 to -114°W)", value)))
    }
  }
  
  list(valid = TRUE, message = "OK")
}

#' Validate Latitude (convenience wrapper)
#' 
#' @param latitude Numeric
#' @param strict Logical, use BC-specific bounds
#' @return List with valid and message
validate_latitude <- function(latitude, strict = FALSE) {
  validate_coordinate(latitude, "latitude", strict)
}

#' Validate Longitude (convenience wrapper)
#' 
#' @param longitude Numeric
#' @param strict Logical, use BC-specific bounds
#' @return List with valid and message
validate_longitude <- function(longitude, strict = FALSE) {
  validate_coordinate(longitude, "longitude", strict)
}

# ============================================================================
# Utility Functions
# ============================================================================

#' Format DMS for Display
#' 
#' Pretty-print DMS coordinates
#' 
#' @param deg Integer, degrees
#' @param min Integer, minutes
#' @param sec Numeric, seconds
#' @param direction Character, N/S/E/W
#' @return Character formatted string
format_dms_display <- function(deg, min, sec, direction) {
  # NULL handling
  if (is.na(deg) || is.na(min) || is.na(sec)) {
    return("")
  }

  # Match Access-like, keyboard-friendly formatting.
  # Tests and UI expect a simple space-delimited form, e.g. "49 12 00.00 N".
  sprintf("%d %02d %05.2f %s", deg, min, sec, direction)
}

#' Normalize Bearing to 0-360
#' 
#' @param bearing Numeric, bearing in degrees
#' @return Numeric bearing between 0 and 360
normalize_bearing <- function(bearing) {
  if (is.null(bearing) || is.na(bearing)) {
    return(NA_real_)
  }
  
  # Reduce to 0-360 range
  bearing %% 360
}

#' Calculate Distance Between Two Points (Haversine)
#' 
#' @param lat1 Numeric, latitude of point 1 (decimal degrees)
#' @param lon1 Numeric, longitude of point 1
#' @param lat2 Numeric, latitude of point 2
#' @param lon2 Numeric, longitude of point 2
#' @return Numeric distance in meters, or NA if any input is invalid
calculate_distance <- function(lat1, lon1, lat2, lon2) {
  # NULL handling
  if (any(is.na(c(lat1, lon1, lat2, lon2)))) {
    return(NA_real_)
  }
  
  # Haversine formula
  R <- 6371000  # Earth radius in meters
  
  # Convert to radians
  lat1_rad <- lat1 * pi / 180
  lat2_rad <- lat2 * pi / 180
  delta_lat <- (lat2 - lat1) * pi / 180
  delta_lon <- (lon2 - lon1) * pi / 180
  
  a <- sin(delta_lat/2)^2 + 
    cos(lat1_rad) * cos(lat2_rad) * sin(delta_lon/2)^2
  
  c <- 2 * atan2(sqrt(a), sqrt(1-a))
  
  R * c
}
