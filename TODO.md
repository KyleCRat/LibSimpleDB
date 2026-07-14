# LibSimpleDB-2.0 Rewrite TODO

## Goal

Make LibSimpleDB a standalone, reusable WoW SavedVariables library that is:

- Flexible and easy to use across addons.
- Safe for frequent reads in combat-sensitive code.
- Predictable about defaults, resets, callbacks, and mutable tables.
- Correct when multiple addons embed different LibStub minor versions or the
  `1.0` and `2.0` API families together during migration.
- Distributed through a reproducible process instead of manual folder copies.

WoW currently uses Interface `120007` and Lua 5.1. Do not use `goto`,
`continue`, later-Lua operators, or assumptions that conflict with Lua 5.1.

## Current State

- Legacy library major/minor: `LibSimpleDB-1.0`, minor `2`.
- Target library major/minor: `LibSimpleDB-2.0`, minor `1`.
- The repository is initialized as `LibSimpleDB` with `main` pushed to origin.
- Commit `4a07ad4` preserves the legacy source and is tagged `1.0.0`.
- The current checkout folder remains `LibSimpleDB-1.0` temporarily and will be
  renamed to `LibSimpleDB` after active work in this path is complete.
- The working tree now replaces the legacy root file with
  `LibSimpleDB-2.0.lua`, updates `embed.xml`, and adds API documentation, tests,
  benchmarks, license, and project metadata. These rewrite changes are not yet
  committed or tagged.
- Identical embedded copies currently exist in:
  - `LootLevel`
  - `PhasedCombatTimer`
  - `RPGBossBar`
  - `YvBags`
- `YvBags` creates account-wide and per-character database instances and uses
  path callbacks.
- `RPGBossBar` has many nested reads; its boss power event path currently makes
  several `Get()` calls per event.
- `PhasedCombatTimer` caches display settings to keep database reads out of its
  10 Hz timer path.
- `LootLevel` currently embeds the library but does not appear to consume it.

## Versioning and Repository Decisions

- Keep the Git repository name and eventual checkout root unversioned:
  `LibSimpleDB`.
- Keep the repository root flat. Do not add side-by-side
  `LibSimpleDB-1.0/` and `LibSimpleDB-2.0/` source directories on `main`.
- Preserve the legacy implementation through Git tag `1.0.0`. Create a `1.x`
  maintenance branch from that tag only if a legacy fix is ever required.
- The rewrite replaces the root implementation file with
  `LibSimpleDB-2.0.lua` and updates `embed.xml` accordingly.
- Use the LibStub declaration `"LibSimpleDB-2.0", 1` for the first rewrite
  release. Treat the LibStub MAJOR as the opaque public API family and MINOR as
  a monotonically increasing implementation/release counter within that family.
- Tag library releases with unprefixed SemVer. The first reviewed rewrite is
  `2.0.0`; compatible fixes/features use `2.0.1`, `2.1.0`, and so on while the
  LibStub family remains `LibSimpleDB-2.0` and its numeric MINOR keeps rising.
- Record WoW client compatibility separately in metadata, tests, and release
  notes. Do not use the WoW-patch addon release scheme for library Git tags.
- A breaking future API becomes a new family such as `LibSimpleDB-3.0` and Git
  tag `3.0.0`.
- Consumers will pin a reviewed Git tag into a versioned destination such as
  `Libs/LibSimpleDB-2.0`. The repository name does not determine that embedded
  destination.

## Resolved 2.0 Contracts

- `Set(..., nil)` errors without modifying data. `Delete()` and `ResetPath()`
  explicitly remove raw overrides and fall back to defaults.
- Values recursively equal to current defaults are normalized by removing the
  raw override and pruning empty raw ancestors.
- Path callbacks report effective new and old values and fire only for a real
  effective change.
- Path callbacks use typed exact/tree registrations instead of dotted strings.
  Tree callbacks may register at the root to observe all path changes.
- Callback dispatch snapshots registrations before invocation. Mutations apply
  to the next dispatch, and errors are reported without stopping later
  callbacks.
- `Reset()`, `SetData()`, and `RegisterDefaults()` fire lifecycle callbacks only;
  they do not synthesize per-path callbacks for bulk changes.
- Constructor defaults, registered defaults, and table values passed to `Set()`
  are copied. Normal table reads are read-only internal references; `GetCopy()`
  is the supported edit-and-commit workflow.
