------------------------------------------------------------
-- EMBEDDED DKJSON (lightweight JSON parser)
------------------------------------------------------------
local json = {}
do
  local function decode_error(str, idx, msg)
    error(string.format("Error at position %d: %s", idx, msg))
  end

  local function parse_value(str, idx)
    idx = str:find("%S", idx) or idx
    local chr = str:sub(idx, idx)
  
    if chr == '"' then
      local res = ""
      idx = idx + 1
      while idx <= #str do
        chr = str:sub(idx, idx)
        if chr == '"' then return res, idx + 1 end
        res = res .. chr
        idx = idx + 1
      end
      decode_error(str, idx, "unterminated string")
  
    elseif chr:match("[%d%-]") then
      local num = str:match("^-?%d+%.?%d*[eE]?[%+%-]?%d*", idx)
      return tonumber(num), idx + #num
  
    elseif str:sub(idx, idx + 3) == "true" then
      return true, idx + 4
  
    elseif str:sub(idx, idx + 4) == "false" then
      return false, idx + 5
  
    elseif str:sub(idx, idx + 3) == "null" then
      return nil, idx + 4
  
    elseif chr == "[" then
      local res, val = {}, nil
      idx = idx + 1
      while true do
        idx = str:find("%S", idx) or idx
        if str:sub(idx, idx) == "]" then return res, idx + 1 end
        val, idx = parse_value(str, idx)
        table.insert(res, val)
        idx = str:find("%S", idx) or idx
        chr = str:sub(idx, idx)
        if chr == "]" then return res, idx + 1 end
        if chr ~= "," then decode_error(str, idx, "expected ',' or ']' in array") end
        idx = idx + 1
      end
  
    elseif chr == "{" then
      local res, key, val = {}, nil, nil
      idx = idx + 1
      while true do
        idx = str:find("%S", idx) or idx
        if str:sub(idx, idx) == "}" then return res, idx + 1 end
        key, idx = parse_value(str, idx)
        idx = str:find("%S", idx) or idx
        if str:sub(idx, idx) ~= ":" then decode_error(str, idx, "expected ':' after key") end
        idx = idx + 1
        val, idx = parse_value(str, idx)
        res[key] = val
        idx = str:find("%S", idx) or idx
        chr = str:sub(idx, idx)
        if chr == "}" then return res, idx + 1 end
        if chr ~= "," then decode_error(str, idx, "expected ',' or '}' in object") end
        idx = idx + 1
      end
  
    else
      decode_error(str, idx, "unexpected character")
    end
  end
  
  function json.decode(str)
    str = str:match("^%s*(.-)%s*$") -- Trim leading/trailing whitespace
    local res, idx = parse_value(str, 1)
    return res
  end
end

------------------------------------------------------------
-- Load activation times from a JSON file.
-- The JSON file now contains an array of objects:
-- [ {"entry_time": "18:08:18", "exit_time": "18:10:05"}, ... ]
------------------------------------------------------------
local activationTimes = {}
local function load_activation_times(filename)
    local file = io.open(filename, "r")
    if file then
      local content = file:read("*a")
      file:close()
      if not content or content == "" then
        reaper.ShowMessageBox("The JSON file is empty: " .. filename, "Error", 0)
        return
      end
      reaper.ShowConsoleMsg("Loaded JSON content: " .. tostring(content) .. "\n")
      activationTimes = json.decode(content)
    else
      reaper.ShowMessageBox("Could not open activation times file: " .. filename, "Error", 0)
    end
end

-- Need to load the list of times to unmute a channel
load_activation_times("#####")

------------------------------------------------------------
-- Utility Functions
------------------------------------------------------------
local function random_range(min, max)
  return min + math.random() * (max - min)
end

local function db_to_lin(db)
  return 10^(db / 20)
end

-- Returns the current time as an "HH:MM:SS" string.
local function get_current_time_string()
  return os.date("%H:%M:%S")
end

-- Helper: Convert an "HH:MM:SS" time string to seconds from midnight.
local function timeStringToSeconds(timeStr)
    if not timeStr then
      error("timeStringToSeconds received nil value")
    end
    local h, m, s = timeStr:match("^(%d+):(%d+):(%d+)$")
    if not h or not m or not s then
      error("timeStringToSeconds: invalid format for time string: " .. tostring(timeStr))
    end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
  end

