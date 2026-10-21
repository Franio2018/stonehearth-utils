# Stonehearth Utils

Mods and tools from an investigation into why a grown, modded Stonehearth town
(ACE and others) lags harder and harder and then crashes about an hour into a
session.

## Mods

| Mod | What it does |
|-----|--------------|
| [trace_leak_fix](trace_leak_fix/) | **The fix.** Patches a UI memory leak in vanilla `RadiantTrace` that piles up duplicate traces of the same entities until the UI process runs out of memory. Works with vanilla and ACE. Details and measurements in [its README](trace_leak_fix/README.md). |
| [memory_probe](memory_probe/) | Diagnostic. Logs Lua memory and frame stalls on server and client once a minute to `stonehearth.log`. |
| [storage_throttle](storage_throttle/) | Experimental, needs ACE. Coalesces public storage updates to at most one every 2 s. Measurements showed little effect, so it is kept only for reference. |

Install a mod by copying its folder into `Stonehearth/mods/` (or use
`dist/trace_leak_fix.smod`) and enabling it in the game's mod list. When you
load an existing save, choose "Apply Mod Changes", then "Continue".

## Measurements

`logs/2026-10-20_afk_4h_trace_fix/` holds the per-minute measurements from a
4-hour AFK run with the fix and from a run without it (memory of the main and UI
processes, trace counts, a UI allocation profile). Raw game logs are not
included.

## Reporting

[trace_leak_fix/REPORT_for_ACE.md](trace_leak_fix/REPORT_for_ACE.md) is the bug
report sent to the ACE developers.
