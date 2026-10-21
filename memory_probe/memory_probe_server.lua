memory_probe = {}

-- Fires after radiant's own 'radiant:init' handler has created the realtime clock.
radiant.events.listen(memory_probe, 'radiant:init', function()
      require('memory_probe.probe').start('server')
   end)

return memory_probe