------------------------------------------------------------
-- Global Settings
------------------------------------------------------------
local target_vol = db_to_lin(-12)  -- Target volume for active tracks (-12 dB ≈ 0.2512)
local fade_proportion = 0.25         -- Fade-in (25%) and fade-out (25%) of the active period.
local interval = 0.03                -- Update interval (seconds)

------------------------------------------------------------
-- Track State Initialization
------------------------------------------------------------
local function initialize_track_state()
  local center_x = random_range(0.3, 0.7)
  local center_y = random_range(0.3, 0.7)
  local radius   = random_range(0.3, 0.5)
  -- Default duration if not set later via schedule.
  local duration = random_range(100.0, 300.0)
  local direction = math.random(0, 1) == 1 and 1 or -1

  local start_angle = random_range(0, 2 * math.pi)
  local end_angle = start_angle + math.pi * direction  -- 180° away

  return {
    center_x = center_x,
    center_y = center_y,
    radius = radius,
    duration = duration,
    direction = direction,
    start_angle = start_angle,
    end_angle = end_angle,
    phase = 0,          -- Elapsed time for motion (seconds)
    active = false,     -- Initially inactive
    pos_x = center_x,   -- Start at center
    pos_y = center_y,
    schedule = nil      -- To be assigned when activated by a schedule
  }
end

-- Create an array of track states (here 18 tracks).
local num_tracks = 34
local tracks = {}
for i = 1, num_tracks do
  tracks[i] = initialize_track_state()
end

------------------------------------------------------------
-- Motion and Volume Update Functions
------------------------------------------------------------
-- For linear motion across the circle (based on start and end angles).
local function update_motion(track_state)
  local fraction = math.min(track_state.phase / track_state.duration, 1)
  local angle = track_state.start_angle + fraction * (track_state.end_angle - track_state.start_angle)
  track_state.pos_x = track_state.center_x + track_state.radius * math.cos(angle)
  track_state.pos_y = track_state.center_y + track_state.radius * math.sin(angle)
end

-- Volume update: fade in during first 25% of duration, steady during 50%, fade out during last 25%.
local function update_volume(track_state)
  local duration = track_state.duration
  local fade_in_time = duration * 0.25
  local steady_time = duration * 0.50
  local fade_out_time = duration * 0.25
  local phase = track_state.phase
  local vol = 0

  if phase < fade_in_time then
    vol = target_vol * (phase / fade_in_time)
  elseif phase < (fade_in_time + steady_time) then
    vol = target_vol
  elseif phase < duration then
    local t = (phase - (fade_in_time + steady_time)) / fade_out_time
    vol = target_vol * (1 - t)
  else
    vol = 0
  end
  return vol
end

------------------------------------------------------------
-- Activation Helpers
------------------------------------------------------------
-- Updated activate_track now accepts a schedule.
local function activate_track(track_state, schedule)
  track_state.active = true
  track_state.phase = 0
  track_state.schedule = schedule
  
  -- Calculate schedule duration in seconds from entry to exit.
  local entry_sec = timeStringToSeconds(schedule.entry_time)
  local exit_sec = timeStringToSeconds(schedule.exit_time)
  track_state.duration = exit_sec - entry_sec
  
  -- Also reinitialize motion parameters.
  local new_state = initialize_track_state()
  track_state.center_x  = new_state.center_x
  track_state.center_y  = new_state.center_y
  track_state.radius    = new_state.radius
  track_state.direction = new_state.direction
  track_state.start_angle = new_state.start_angle
  track_state.end_angle   = new_state.end_angle
  track_state.pos_x = track_state.center_x
  track_state.pos_y = track_state.center_y
end

local function deactivate_track(track_state)
  track_state.active = false
  track_state.phase = 0
  track_state.schedule = nil
end

