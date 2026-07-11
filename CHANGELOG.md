# LibSimpleDB-1.0 Changelog

This changelog tracks changes by LibStub minor version.

## Minor 2

- Replaced non-table intermediate values with tables when writing nested paths.
  This prevents writes like `db:Set("power", "border", "texture", value)` from
  failing if `power.border` already contains a scalar value.
- Applied the same nested-path overwrite behavior to `SetDefault()`, `Toggle()`,
  and `SetColor()` through the shared path-creation helper.
- Updated `SetColor()` to replace wrong-shaped existing data with a valid color
  table instead of mutating arbitrary tables in place.

## Minor 1

- Initial embedded library version.
- Added defaults fallback, nested get/set helpers, reset support, callbacks,
  lifecycle events, color helpers, and default registration.
