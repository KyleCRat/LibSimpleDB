# LibSimpleDB-2.0 Release TODO

## Current Status

- API family: `LibSimpleDB-2.0`, LibStub minor `1`.
- Latest released tag: `1.0.0` for the legacy `LibSimpleDB-1.0` family.
- `2.0.0` is implemented but remains unreleased.
- The Lua 5.1 tests, tagged-family compatibility tests, syntax checks, and
  repeatable 1.0-versus-2.0 benchmarks are available and passing.
- Current read and write performance is accepted for the initial 2.0 release.
- `LibSimpleDBProfiles-1.0` is planned in the sibling
  `LibSimpleDBProfiles/PLAN.md` file but is not implemented.
- YvBags will be the release-candidate smoke test for both libraries.

## Finalize LibSimpleDB

- [ ] Commit the current `Set(..., nil)` reset behavior, tests, API contract,
  changelog, and migration guide after final document review.
- [ ] Update stale pre-verification status in `README.md` and `Performance.md` to
  record the accepted benchmark conclusion and YvBags-only smoke-test scope.
- [ ] Review `MIGRATION.md` end to end against the final 2.0 implementation.
- [ ] Decide whether hosted Lua 5.1 CI is required for `2.0.0` or explicitly
  defer it as post-release infrastructure.

## Build LibSimpleDBProfiles

- [ ] Implement `LibSimpleDBProfiles-1.0` from
  `../LibSimpleDBProfiles/PLAN.md` against the reviewed core release candidate.
- [ ] Add Lua 5.1 tests for storage initialization, scope selection, named
  profiles, copy/rename/delete/reset operations, lifecycle callbacks, and
  switching the active LibSimpleDB data root.
- [ ] Verify that profile selection happens outside hot-path reads so consumers
  continue calling core database methods without `global` or profile-name path
  prefixes.
- [ ] Prepare its API documentation, migration guidance, changelog, embedding
  metadata, and reproducible consumer pin.

## Smoke-Test YvBags

- [ ] Update YvBags to use the reviewed `LibSimpleDB-2.0` and
  `LibSimpleDBProfiles-1.0` candidate commits.
- [ ] Validate account-wide, per-character, profile-selection,
  profile-switching, path-callback, lifecycle-refresh, and reload-persistence
  behavior.
- [ ] Load YvBags with real embedded LibStub copies while other installed addons
  provide `LibSimpleDB-1.0`; confirm both API families coexist without
  replacement or mutation.
- [ ] Confirm YvBags does not mutate tables returned by normal reads and does not
  depend on LibSimpleDB instance internals.

## Final Verification And Release

- [ ] Run `luac -p LibSimpleDB-2.0.lua` with stock Lua 5.1.
- [ ] Run `lua tests/run.lua` and `lua tests/tagged-compat.lua`.
- [ ] Run `lua benchmarks/run.lua` and `lua benchmarks/compare.lua`; confirm the
  results remain consistent with the accepted `Performance.md` conclusion.
- [ ] Review the final diff and confirm only intended source, tests, benchmark,
  and documentation changes are included.
- [ ] Commit and push the reviewed LibSimpleDB release candidate.
- [ ] Create and push the annotated `2.0.0` tag.
- [ ] Release LibSimpleDBProfiles with Git tag `1.0.0` only after the core
  `2.0.0` tag exists.
- [ ] Replace YvBags candidate pins with the final library tags and repeat its
  focused smoke test.

## Deferred Consumers

These migrations do not block `LibSimpleDB-2.0`:

- [ ] Validate and migrate PhasedCombatTimer later.
- [ ] Validate and migrate RPGBossBar later.
- [ ] Reassess LootLevel later and remove its unused embed if it remains unused.
- [ ] Replace each deferred consumer's manual library copy with the reviewed
  dependency process when that consumer is migrated.
