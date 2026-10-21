# UI memory leak in RadiantTrace: grandchild traces are never destroyed

## Summary

`RadiantTrace._expand_uri` (`radiant/js/radiant/trace.js`, vanilla, not
overridden by ACE) destroys only the direct child traces when a traced object
updates. Deeper traces are orphaned: they stay registered in their `Tracer`,
keep receiving progress and keep re-expanding. Long-lived views accumulate
duplicate traces of the same entities without bound. This explains the common
"game lags more and more, then crashes after about an hour" reports in grown
towns.

## Evidence

Measured over the DevTools protocol (`127.0.0.1:1338`) on a 25-citizen ACE town,
game left AFK at 1x, nothing clicked:

- `radiant._tracerMap['object://game/<citizen>']._traces.length` went from 101
  to 175 within about 10 minutes and kept climbing.
- A sampling heap profile (allocations still alive after a forced GC, 5 min
  window): 108 MB, dominated by `$.Deferred` / `$.Callbacks` created from
  `_expand_uri` and `_expand_object_properties` in `trace.js`.
- The CEF renderer grew about 35 MB/min (540 MB -> 2.1 GB) and died after 43
  minutes with `0xe0000008` in `KERNELBASE.dll` (Chromium OOM). The simulation
  kept running without a UI.

With the fix below, the same save and setup ran 4 hours with at most 5 traces
per entity, total trace count flat (1200 -> 1092) and the UI process at
600-750 MB for the first 3 hours.

## Cause

```js
var trace = radiant.trace(uri)
   .progress(function (json) {
      if (json) {
         var tracesToDelete = previousTraces;
         [childDeferred, previousTraces] = self._expand_object(json, properties, ...);
         ...
         radiant.each(tracesToDelete, function (_, t) {
            delete self._traces[t.get_id()];
            t.destroy();   // <- removes only this trace; the traces that ITS
                           //    progress callback created stay installed
         });
      }
   })
```

`previousTraces` holds only the traces created directly by this expansion. The
traces each of them created in turn live in their own closures, and nothing
ever destroys them. `RadiantTrace.destroy()` does clean everything up through
`this._traces`, so short-lived views are fine. Views that live all session never
call it.

A second, smaller problem: a trace removed during `Tracer._protectTraceList` is
only queued in `_dead_traces`, so it still receives the current update and
re-expands, installing new child traces nobody owns.

## Fix

The full fix (UI-only, about 80 lines, works on vanilla and ACE) patches
`RadiantTrace.prototype`:

```js
proto._destroyTraceTree = function (t) {
   var self = this;
   t._tlf_dead = true;
   delete self._traces[t.get_id()];
   t.destroy();
   var children = t._tlf_children;
   t._tlf_children = null;
   radiant.each(children, function (_, c) { self._destroyTraceTree(c); });
};

// in _expand_uri's progress callback:
if (trace._tlf_dead || self._destroyed) {
   return;
}
...
[childDeferred, previousTraces] = self._expand_object(json, properties, ...);
trace._tlf_children = previousTraces;
...
radiant.each(tracesToDelete, function (_, t) { self._destroyTraceTree(t); });
```

`_destroyAllTraces` also marks every trace dead before destroying it. The
complete file is `ui/trace_leak_fix.js` in the attached mod. Merging it into
`trace.js` directly would be the cleanest option.

## Not fixed yet

After about 3 hours the UI's JS heap grows again (391 -> 670 MB) while trace,
view and DOM counts stay flat, so there is a second, unrelated source. The main
process's native memory also grows steadily (about 22 MB/min).