- Paths accept string and non-NaN numeric keys. Stored tables must be plain,
  acyclic SavedVariables-compatible values with string/numeric keys.
- Later `RegisterDefaults()` calls overwrite conflicting registered defaults and
  preserve non-conflicting keys.
- Colors require numeric `r`, `g`, `b`, and `a` components in the inclusive
  range 0 through 1; malformed reads fall back to opaque white.
- Source and project files use four-space indentation and never tabs.

## Current Verification Blocker

- Install a trusted Lua 5.1 runtime on `PATH`; do not download or vendor an
  unreviewed binary as part of this repository.
- Run `lua tests/run.lua` and resolve every failure.
- Run `lua benchmarks/run.lua`, record results for the `1.0.0` tag and the `2.0`
  rewrite under the same runtime, and review allocation/CPU differences.
- Do not commit/tag `2.0.0` or update consumers until the tests and benchmarks
  have run successfully and the standalone changes are reviewed.
- No automated workflow has been added yet. Choose and review a trusted Lua 5.1
  installation source before adding local or hosted CI runtime setup.

## Confirmed Review Findings

### Allocation and Runtime Performance

- `Get()`, `GetRaw()`, `GetDefault()`, `Set()`, `Delete()`, `SetDefault()`,
  `IsModified()`, `Toggle()`, `GetColorDefault()`, and `SetColor()` collect
  varargs into temporary tables.
- `GetColor()` inherits the allocation behavior of `Get()` and is also a read
  path that should remain allocation-free.
- Vararg arity is currently derived from the length of a temporary table.
  Trailing `nil` arguments are therefore unsafe: for example,
  `Set("a", "b", nil)` can be misread as `Set("a", "b")` and write to the
  wrong path. Use `select("#", ...)` to preserve arity and explicitly reject a
  nil value or define it as deletion. Prefer rejection because `Delete()` is
  already explicit.
- `Toggle()` creates a path table and then calls `Get()`, which creates another
  path table.
- Every write builds a dotted callback path, including when no callbacks are
  registered.
- `buildDotPath()` allocates a parts table and the resulting string.
- `IsModified()` recursively compares an entire table subtree when called on a
  parent path; this cost should be documented and benchmarked.
- The constructor deep-copies the complete defaults tree for every instance and
  copies every method directly onto every instance.

### LibStub Upgrade Behavior

- Database methods are copied onto instances at construction time.
- If an older embedded minor creates an instance before a newer minor loads,
  that existing instance retains the old copied methods.
- Move methods to a stable prototype owned by the LibStub library table and use
  metatable-backed instances. Ensure the prototype is updated in place across
  minor upgrades.
- Store both the prototype and its metatable on the persistent LibStub library
  table. Reusing only a newly created local methods table will not upgrade
  existing instances.
- Do not attempt to upgrade `LibSimpleDB-1.0` instances into `2.0` instances in
  place. They belong to separate LibStub families and may coexist during the
  consumer migration.
- Require reliable live minor upgrades for instances created by
  `LibSimpleDB-2.0`. Store and update its prototype in place from its first
  release so the copied-method problem does not recur within the `2.0` family.
- Define how removed or renamed prototype methods are handled on later minor
  upgrades so stale prototype entries do not survive indefinitely.

### Defaults and Reset Semantics

- `SetDefault()` deep-copies the current default into SavedVariables as an
  explicit override.
- This bloats saved data and prevents later default changes from reaching users.
- Define a path-reset operation that deletes the raw override and falls back to
  the current default. The `2.0` rewrite may remove, rename, or redefine
  `SetDefault()` as needed for a coherent API.
- `Delete()` currently reports callback `newValue` as `nil`, even when the
  effective value becomes a default. Define whether callbacks report raw or
  effective values and make all write methods consistent.
- The same raw-versus-effective issue applies to `oldValue` from `Set()`,
  `SetDefault()`, `Toggle()`, and `SetColor()`, not only to `Delete()`.
- Define whether later `RegisterDefaults()` calls replace existing registered
  defaults or only fill missing values. The current deep merge replaces scalar
  values and wrong-shaped subtrees.
- Define whether `ResetPath()` prunes empty raw ancestor tables after deleting
  the leaf. Prefer pruning so resets do not leave empty SavedVariables trees.
- Define how whole-database `Reset()` relates to path callbacks: lifecycle event
  only, per-path callbacks, or one explicit database-level change notification.

