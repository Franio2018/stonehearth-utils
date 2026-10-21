# Trace Leak Fix

Fixes a memory leak in Stonehearth's UI that makes long sessions lag harder and
harder until the UI (or the whole game) crashes, usually after 45-60 minutes in
a grown town.

Works with vanilla and with ACE. UI-only: it changes no game data and is safe
to add to or remove from an existing save.

## The bug

The UI keeps itself up to date through `RadiantTrace`
(`radiant/js/radiant/trace.js`). A trace of an object also traces the objects
it references, which can trace their own references, and so on.

When a traced object changes, `_expand_uri` re-expands it and destroys the
previous child traces. It destroys only the **direct** children, though. Their
children (grandchildren and deeper) are never destroyed. They stay installed,
keep receiving updates from the game and keep re-expanding their own subtrees.

Views that stay open for the whole session (unit frame, town, bulletins, ...)
therefore pile up duplicate traces of the same entities:

- every update fires more and more callbacks, so the UI gets slower over time;
- every leaked trace keeps its jQuery Deferreds and Ember objects alive, so the
  UI process grows until Chromium runs out of memory (crash `0xe0000008` in
  `KERNELBASE.dll`, UI goes unresponsive while the simulation keeps running);
- the game keeps sending updates for every trace that was never uninstalled.

## The fix

Each trace remembers the traces created while expanding it. When a trace is
replaced or destroyed, its whole subtree is destroyed with it. A trace that is
removed while its tracer is still notifying no longer re-expands (that would
install traces nobody owns).

## Measurements (one modded town, 25 citizens, game left AFK at 1x)

|                                | without fix            | with fix          |
|--------------------------------|------------------------|-------------------|
| traces of one citizen          | 101 -> 175 in ~10 min  | 5, flat for 4 h   |
| all traces                     | growing                | 1200 -> 1092      |
| UI process memory              | 540 MB -> 2.1 GB, crash at 43 min | 600-750 MB for 3 h |
| session length                 | UI crash after 43 min  | 4 h, still responsive |

After about 3 hours the UI's JS heap starts growing again from a second,
smaller source that this mod does not address yet.
