# Performance Verification

This document records the Lua 5.1 performance review for the unreleased
`LibSimpleDB-2.0`, minor `1`, against the tagged `1.0.0` implementation
(`LibSimpleDB-1.0`, minor `2`).

## Reproducing the Benchmarks

Run commands from the repository root with stock Lua 5.1:

```powershell
lua benchmarks/run.lua
lua benchmarks/compare.lua
```

Both commands default to 250,000 primary iterations and three independent runs.
Override those values with positional arguments:

```powershell
lua benchmarks/compare.lua 500000 5
lua benchmarks/compare.lua 250000 3 enabled
```

The optional third argument selects `stopped` or `enabled` garbage collection.
Stopped mode is the default and reports cumulative allocation. Enabled mode
includes collector CPU cost and reports only the retained-memory delta observed
at the end of each operation.

`benchmarks/compare.lua` loads the legacy implementation directly from Git with
`git show 1.0.0:LibSimpleDB-1.0.lua`. It then runs both API families through the
same benchmark suite and adapters for their differing callback APIs. No legacy
source copy or generated benchmark file is required.

Each operation warms up first, performs a full collection, stops garbage
collection during measurement, and records:

- CPU time from `os.clock()`.
- Cumulative allocation from `collectgarbage("count")` while collection is
  stopped.
- The median of all requested runs.

The callback allocation numbers are cumulative allocations, not retained
memory. For example, 39,062.5 KiB across 250,000 writes is 160 bytes per changed
write.

## Reviewed Results

The following medians were recorded on 2026-07-14 with stock Lua 5.1.5 on
Windows. Primary operations used 250,000 iterations, `IsModified()` used 1,000,
and construction used 100.

| Operation | 1.0 CPU | 2.0 CPU | CPU change | Allocation KiB, 1.0 to 2.0 |
|---|---:|---:|---:|---:|
| Get one raw key | 0.054 s | 0.040 s | -25.9% | 19,531.250 to 0 |
| Get four raw keys | 0.106 s | 0.162 s | +52.8% | 31,250.000 to 0 |
| Get default fallback | 0.081 s | 0.049 s | -39.5% | 19,531.250 to 0 |
| GetRaw four keys | 0.107 s | 0.162 s | +51.4% | 31,250.000 to 0 |
| GetDefault four keys | 0.105 s | 0.156 s | +48.6% | 31,250.000 to 0 |
| GetColor default | 0.114 s | 0.133 s | +16.7% | 19,531.250 to 0 |
| GetColorDefault | 0.078 s | 0.139 s | +78.2% | 19,531.250 to 0 |
| Set, no callbacks | 0.124 s | 0.248 s | +100.0% | 42,968.750 to 0 |
| Set, exact callback | 0.146 s | 0.369 s | +152.7% | 42,968.750 to 39,062.500 |
| Set, wildcard/root tree callback | 0.165 s | 0.368 s | +123.0% | 42,968.750 to 39,062.500 |
| IsModified large parent | 0.230 s | 0.231 s | +0.4% | 78.125 to 0 |
| Construct large defaults | 0.018 s | 0.031 s | +72.2% | 6,700.781 to 6,628.906 |

Supplemental runs with garbage collection enabled produced the same CPU trend.
Collection overhead did not offset the deep-read and write regressions.

## Combined Traversal Optimization

The working tree validates path keys while performing its first read-only
traversal. Default fallback replays the already-validated path. Mutating methods
retain complete pre-validation so invalid writes cannot partially modify data.

Compared with the preceding 2.0 implementation, this reduced median CPU time as
follows while preserving zero allocation:

| Operation | Before | After | Improvement |
|---|---:|---:|---:|
| Get four raw keys | 0.187 s | 0.162 s | 13.4% |
| GetRaw four keys | 0.183 s | 0.162 s | 11.5% |
| GetDefault four keys | 0.182 s | 0.156 s | 14.3% |
| GetColor default | 0.184 s | 0.133 s | 27.7% |
| GetColorDefault | 0.155 s | 0.139 s | 10.3% |

## Interpretation

The explicit allocation goals pass:

- `Get()`, `GetRaw()`, `GetDefault()`, `GetColor()`, and `GetColorDefault()`
  allocate no temporary memory in the measured paths.
- Writes with no callbacks allocate no temporary memory and do not construct
  callback path strings.
- Callback writes allocate about 160 bytes per changed write for the structured
  path and dispatch snapshots, down from about 176 bytes per legacy write.
- Large-parent `IsModified()` no longer allocates a temporary vararg table.

CPU results are mixed. One-key reads and default fallback improve. Deep reads
remain roughly 49% to 53% slower after the combined traversal optimization,
callback-free writes are about twice as slow, and callback writes are more than
twice as slow. These operations remain below two microseconds per call in this
runtime, but the regression is relevant to addons that perform many nested
reads per event.

The documented release criterion that benchmarks demonstrate the expected
improvement is therefore only partially satisfied. Before tagging `2.0.0`, the
project must either:

1. Continue optimizing common fixed-depth vararg extraction and strict color
   validation, then rerun the comparison; or
2. Explicitly accept and document the CPU-for-allocation tradeoff based on
   focused consumer smoke tests in the WoW client.

## Remaining Verification

- Smoke-test `LootLevel`, `PhasedCombatTimer`, `RPGBossBar`, and `YvBags` with
  the release candidate and real embedded LibStub copies.
- Run `lua tests/tagged-compat.lua` to verify the actual tagged legacy source and
  working-tree rewrite in both load orders.
- Record new benchmark results here whenever a performance-sensitive
  implementation change alters the comparison materially.