### Table and Callback Contracts

- `Get()` returns internal raw/default table references. Mutating a fallback
  table can silently alter instance defaults without saving data or firing a
  callback.
- `Set()` stores caller-owned tables directly. Mutating the input table after
  `Set()` changes SavedVariables without another library call or callback.
- Define table ownership in both directions: whether reads are read-only,
  whether `Set()` copies or takes ownership, and whether an explicit copy API is
  needed. State that direct mutations through a mutable accessor cannot produce
  callbacks unless the mutation is committed through another library method.
- Keep normal reads fast; do not solve this by blindly deep-copying every table
  read. Document table values as read-only or add an explicit mutable accessor
  such as `GetMutable()`/`EnsureTable()`.
- Define unchanged writes for every mutator. Current behavior is inconsistent:
  `Set()` fires for the same value, while `Delete()` fires for a missing leaf
  only when its raw parent exists.
- Callback errors currently stop later callbacks.
- Registering or unregistering callbacks while dispatch is iterating needs a
  defined behavior.
- Dotted callback paths are ambiguous when a real key contains a dot.
- Stringification also makes numeric key `1` collide with string key `"1"`.
  Either restrict callback-compatible keys to dot-free strings or add a
  structured-path callback API. The `2.0` rewrite does not need to retain the
  dotted callback API, but its replacement must have a clear consumer migration
  path.
- Apply error isolation and mutation-during-dispatch rules to lifecycle events
  as well as path callbacks. Define callback ordering as unspecified unless an
  ordered registry is intentionally implemented.
- `SetColor()` currently reports the caller's color table as callback
  `newValue`, even when the stored table is a different table. Include color
  writes in the same ownership and callback-value contract.
- Define the supported data model. SavedVariables should normally be plain,
  acyclic tables with serializable key/value types; current deep-copy and
  deep-equality helpers do not handle cycles or preserve metatables.
- Consider `UnregisterAllCallbacks()` and clearer naming for the internal
  lifecycle event API so it is not confused with WoW frame events.

## Proposed Work Sequence

### 1. Establish Tests and Benchmarks

- [x] Add a lightweight Lua 5.1-compatible test harness.
- [x] Capture current minor-2 behavior as a migration reference, not as a contract
  the `2.0` rewrite must preserve.
- [x] Benchmark one-key and four-key reads, raw reads, default fallbacks, writes with
  no callbacks, writes with exact callbacks, and wildcard callback dispatch.
- [x] Benchmark `GetDefault()`, both color read helpers, parent-path `IsModified()`,
  constructor cost for large defaults trees, and multiple instances sharing the
  same source defaults.
- [x] Track both elapsed CPU time and allocation/garbage behavior where the runtime
  permits it.
- [x] Define a repeatable benchmark method: warm up first, control or stop garbage
  collection during measurement, use fixed iteration counts, and document the
  timing/allocation source for stock Lua and the WoW client.
- [ ] Install a reviewed, trusted Lua 5.1 runtime on the developer `PATH` and
  decide whether to add equivalent hosted CI setup.

### 2. Define the 2.0 API Contracts

- [x] Treat the release boundary as decided: this is a complete
  `LibSimpleDB-2.0` rewrite with Git release `2.0.0`. Preserve a `1.0` behavior
  only when it remains a good contract or materially simplifies consumer
  migration.
- [x] Require `Set(..., nil)` to error without modifying data. Require callers to
  use `Delete()` explicitly for deletion.
- [x] Define effective callback values, unchanged-write behavior, dispatch
  mutation/error behavior, and lifecycle notification behavior.
- [x] Define table ownership for constructor defaults, `RegisterDefaults()`,
  `Set()`, reads, and `GetCopy()`.
- [x] Replace ambiguous dotted paths with typed structured callback paths.
- [x] Specify `ResetPath()`, ancestor pruning, whole reset, and `SetData()` behavior.
- [x] Write these decisions as tests and API documentation before optimizing the
  implementation.

### 3. Implement the 2.0 Rewrite

- [x] Replace temporary path tables with allocation-free vararg traversal using
  `select()` or specialized helpers.
- [x] Add direct fast paths for one-key reads.
- [x] Avoid building callback path data when the callback registry is empty.
- [x] Avoid duplicate traversal/allocation in `Toggle()` and color helpers.
- [x] Replace per-instance method copies with a stable metatable prototype.
- [x] Build later minor methods separately and replace the persistent prototype
  only after method construction succeeds.
