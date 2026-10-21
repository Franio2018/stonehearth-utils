-- Memory Probe: diagnostics only, changes no game state.
--
-- Every REPORT_MINUTES it writes one line to stonehearth.log:
--    [memory_probe] server t=12m lua=812.4MB frames=1180 slow=3 max_gap=640ms
-- Every FULL_GC_MINUTES it forces a full Lua collection and logs how much it
-- freed and how long it took:
--    [memory_probe] server full_gc before=812.4MB after=455.1MB freed=357.3MB took=910ms
--
-- Reading it:
--    lua keeps rising, full_gc frees a lot   -> GC falling behind
--    lua keeps rising, full_gc frees little  -> Lua leak (objects still referenced)
--    lua flat while Task Manager rises       -> native (engine) memory, not Lua
--    max_gap / slow rising over the session  -> the lag, measured

local REPORT_MINUTES  = 1
local FULL_GC_MINUTES = 0       -- 0 disables the forced collection
local SLOW_FRAME_MS   = 250     -- a gap between game loops longer than this counts as "slow"

local Probe = {}

local function now_s()
   return _host:get_realtime()   -- seconds, same clock radiant/modules/timer.lua uses
end

local function lua_mb()
   return collectgarbage('count') / 1024
end

local function write(side, format, ...)
   radiant.log.write('memory_probe', 0, '[memory_probe] ' .. side .. ' ' .. format, ...)
end

function Probe.start(side)
   local started = now_s()
   local last_loop = nil
   local frames, slow, max_gap = 0, 0, 0

   -- Kept allocation-free: runs every game loop.
   radiant.on_game_loop('memory_probe frame gap', function()
         local t = now_s()
         if last_loop then
            local gap = t - last_loop
            frames = frames + 1
            if gap > max_gap then
               max_gap = gap
            end
            if gap * 1000 > SLOW_FRAME_MS then
               slow = slow + 1
            end
         end
         last_loop = t
      end)

   radiant.set_realtime_interval('memory_probe report', REPORT_MINUTES * 60 * 1000, function()
         local ok, err = pcall(function()
               write(side, 't=%dm lua=%.1fMB frames=%d slow=%d max_gap=%dms',
                     math.floor((now_s() - started) / 60), lua_mb(), frames, slow, math.floor(max_gap * 1000))
            end)
         if not ok then
            write(side, 'report failed: %s', tostring(err))
         end
         frames, slow, max_gap = 0, 0, 0
      end)

   if FULL_GC_MINUTES > 0 then
      radiant.set_realtime_interval('memory_probe full gc', FULL_GC_MINUTES * 60 * 1000, function()
            local before = lua_mb()
            local t0 = now_s()
            collectgarbage('collect')
            local took = now_s() - t0
            local after = lua_mb()
            write(side, 'full_gc before=%.1fMB after=%.1fMB freed=%.1fMB took=%dms',
                  before, after, before - after, math.floor(took * 1000))
            -- don't let the forced collection's own pause count as lag
            last_loop = nil
         end)
   end

   write(side, 'started: report every %dm, full gc every %dm, lua=%.1fMB',
         REPORT_MINUTES, FULL_GC_MINUTES, lua_mb())
end

return Probe
