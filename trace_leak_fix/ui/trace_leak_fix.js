// Trace Leak Fix
//
// RadiantTrace (radiant/js/radiant/trace.js) expands a uri into a tree of
// traces. Each time a traced object changes, its children are re-expanded and
// the old child traces are destroyed - but only the direct children. Their own
// children (grandchildren and deeper) are never destroyed, so they stay
// installed, keep receiving updates and keep re-expanding forever. A view that
// is open all session (unit frame, town, bulletins...) therefore piles up
// duplicate traces of the same entities: memory in the UI process grows until
// it runs out, and every update fires more and more callbacks.
//
// This makes each trace own the traces created while expanding it, and
// destroys the whole subtree when the trace is replaced or destroyed.
(function () {
   if (!window.RadiantTrace || RadiantTrace.prototype._trace_leak_fix) {
      return;
   }
   var proto = RadiantTrace.prototype;
   proto._trace_leak_fix = true;

   proto._destroyTraceTree = function (t) {
      var self = this;
      t._tlf_dead = true;
      delete self._traces[t.get_id()];
      t.destroy();
      var children = t._tlf_children;
      t._tlf_children = null;
      radiant.each(children, function (_, c) {
         self._destroyTraceTree(c);
      });
   };

   proto._destroyAllTraces = function () {
      $.each(this._traces, function (i, trace) {
         trace._tlf_dead = true;
         trace.destroy();
      });
      this._top_deferred = null;
      this._traces = {};
   };

   proto._expand_uri = function (uri, properties, level) {
      var self = this;
      var previousTraces, childDeferred;
      var deferred = $.Deferred();
      var trace = radiant.trace(uri);
      trace
         .progress(function (json) {
            // A trace removed while its tracer is notifying still gets this
            // update; expanding it would install traces nobody owns.
            if (trace._tlf_dead || self._destroyed) {
               return;
            }
            if (json) {
               var tracesToDelete = previousTraces;
               [childDeferred, previousTraces] = self._expand_object(json, properties, level != undefined ? level + 1 : 0);
               trace._tlf_children = previousTraces;
               childDeferred
                  .progress(function (eobj) {
                     deferred.notify(eobj);
                  })
                  .fail(function (o) {
                     deferred.reject(o);
                  });
               radiant.each(tracesToDelete, function (_, t) {  // Must be after, to avoid uninstalling traces that we may just reinstall immediately.
                  self._destroyTraceTree(t);
               });
            } else {
               deferred.notify(null);
            }
         })
         .fail(function (o) {
            deferred.reject(o);
         });
      self._traces[trace.get_id()] = trace;
      return [deferred, [trace]];
   };

   console.log('trace_leak_fix: RadiantTrace patched');
})();