------------------------------------------------------------
-- Scheduling: Ensure Active Tracks Based on Entry/Exit Times
------------------------------------------------------------
-- This function now examines each schedule in activationTimes and:
--   (a) Activates a track (if not already assigned) for each schedule where
--       current time is between entry and exit.
--   (b) Forces fade-out on a track if the schedule’s exit time has passed.
local function ensure_active_tracks()
    local current_time_str = get_current_time_string()
    local current_time_sec = timeStringToSeconds(current_time_str)
    
    -- Build a list of active schedules (check for valid entry and exit times first)
    local activeSchedules = {}
    for i, satellite in ipairs(activationTimes) do
      if satellite.entry_time and satellite.exit_time then
        local entry_sec = timeStringToSeconds(satellite.entry_time)
        local exit_sec  = timeStringToSeconds(satellite.exit_time)
        if current_time_sec >= entry_sec and current_time_sec <= exit_sec then
          table.insert(activeSchedules, satellite)
        end
      else
        reaper.ShowConsoleMsg("Schedule entry #" .. i .. " is missing entry_time or exit_time.\n")
      end
    end
    
    local target_channels = #activeSchedules
    if target_channels == 0 then
      for _, state in ipairs(tracks) do
        if state.active then
          state.active = false
        end
      end
      return
    end
  
    -- Count already active tracks.
    local active_count = 0
    for _, state in ipairs(tracks) do
      if state.active then
        active_count = active_count + 1
      end
    end
  
    -- Activate tracks for each active schedule if not already assigned.
 -- For each active schedule, assign it to a track if not already assigned.
for _, sched in ipairs(activeSchedules) do
    local assigned = false
    for _, state in ipairs(tracks) do
      if state.active and state.schedule and 
         state.schedule.entry_time == sched.entry_time and 
         state.schedule.exit_time == sched.exit_time then
        assigned = true
        break
      end
    end
    if not assigned then
      local inactive_indices = {}
      for i, track in ipairs(tracks) do
        if not track.active then
          table.insert(inactive_indices, i)
        end
      end
      if #inactive_indices > 0 then
        local randomIndex = inactive_indices[math.random(#inactive_indices)]
        activate_track(tracks[randomIndex], sched)
      end
    end
  end
  
    -- For each active track with a schedule, if current time is past its exit time, force fade-out.
    for _, state in ipairs(tracks) do
      if state.active and state.schedule then
        local exit_sec = timeStringToSeconds(state.schedule.exit_time)
        if current_time_sec > exit_sec then
          state.phase = state.duration  -- Force fade-out
        end
      end
    end
    
    -- Deactivate any extra tracks beyond target_channels.
    local active_count = 0
    for _, state in ipairs(tracks) do
      if state.active then
        active_count = active_count + 1
      end
    end
    
    while active_count > target_channels do
      for i = 1, #tracks do
        if tracks[i].active and tracks[i].schedule then
          local exit_sec = timeStringToSeconds(tracks[i].schedule.exit_time)
          if current_time_sec > exit_sec then
            deactivate_track(tracks[i])
            active_count = active_count - 1
            break
          end
        end
      end
      break -- safeguard against infinite loops
    end
    
  end

------------------------------------------------------------
-- Main Update Loop
------------------------------------------------------------
function update_positions()
  ensure_active_tracks()
  
  for i, track_state in ipairs(tracks) do
    local track = reaper.GetSelectedTrack(0, i - 1)
    if track then
      if track_state.active then
        track_state.phase = track_state.phase + interval
        update_motion(track_state)
        local vol = update_volume(track_state)
        if track_state.phase >= track_state.duration then
          deactivate_track(track_state)
          -- Reset FX panning to center.
          reaper.TrackFX_SetParam(track, 0, 3, track_state.center_x)
          reaper.TrackFX_SetParam(track, 0, 4, track_state.center_y)
        else
          reaper.TrackFX_SetParam(track, 0, 3, track_state.pos_x)
          reaper.TrackFX_SetParam(track, 0, 4, track_state.pos_y)
        end
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", vol)
      else
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 1)
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", 0)
      end
    end
  end
  reaper.defer(update_positions)
end

------------------------------------------------------------
-- Initialize All Selected Tracks (Mute and Volume Off)
------------------------------------------------------------
for i = 0, num_tracks - 1 do
  local track = reaper.GetSelectedTrack(0, i)
  if track then
    reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 1)
    reaper.SetMediaTrackInfo_Value(track, "D_VOL", 0)
  end
end

------------------------------------------------------------
-- Optionally, Start REAPER Playback Automatically
------------------------------------------------------------
function start_playback_on_startup()
  reaper.Main_OnCommand(40044, 0) -- Start playback.
end

-- Start playback and begin the update loop.
start_playback_on_startup()
update_positions()
