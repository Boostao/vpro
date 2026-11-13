# Coordinate conversion contract

## Access evidence

The canonical implementation is `V7mdlCoordTools` in the Access SaveAsText corpus.
It defines decimal-degree composition, degree-minute-second decomposition, and
degree-decimal-minute decomposition separately for longitude and latitude.
The latitude and longitude implementations are otherwise identical.

`ConvertLongLatToDeg` returns null when degrees are null, treats omitted or null
minutes and seconds as zero, and calculates:

`degrees + (minutes + seconds / 60) / 60`

This means a negative degree with positive components moves toward zero; the
routine does not apply the degree sign to the complete magnitude.

`GetLongDMS`, `GetLatDMS`, `GetLongDM`, and `GetLatDM` remove a negative input
sign before decomposition. Hemisphere or sign is therefore maintained outside
these returned components. Null inputs produce null components.

The lower-level `GetLatLongDeg`, `GetLatLongMin`, and `GetLatLongSec` functions
extract individual components. Unlike the latitude- and longitude-specific
wrappers, they do not remove negative signs before applying VBA `Int`.
Their observed callers should therefore be reviewed before using them as a
signed-coordinate contract.

## Package API

- `vpro_coordinate_decimal()` composes decimal degrees and preserves the Access
  null/default and component-sign calculation.
- `vpro_coordinate_dms()` returns vectorized nonnegative degree, minute, and
  second components in a data frame.
- `vpro_coordinate_dm()` returns vectorized nonnegative degree and decimal-minute
  components in a data frame.

The package consolidates duplicate latitude and longitude routines because the
Access algorithms are identical. It also consolidates the lower-level component
helpers into the structured DMS result for nonnegative coordinates. Inputs must
be numeric and finite or missing, and component vectors must have a common
length or length one.

R double precision is retained intentionally instead of reproducing the loss of
precision caused by VBA `Single` intermediate variables. No range restriction is
imposed because the Access procedures do not enforce latitude, longitude,
minute, or second bounds.
