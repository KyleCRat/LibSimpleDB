# LibSimpleDB-2.0 Release TODO

## Current Status

- API family: `LibSimpleDB-2.0`, LibStub minor `1`.
- Latest released tag: `1.0.0` for the legacy `LibSimpleDB-1.0` family.
- `2.0.0` is implemented but remains unreleased.
- The Lua 5.1 tests, tagged-family compatibility tests, syntax checks, and
  repeatable 1.0-versus-2.0 benchmarks are available and passing.
- Current read and write performance is accepted for the initial 2.0 release.
- Hosted CI/CD is intentionally not planned. Run the complete Lua 5.1
  verification suite locally before pushing release changes or tags to GitHub.
- `LibSimpleDBProfiles-1.0` is implemented and awaiting integration and release
  verification with YvBags.
- YvBags will be the release-candidate smoke test for both libraries.

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