- [x] Design the stable prototype for reliable future `2.0` minor upgrades; no
  `1.0` instance upgrade operation is required.
- [x] Reuse existing public method names only where they fit the reviewed `2.0`
  contracts. Remove compatibility behavior that would compromise the new API.
- [x] Change the LibStub identity to `"LibSimpleDB-2.0", 1`, rename the source file
  to `LibSimpleDB-2.0.lua`, and update `embed.xml`.

### 4. Complete the Standalone Project

- [x] Continue from the initialized `LibSimpleDB` repository and preserved `1.0.0`
  baseline tag.
- [x] Add README/API documentation, MIT license, changelog, tests, and benchmarks.
- [x] Add embedded load metadata and document why no standalone TOC is required.
- [x] Specify how LibStub is loaded or embedded before `LibSimpleDB-2.0.lua` in
  both standalone and embedded packages, and test that load order directly.
- [x] Choose packager-managed Git externals and self-contained consumer release
  packages rather than a separately enabled library addon.
- [x] Document how consumer addons pin and update a tagged library version.
- [x] Keep release source flat at the repository root. Let consumer dependency
  configuration choose the versioned embedded destination.
- [ ] Run tests and benchmarks, review results, commit the rewrite, and create
  annotated tag `2.0.0`.

### 5. Update Consumers Together

Deferred by current scope. Do not begin this section until the standalone
`2.0.0` release has passed verification and been reviewed.

- Validate `LootLevel`, `PhasedCombatTimer`, `RPGBossBar`, and `YvBags` against
  the reviewed standalone version.
- Remove the unused `LootLevel` embed if it remains unused.
- Replace manual source copies with the chosen reproducible dependency process.
- Pin all migrated consumers to the reviewed `2.0.0` tag or its exact release
  commit.
- Test mixed-addon load order with different `2.0` minors and with legacy `1.0`
  and rewritten `2.0` families present together.

## Required Test Matrix

- Raw value, default fallback, `false`, `0`, empty string, and missing values.
- Trailing nil values, nil intermediate keys, and explicit rejection of
  `Set(..., nil)` without modifying data or writing to the wrong path.
- One-level and deeply nested string/numeric paths.
- Nested writes where an intermediate raw value is a scalar.
- `GetRaw()`, `Set()`, `Delete()`, `Toggle()`, reset, and profile `SetData()`.
- Table aliasing after `Set()`, table references returned by reads, mutable-table
  access, and callback behavior for mutations made through each supported path.
- Default registration, repeated registration conflicts, and nested default
  merges.
- Color get/set/default behavior and malformed saved color tables.
- Exact callbacks, wildcard callbacks, no callbacks, callback removal during
  dispatch, and callback errors.
- Callback addition during dispatch, duplicate registration, no-op writes,
  missing-leaf deletion with present/missing parents, lifecycle callback errors
  and mutation, wildcard root matching, dotted keys, and numeric/string key
  collisions.
- Old-minor/new-minor `LibSimpleDB-2.0` load order before and after instances are
  created.
- In-place prototype updates across at least two simulated `2.0` minors.
- Legacy `LibSimpleDB-1.0` and rewritten `LibSimpleDB-2.0` loading in both
  orders, with independent instances and no cross-family replacement.
- Multiple instances with large defaults trees.
- SavedVariables output after resetting individual paths and the whole DB.
- Empty-parent pruning after path resets and lifecycle/path notifications after
  path reset, whole reset, and `SetData()`.

## Definition of Done

- Hot-path `Get()`, `GetRaw()`, `GetDefault()`, `GetColor()`, and
  `GetColorDefault()` perform no temporary table allocations.
- Writes with no callbacks do not build callback path strings.
- Trailing nil arguments cannot silently change the requested write path.
- Instances created by the metatable-based implementation update through the
  stable prototype across later `LibSimpleDB-2.0` minor upgrades.
- `LibSimpleDB-1.0` and `LibSimpleDB-2.0` coexist without replacing or mutating
  each other's library tables or instances.
- Reset/default, callback, path-key, supported-data, and table ownership
  contracts are documented and tested.
- Benchmarks demonstrate the expected improvement without behavior regressions.
- The standalone rewrite is tagged `2.0.0`, and all four consumer addons load
  and pass focused smoke tests using that same pinned release.
