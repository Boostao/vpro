# Value classification and rounding contract

## Access evidence

The canonical source is `V7mdlValueConversions` in the Access SaveAsText corpus.
The classification routines are used primarily by `V7mdlReportsShortVeg`, both
directly and in dynamically generated Access SQL.

`Presence2Class` maps proportions from zero through one to Roman-numeral classes
I through V in 0.2-wide intervals. Upper boundaries belong to the lower class.
`Presence2ClassNval` applies the same boundaries using character labels 1 through
5, but its fifth class has no upper bound.

`ProminenceClass` calculates:

`mean cover * 10 * sqrt(presence)`

and maps the result at boundaries 15, 50, 100, and 200 to classes 1 through 5.
`GoldstreamClass` calculates:

`presence * 100 * sqrt(mean cover)`

and maps the result at boundaries 5, 25, 75, 150, 300, and 500 to classes 0
through 6. Both return the score instead when global report option `SVShowClass`
is 20.

Both score functions call `vpRoundUp`, but that routine immediately overwrites
both attempted rounding results with its input. Its observed effect is therefore
identity. The package classification functions deliberately use the unrounded
score.

`SignifClass` maps values above -1 to `+` and classes 1 through 9 using boundaries
0.3, 1, 2.2, 5, 10, 20, 33, 50, and 75. Access mixes text and numeric return
values in one implicit `Variant`.

`vpRoundUp2` returns locale-formatted text with two decimal places for values at
least 0.01, but numeric 0.01 for smaller values. Its comments incorrectly refer
to 0.1 and one decimal place. `vpRoundDown1` is a cap at 100 rather than a
rounding operation.

## Package API

- `vpro_presence_class()` returns Roman-numeral presence classes.
- `vpro_presence_class_numeric()` returns the Access character-number labels.
- `vpro_prominence_class()` and `vpro_goldstream_class()` return classes or raw
  scores through an explicit `return_score` argument, replacing global report
  state.
- `vpro_significance_class()` returns one stable character type.
- `vpro_round_minimum()` provides the documented minimum-and-rounding operation
  as stable numeric data with explicit digits and minimum arguments.
- `vpro_cap_percent()` preserves the Access cap-at-100 behavior.

All APIs are vectorized, require finite numeric values or missing values, and
represent unset or invalid Access results as typed `NA`. Classification scores
use R double precision rather than VBA `Single` intermediates. The package does
not reproduce modal error messages, locale-sensitive numeric strings, implicit
VBA coercion, or mixed branch return types.
