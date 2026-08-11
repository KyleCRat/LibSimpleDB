# Changelog

## 2.0.0 - 2026-08-10

- Rewrote the library as the separate `LibSimpleDB-2.0` API family.
- Added allocation-free effective, raw, default, and color read paths.
- Added stable metatable-backed instances that update through a persistent
  LibStub-owned prototype across later `2.0` minors.
- Added explicit reset normalization and empty-parent pruning.
- Added copied table writes and `GetCopy()` for callback-safe table editing.
- Replaced dotted callback paths with typed exact and tree callbacks.
- Defined effective-value, unchanged-write, dispatch snapshot, and callback
  error-isolation behavior.
- Replaced frame-like lifecycle event names with explicit lifecycle callbacks.
- Added strict path, color, and SavedVariables value validation, with nil final
  `Set()` values defined as path resets.
- Added a dependency-free Lua 5.1 test harness and reproducible benchmarks.

## 1.0.0 - 2026-07-11

- Preserved the legacy `LibSimpleDB-1.0`, minor 2 implementation as the
  standalone repository baseline.
