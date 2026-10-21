-- Storage Throttle
--
-- ACE re-sends a storage's whole item tracker to the client on every single
-- item added or removed. For public storage (stockpiles, chests) that happens
-- even with ACE's "Limit Network Data" setting, because
-- AceStorageComponent:_consider_marking_changed treats is_public as "always
-- update" (its comment says that path was meant for small private storage).
--
-- This coalesces those updates: a public storage sends at most one update per
-- FLUSH_DELAY_MS, carrying every change since the last one. Private storage
-- (backpacks) and storage that renders its contents (shelves, displays) keep
-- ACE's original behaviour. An open stockpile window still refreshes every
-- second through ACE's own 'stonehearth_ace:storage_mark_changed' call.

local FLUSH_DELAY_MS = 2000
local REPORT_MINUTES = 5

storage_throttle = {}

local changes, flushes = 0, 0

local function write(format, ...)
   radiant.log.write('storage_throttle', 0, '[storage_throttle] ' .. format, ...)
end

local function patch()
   local StorageComponent = radiant.mods.require('stonehearth.components.storage.storage_component')
   local ace_consider = StorageComponent and StorageComponent._consider_marking_changed
   if not ace_consider then
      write('ACE storage patch not found, nothing changed')
      return
   end

   function StorageComponent:_consider_marking_changed()
      if self._throttle_render_contents == nil then
         local json = radiant.entities.get_json(self) or {}
         self._throttle_render_contents = json.render_contents and true or false
      end
      if not self._sv.is_public or self._throttle_render_contents then
         return ace_consider(self)
      end

      changes = changes + 1
      self._has_changed = true
      if not self._throttle_timer then
         self._throttle_timer = radiant.set_realtime_timer('storage_throttle flush', FLUSH_DELAY_MS, function()
               self._throttle_timer = nil
               if not self.__destroying and self._entity and self._entity:is_valid() then
                  flushes = flushes + 1
                  self:mark_changed()
               end
            end)
      end
   end

   write('patched storage updates: public storage sends at most every %dms', FLUSH_DELAY_MS)
end

radiant.events.listen_once(radiant, 'stonehearth_ace:server:required_loaded', patch)

-- Fires after radiant's own 'radiant:init' handler has created the realtime clock.
radiant.events.listen(storage_throttle, 'radiant:init', function()
      radiant.set_realtime_interval('storage_throttle report', REPORT_MINUTES * 60 * 1000, function()
            write('last %dm: %d storage changes sent as %d updates', REPORT_MINUTES, changes, flushes)
            changes, flushes = 0, 0
         end)
   end)

return storage_throttle
