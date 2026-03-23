-- jam coast
-- west coast synthesizer
-- finding beauty in chaos
--
-- inspired by Make Noise:
-- DPO, Mysteron, QPAS, Optomix,
-- Maths, Strega, Erbe-Verb,
-- Morphagene, Wogglebug
--
-- E1: page select
-- E2/E3: page params
-- K2: play/stop
-- K3: page action
--
-- v1.0 @jamminstein

engine.name = "Jamcoast"

local musicutil = require "musicutil"
local util = require "util"
local seq = include("lib/sequencer")

-- ======== CONSTANTS ========

local PAGES = {"VOICE", "FILTER", "SPACE", "MORPH", "CHAOS"}
local SHAPE_NAMES = {"tri", "saw", "pulse"}
local SCALE_NAMES = {
  "major", "natural_minor", "dorian", "phrygian",
  "mixolydian", "pentatonic_maj", "chromatic"
}
local SCALE_DISPLAY = {"MAJ", "MIN", "DOR", "PHR", "MIX", "PNT", "CHR"}
local TAPE_BUF_SEC = 16

-- ======== STATE ========

local current_page = 1
local playing = false
local seq_clock_id = nil
local grid_clock_id = nil
local screen_metro = nil
local screen_dirty = true

-- MIDI
local midi_out_device = nil
local midi_in_device = nil
local opxy_device = nil
local current_note = nil -- for monophonic note tracking
local k2_hold_time = 0   -- for long-press detection

-- scale
local scale_notes = {}

-- softcut / morphagene
local tape_recording = false
local tape_playing = false
local tape_phase = 0
local tape_rec_start = 0
local tape_rec_length = 4

-- chaos / wogglebug state
local smooth_val = 0
local smooth_target = 0
local stepped_val = 0
local step_counter = 0
local burst_flash = 0

-- screen visualization state
local waveform_buf = {}    -- 64 samples for voice page oscilloscope
local particles = {}       -- space page particles
local chaos_trail = {}     -- chaos page random walk trail
local chaos_x = 64         -- chaos walk position
local chaos_y = 32
local tape_angle = 0       -- morph page reel rotation

-- ======== EXPLORER (bandmate/autopilot) ========
-- 4 phases inspired by Make Noise philosophy:
-- DRIFT: slow evolution, subtle wavefold sweeps, gentle FM (Maths rising)
-- SURGE: energy builds, chaos routes activate, waveguide resonance (DPO peak)
-- RUPTURE: maximum fold + FM, burst mode, delay freeze, wild modulation (Strega feedback)
-- DISSOLVE: thin out, reverb washes, granular textures, LPG plucks (Morphagene decay)

local explorer_on = false
local explorer_clock_id = nil
local explorer_phase = 1
local explorer_tick = 0
local explorer_phase_lengths = {10, 8, 6, 10} -- bars per phase
local EXPLORER_PHASES = {"DRIFT", "SURGE", "RUPTURE", "DISSOLVE"}

-- scene anchors: saved param values to drift back toward
local scene_anchors = nil

-- scale palettes: each phase can shift the musical mood
local SCALE_PALETTES = {
  -- palette 1: bright to dark journey
  {drift = 1, surge = 3, rupture = 7, dissolve = 2},  -- MAJ->DOR->CHR->MIN
  -- palette 2: modal exploration
  {drift = 3, surge = 5, rupture = 4, dissolve = 1},  -- DOR->MIX->PHR->MAJ
  -- palette 3: pentatonic to chromatic
  {drift = 6, surge = 1, rupture = 7, dissolve = 6},  -- PNT->MAJ->CHR->PNT
  -- palette 4: dark descent
  {drift = 2, surge = 4, rupture = 7, dissolve = 3},  -- MIN->PHR->CHR->DOR
  -- palette 5: tension and release
  {drift = 1, surge = 2, rupture = 4, dissolve = 5},  -- MAJ->MIN->PHR->MIX
}
local active_palette = nil

-- melodic interval pools per phase
local DRIFT_INTERVALS = {0, 2, 3, 5, 7, -5, 12}
local SURGE_INTERVALS = {0, 3, 5, 7, 10, 12, -7, -12, 14}
local RUPTURE_INTERVALS = {0, 1, 6, 7, 11, 13, -6, -11, -1, 15}
local DISSOLVE_INTERVALS = {0, -2, -5, -7, -12, 7, 5}

local function save_scene_anchors()
  scene_anchors = {
    fold_amt = params:get("fold_amt"),
    fm_amt = params:get("fm_amt"),
    cutoff = params:get("cutoff"),
    radiate = params:get("radiate"),
    wg_mix = params:get("wg_mix"),
    delay_mix = params:get("delay_mix"),
    delay_fb = params:get("delay_fb"),
    reverb_mix = params:get("reverb_mix"),
    reverb_decay = params:get("reverb_decay"),
    chaos_to_fold = params:get("chaos_to_fold"),
    chaos_to_cutoff = params:get("chaos_to_cutoff"),
    correlation = params:get("correlation"),
    shape = params:get("shape"),
    scale_type = params:get("scale_type"),
    root_note = params:get("root_note"),
    octave_shift = params:get("octave_shift"),
  }
  -- pick a random palette for this exploration cycle
  active_palette = SCALE_PALETTES[math.random(#SCALE_PALETTES)]
end

-- regenerate the sequencer pattern with musical intent
local function regen_pattern(pool, density, vel_range_lo, vel_range_hi)
  for i = 1, seq.NUM_STEPS do
    seq.set_step(i, "note", pool[math.random(#pool)])
    seq.set_step(i, "vel", vel_range_lo + math.random() * (vel_range_hi - vel_range_lo))
    seq.set_step(i, "gate_len", 0.2 + math.random() * 0.8)
    seq.set_step(i, "on", math.random() < density)
    seq.set_step(i, "fold_amt", -1)
    seq.set_step(i, "fm_amt", -1)
  end
  -- always keep step 1 on for downbeat
  seq.set_step(1, "on", true)
end

local function explorer_evolve()
  explorer_tick = explorer_tick + 1
  local phase = explorer_phase
  local progress = explorer_tick / explorer_phase_lengths[phase]

  if phase == 1 then
    -- DRIFT: Maths-like slow rise. the sound slowly comes alive.
    -- scale shifts to set the mood. melody evolves gently.

    -- set scale for this phase
    if explorer_tick == 1 then
      if active_palette then
        params:set("scale_type", active_palette.drift)
      end
      -- regenerate pattern with gentle intervals
      regen_pattern(DRIFT_INTERVALS, 0.7, 0.5, 0.8)
    end

    -- wavefold: slow sweep upward
    local fold = params:get("fold_amt")
    params:set("fold_amt", util.clamp(fold + 0.02 + math.random() * 0.02, 0, 0.6))

    -- shape drift
    if math.random() < 0.25 then
      local shape = params:get("shape")
      params:set("shape", util.clamp(shape + (math.random() - 0.5) * 0.15, 0, 1))
    end

    -- FM slowly rises
    params:set("fm_amt", util.clamp(params:get("fm_amt") + 0.015, 0, 0.8))

    -- filter opens gradually
    params:set("cutoff", util.clamp(params:get("cutoff") + 100 + math.random(200), 200, 10000))

    -- chaos stirs: correlation drops, routes activate
    params:set("correlation", util.clamp(params:get("correlation") - 0.02, 0.2, 0.95))
    params:set("chaos_to_fold", util.clamp(params:get("chaos_to_fold") + 0.02, 0, 0.5))

    -- melodic evolution: mutate notes within scale
    if math.random() < 0.35 then
      local i = math.random(1, seq.NUM_STEPS)
      local step = seq.get_step(i)
      if step then
        local new_note = DRIFT_INTERVALS[math.random(#DRIFT_INTERVALS)]
        seq.set_step(i, "note", new_note)
      end
    end

    -- occasionally shift root by a 4th or 5th
    if math.random() < 0.08 then
      local shifts = {-7, -5, 5, 7}
      local root = params:get("root_note")
      params:set("root_note", util.clamp(root + shifts[math.random(#shifts)], 24, 84))
    end

  elseif phase == 2 then
    -- SURGE: DPO at full power. energy builds. wider intervals.
    -- scale shifts to something brighter/more complex.

    if explorer_tick == 1 then
      if active_palette then
        params:set("scale_type", active_palette.surge)
      end
      -- regenerate with wider intervals and higher density
      regen_pattern(SURGE_INTERVALS, 0.85, 0.6, 0.95)
      -- octave up for energy
      params:set("octave_shift", math.random(0, 1))
    end

    -- wavefold pushes higher
    params:set("fold_amt", util.clamp(params:get("fold_amt") + 0.03, 0, 0.85))

    -- FM ratio shifts for metallic timbres (DPO cross-mod)
    if math.random() < 0.3 then
      local ratios = {1.5, 2, 2.5, 3, 0.75, 1.33, 3.5}
      params:set("fm_ratio", ratios[math.random(#ratios)])
    end

    -- waveguide resonance enters (Mysteron)
    params:set("wg_mix", util.clamp(params:get("wg_mix") + 0.03, 0, 0.6))

    -- QPAS radiate opens (formant vowels)
    params:set("radiate", util.clamp(params:get("radiate") + 0.03, 0, 0.7))

    -- chaos routes build
    params:set("chaos_to_fold", util.clamp(params:get("chaos_to_fold") + 0.03, 0, 0.7))
    params:set("chaos_to_cutoff", util.clamp(params:get("chaos_to_cutoff") + 0.02, 0, 0.5))

    -- pattern mutations: swap notes, add accents
    if math.random() < 0.3 then
      local i = math.random(1, seq.NUM_STEPS)
      seq.set_step(i, "note", SURGE_INTERVALS[math.random(#SURGE_INTERVALS)])
      seq.set_step(i, "vel", 0.8 + math.random() * 0.2)
    end

    -- activate silent steps
    if math.random() < 0.25 then
      local i = math.random(1, seq.NUM_STEPS)
      seq.set_step(i, "on", true)
    end

    -- gate length variation
    if math.random() < 0.2 then
      local i = math.random(1, seq.NUM_STEPS)
      seq.set_step(i, "gate_len", 0.1 + math.random() * 0.5)
    end

    -- delay builds (Strega warming up)
    params:set("delay_mix", util.clamp(params:get("delay_mix") + 0.02, 0, 0.5))
    params:set("delay_fb", util.clamp(params:get("delay_fb") + 0.02, 0.1, 0.75))

    -- root note wanders: up by 2nds and 3rds
    if math.random() < 0.12 then
      local root = params:get("root_note")
      params:set("root_note", util.clamp(root + math.random(-3, 4), 24, 84))
    end

  elseif phase == 3 then
    -- RUPTURE: Strega feedback chaos. chromatic territory.
    -- everything feeds back on itself. beautiful destruction.

    if explorer_tick == 1 then
      if active_palette then
        params:set("scale_type", active_palette.rupture)
      end
      -- rupture: dense, dissonant, chaotic intervals
      regen_pattern(RUPTURE_INTERVALS, 0.9, 0.7, 1.0)
      -- burst mode on for probabilistic triggering
      params:set("burst_mode", 2)
      params:set("burst_density", 0.4 + math.random() * 0.4)
    end

    -- wavefold maxes out
    params:set("fold_amt", util.clamp(params:get("fold_amt") + 0.04, 0, 1))

    -- FM surges wildly
    if math.random() < 0.4 then
      params:set("fm_amt", 0.5 + math.random() * 1.2)
      -- non-integer ratios for inharmonic metallic tones
      if math.random() < 0.5 then
        params:set("fm_ratio", 0.5 + math.random() * 4)
      end
    end

    -- chaos routing maximal
    params:set("chaos_to_fold", util.clamp(params:get("chaos_to_fold") + 0.05, 0, 0.9))
    params:set("chaos_to_cutoff", util.clamp(params:get("chaos_to_cutoff") + 0.04, 0, 0.8))
    params:set("chaos_to_delay", util.clamp(params:get("chaos_to_delay") + 0.03, 0, 0.6))

    -- correlation drops: wogglebug goes wild
    params:set("correlation", util.clamp(params:get("correlation") - 0.04, 0.1, 0.9))

    -- delay freeze moments (Mimeophon hold)
    if math.random() < 0.15 then
      params:set("delay_freeze", 2)
    elseif math.random() < 0.3 then
      params:set("delay_freeze", 1)
    end

    -- per-step fold/FM overrides: each step gets its own timbre
    if math.random() < 0.4 then
      local i = math.random(1, seq.NUM_STEPS)
      seq.set_step(i, "fold_amt", math.random() * 0.9)
      seq.set_step(i, "fm_amt", math.random() * 1.5)
    end

    -- octave jumps for energy
    if math.random() < 0.1 then
      params:set("octave_shift", math.random(-1, 2))
    end

    -- root note: chromatic wandering
    if math.random() < 0.15 then
      local root = params:get("root_note")
      params:set("root_note", util.clamp(root + math.random(-5, 5), 24, 84))
    end

    -- pattern mutations: wild note replacement
    if math.random() < 0.3 then
      local i = math.random(1, seq.NUM_STEPS)
      seq.set_step(i, "note", RUPTURE_INTERVALS[math.random(#RUPTURE_INTERVALS)])
      seq.set_step(i, "gate_len", 0.05 + math.random() * 0.3)
    end

    -- reverb toward infinite (Erbe-Verb)
    params:set("reverb_decay", util.clamp(params:get("reverb_decay") + 0.04, 0, 0.95))
    params:set("reverb_mix", util.clamp(params:get("reverb_mix") + 0.02, 0, 0.5))
    params:set("reverb_mod_depth", util.clamp(params:get("reverb_mod_depth") + 0.03, 0, 0.6))

  elseif phase == 4 then
    -- DISSOLVE: Morphagene decay. LPG plucks. reverb washes.
    -- the sound dissolves. melody simplifies. space opens.

    if explorer_tick == 1 then
      if active_palette then
        params:set("scale_type", active_palette.dissolve)
      end
      -- gentle downward pattern, still audible density
      regen_pattern(DISSOLVE_INTERVALS, 0.65, 0.4, 0.75)
      -- burst mode off, back to straight sequencing
      params:set("burst_mode", 1)
      -- octave back to center
      params:set("octave_shift", 0)
      -- open filter back up so we're audible
      params:set("cutoff", util.clamp(params:get("cutoff"), 1500, 18000))
    end

    -- wavefold retreats gently
    local fold = params:get("fold_amt")
    params:set("fold_amt", util.clamp(fold - 0.02, 0.05, 1))

    -- FM retreats but keeps some warmth
    params:set("fm_amt", util.clamp(params:get("fm_amt") - 0.03, 0.05, 2))

    -- filter closes gently but never below audible range
    params:set("cutoff", util.clamp(params:get("cutoff") * 0.95, 800, 18000))

    -- waveguide fades
    params:set("wg_mix", util.clamp(params:get("wg_mix") - 0.03, 0, 1))

    -- chaos calms: correlation rises (smooth, melodic drift)
    params:set("correlation", util.clamp(params:get("correlation") + 0.04, 0, 0.95))

    -- chaos routes decay
    params:set("chaos_to_fold", util.clamp(params:get("chaos_to_fold") - 0.04, 0, 1))
    params:set("chaos_to_cutoff", util.clamp(params:get("chaos_to_cutoff") - 0.03, 0, 1))
    params:set("chaos_to_delay", util.clamp(params:get("chaos_to_delay") - 0.02, 0, 1))

    -- delay freeze off, delay fades
    params:set("delay_freeze", 1)
    params:set("delay_mix", util.clamp(params:get("delay_mix") - 0.02, 0, 1))

    -- reverb sustains but modulation fades
    params:set("reverb_mod_depth", util.clamp(params:get("reverb_mod_depth") - 0.03, 0, 1))

    -- thin pattern slightly: never go below 4 active steps
    if math.random() < 0.15 then
      local active = {}
      for i = 1, seq.NUM_STEPS do
        local step = seq.get_step(i)
        if step and step.on then table.insert(active, i) end
      end
      if #active > 4 then
        local idx = active[math.random(#active)]
        seq.set_step(idx, "on", false)
      end
    end

    -- notes drift downward
    if math.random() < 0.25 then
      local i = math.random(1, seq.NUM_STEPS)
      local step = seq.get_step(i)
      if step then
        seq.set_step(i, "note", DISSOLVE_INTERVALS[math.random(#DISSOLVE_INTERVALS)])
      end
    end

    -- longer gates: notes ring out and decay
    if math.random() < 0.2 then
      local i = math.random(1, seq.NUM_STEPS)
      seq.set_step(i, "gate_len", 0.8 + math.random() * 1.2)
    end

    -- root drifts back toward home
    if scene_anchors and math.random() < 0.15 then
      local root = params:get("root_note")
      local target = scene_anchors.root_note
      params:set("root_note", root + math.floor((target - root) * 0.3 + 0.5))
    end

  end

  -- phase transition
  if explorer_tick >= explorer_phase_lengths[phase] then
    explorer_tick = 0
    explorer_phase = (explorer_phase % 4) + 1
    -- randomize next phase length (keep it unpredictable like Wogglebug)
    explorer_phase_lengths[explorer_phase] = explorer_phase_lengths[explorer_phase] + math.random(-3, 3)
    explorer_phase_lengths[explorer_phase] = util.clamp(explorer_phase_lengths[explorer_phase], 4, 16)

    -- on return to DRIFT: GUARANTEE sound comes back
    if explorer_phase == 1 then
      -- new palette = new musical journey each cycle
      active_palette = SCALE_PALETTES[math.random(#SCALE_PALETTES)]
      -- clear per-step overrides
      for i = 1, seq.NUM_STEPS do
        seq.set_step(i, "fold_amt", -1)
        seq.set_step(i, "fm_amt", -1)
      end
      -- burst mode off, LPG off, freeze off
      params:set("burst_mode", 1)
      params:set("lpg_mode", 1)
      params:set("delay_freeze", 1)
      -- FORCE audible state: filter open, some fold, reasonable volume
      params:set("cutoff", util.clamp(params:get("cutoff"), 2000, 18000))
      params:set("fold_amt", util.clamp(params:get("fold_amt"), 0.05, 0.8))
      params:set("fm_amt", util.clamp(params:get("fm_amt"), 0, 0.8))
      params:set("reverb_mix", util.clamp(params:get("reverb_mix"), 0.05, 0.5))
      params:set("delay_mix", util.clamp(params:get("delay_mix"), 0.05, 0.5))
      params:set("radiate", util.clamp(params:get("radiate"), 0, 0.5))
      params:set("wg_mix", util.clamp(params:get("wg_mix"), 0, 0.3))
      -- root can wander to a new key center
      if math.random() < 0.3 then
        local roots = {36, 38, 40, 41, 43, 45, 48, 50, 52, 53, 55, 57, 60}
        params:set("root_note", roots[math.random(#roots)])
      end
    end
  end

  screen_dirty = true
end

local function start_explorer()
  save_scene_anchors()
  explorer_on = true
  explorer_tick = 0
  explorer_phase = 1
  explorer_clock_id = clock.run(function()
    while explorer_on do
      clock.sync(2) -- evolve every 2 beats
      if explorer_on and playing then
        explorer_evolve()
      end
    end
  end)
end

local function stop_explorer()
  explorer_on = false
  if explorer_clock_id then
    clock.cancel(explorer_clock_id)
    explorer_clock_id = nil
  end
  -- restore scene anchors
  if scene_anchors then
    for name, target in pairs(scene_anchors) do
      params:set(name, target)
    end
  end
  -- clear per-step overrides
  for i = 1, seq.NUM_STEPS do
    seq.set_step(i, "fold_amt", -1)
    seq.set_step(i, "fm_amt", -1)
    seq.set_step(i, "on", true)
  end
  params:set("delay_freeze", 1)
  params:set("lpg_mode", 1)
end

-- ======== MIDI HELPERS ========

local function midi_note_on(note, vel_int, ch)
  if midi_out_device and params:get("midi_out_ch") > 0 then
    midi_out_device:note_on(note, vel_int, ch or params:get("midi_out_ch"))
  end
end

local function midi_note_off(note, ch)
  if midi_out_device and params:get("midi_out_ch") > 0 then
    midi_out_device:note_off(note, 0, ch or params:get("midi_out_ch"))
  end
end

local function opxy_note_on(note, vel_int, ch)
  if opxy_device and params:get("opxy_device") > 1 then
    opxy_device:note_on(note, vel_int, ch)
  end
end

local function opxy_note_off(note, ch)
  if opxy_device and params:get("opxy_device") > 1 then
    opxy_device:note_off(note, 0, ch)
  end
end

local function opxy_cc(cc, val, ch)
  if opxy_device and params:get("opxy_device") > 1 then
    opxy_device:cc(cc, val, ch)
  end
end

-- ======== SCALE HELPERS ========

local function build_scale()
  local root = params:get("root_note")
  local scale_idx = params:get("scale_type")
  local scale_name = SCALE_NAMES[scale_idx]
  scale_notes = musicutil.generate_scale(root - 24, scale_name, 8)
end

local function snap_to_scale(note)
  if #scale_notes == 0 then return note end
  local closest = scale_notes[1]
  local min_dist = math.abs(note - closest)
  for i = 2, #scale_notes do
    local dist = math.abs(note - scale_notes[i])
    if dist < min_dist then
      min_dist = dist
      closest = scale_notes[i]
    end
  end
  return closest
end

-- ======== NOTE PLAYING ========

local function note_off()
  if current_note then
    engine.note_off(current_note)
    midi_note_off(current_note)
    opxy_note_off(current_note, params:get("opxy_melody_ch"))
    current_note = nil
  end
end

local function note_on(midi_note, vel)
  note_off() -- monophonic: kill previous note
  local freq = musicutil.note_num_to_freq(midi_note)
  local vel_f = vel or 0.8
  engine.note_on(midi_note, freq, vel_f)
  midi_note_on(midi_note, math.floor(vel_f * 127))
  opxy_note_on(midi_note, math.floor(vel_f * 127), params:get("opxy_melody_ch"))
  current_note = midi_note
end

-- ======== MIDI INPUT ========

local function midi_event(data)
  local msg = midi.to_msg(data)
  if msg.ch ~= params:get("midi_in_ch") and params:get("midi_in_ch") > 0 then return end
  if msg.type == "note_on" and msg.vel > 0 then
    note_on(msg.note, msg.vel / 127)
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    if current_note == msg.note then
      note_off()
    end
  end
end

-- ======== SEQUENCER ========

local function advance_step()
  -- apply swing delay
  local swing_delay = seq.get_swing_delay()
  if swing_delay > 0 then
    clock.sleep(clock.get_beat_sec() * swing_delay)
  end

  local step = seq.advance()
  if step == nil then return end

  -- per-step param overrides
  local restore_fold = nil
  local restore_fm = nil
  if step.fold_amt >= 0 then
    restore_fold = params:get("fold_amt")
    engine.fold_amt(step.fold_amt)
  end
  if step.fm_amt >= 0 then
    restore_fm = params:get("fm_amt")
    engine.fm_amt(step.fm_amt)
  end

  -- compute note
  local root = params:get("root_note")
  local oct = params:get("octave_shift")
  local midi_note = snap_to_scale(root + step.note + (oct * 12))

  -- play
  note_on(midi_note, step.vel)

  -- schedule note off
  local gate_beats = params:get("gate_length") * step.gate_len * 0.25
  clock.run(function()
    clock.sleep(clock.get_beat_sec() * gate_beats)
    note_off()
    -- restore overrides
    if restore_fold then engine.fold_amt(restore_fold) end
    if restore_fm then engine.fm_amt(restore_fm) end
  end)

  screen_dirty = true
end

local function start_seq()
  seq.reset()
  playing = true
  seq_clock_id = clock.run(function()
    while true do
      clock.sync(1/4)
      if playing then
        advance_step()
      end
    end
  end)
end

local function stop_seq()
  playing = false
  note_off()
  if seq_clock_id then clock.cancel(seq_clock_id) end
  seq_clock_id = nil
  seq.reset()
end

-- ======== WAVEFORM COMPUTATION (for screen) ========

local function compute_waveform()
  local shape = params:get("shape")
  local fold = params:get("fold_amt")
  for i = 1, 64 do
    local t = (i - 1) / 63  -- 0 to 1
    local phase = t * 2 * math.pi
    local v
    -- shape morph: 0=tri, 0.5=saw, 1=pulse
    if shape < 0.5 then
      local mix = shape * 2
      local tri = 1 - 4 * math.abs(t - 0.5)
      local saw = 2 * t - 1
      v = tri * (1 - mix) + saw * mix
    else
      local mix = (shape - 0.5) * 2
      local saw = 2 * t - 1
      local pulse = t < 0.5 and 1 or -1
      v = saw * (1 - mix) + pulse * mix
    end
    -- wavefold simulation
    local gain = 1 + fold * 15
    v = v * gain
    for _ = 1, 4 do
      if v > 1 then v = 2 - v
      elseif v < -1 then v = -2 - v end
    end
    v = v / math.sqrt(gain)
    -- blend
    local orig
    if shape < 0.5 then
      local mix = shape * 2
      orig = (1 - 4 * math.abs(t - 0.5)) * (1 - mix) + (2 * t - 1) * mix
    else
      local mix = (shape - 0.5) * 2
      orig = (2 * t - 1) * (1 - mix) + (t < 0.5 and 1 or -1) * mix
    end
    v = orig * (1 - fold) + v * fold
    waveform_buf[i] = util.clamp(v, -1, 1)
  end
end

-- ======== CHAOS MODULATION (Wogglebug) ========

local function update_chaos()
  local dt = 1 / 15

  -- smooth random: drift toward targets
  if math.random() < params:get("smooth_rate") * dt then
    smooth_target = math.random() * 2 - 1
  end
  local corr = params:get("correlation")
  smooth_val = smooth_val + (smooth_target - smooth_val) * (1 - corr) * 0.3

  -- stepped random: jump at rate
  step_counter = step_counter + dt
  local step_period = 1 / math.max(params:get("stepped_rate"), 0.01)
  if step_counter >= step_period then
    -- correlation affects step size
    local jump = (math.random() * 2 - 1)
    stepped_val = stepped_val * corr + jump * (1 - corr)
    stepped_val = util.clamp(stepped_val, -1, 1)
    step_counter = 0
  end

  -- burst flash for screen
  if math.random() < params:get("burst_rate") * dt then
    burst_flash = 8
  end
  if burst_flash > 0 then burst_flash = burst_flash - 1 end

  -- apply modulations to engine
  local c2f = params:get("chaos_to_fold")
  local c2c = params:get("chaos_to_cutoff")
  local c2d = params:get("chaos_to_delay")

  if c2f > 0.01 then
    local base = params:get("fold_amt")
    engine.fold_amt(util.clamp(base + smooth_val * c2f * 0.5, 0, 1))
  end

  if c2c > 0.01 then
    local base = params:get("cutoff")
    local mod = stepped_val * c2c * base * 0.5
    engine.cutoff(util.clamp(base + mod, 20, 18000))
  end

  if c2d > 0.01 then
    local base = params:get("delay_time")
    local mod = smooth_val * c2d * 0.3
    engine.delay_time(util.clamp(base + mod, 0.01, 2))
  end

  -- update chaos trail for screen
  chaos_x = chaos_x + smooth_val * 3
  chaos_y = chaos_y + stepped_val * 2
  chaos_x = util.clamp(chaos_x, 4, 124)
  chaos_y = util.clamp(chaos_y, 12, 58)
  table.insert(chaos_trail, {x = chaos_x, y = chaos_y})
  -- trail length based on correlation (high = long trails)
  local max_trail = math.floor(corr * 60) + 5
  while #chaos_trail > max_trail do
    table.remove(chaos_trail, 1)
  end
end

-- ======== PARTICLES (Space page) ========

local function init_particles()
  particles = {}
  for i = 1, 30 do
    particles[i] = {
      x = math.random(0, 127),
      y = math.random(0, 63),
      vx = (math.random() - 0.5) * 2,
      vy = (math.random() - 0.5) * 1,
      life = math.random(20, 80),
      age = 0
    }
  end
end

local function update_particles()
  local rev_mix = params:get("reverb_mix")
  local del_time = params:get("delay_time")
  local frozen = params:get("delay_freeze") == 2 -- option: 1=off, 2=on

  for i = 1, #particles do
    local p = particles[i]
    if not frozen then
      p.x = p.x + p.vx * del_time
      p.y = p.y + p.vy
    end
    p.age = p.age + 1
    -- wrap
    if p.x < 0 then p.x = 127 end
    if p.x > 127 then p.x = 0 end
    if p.y < 0 then p.y = 63 end
    if p.y > 63 then p.y = 0 end
    -- respawn if too old
    if p.age > p.life then
      p.x = math.random(0, 127)
      p.y = math.random(0, 63)
      p.vx = (math.random() - 0.5) * 2
      p.vy = (math.random() - 0.5) * 1
      p.life = math.random(20, 80)
      p.age = 0
    end
  end
end

-- ======== SOFTCUT (Morphagene) ========

local function init_softcut()
  softcut.buffer_clear()
  -- voice 1: recorder (engine output -> softcut input)
  softcut.enable(1, 1)
  softcut.buffer(1, 1)
  softcut.level(1, 0)
  softcut.rate(1, 1)
  softcut.loop(1, 0)
  softcut.position(1, 0)
  softcut.rec_level(1, 1)
  softcut.pre_level(1, 0)
  softcut.level_input_cut(1, 1, 1)
  softcut.level_input_cut(2, 1, 1)
  softcut.rec(1, 0)
  softcut.play(1, 0)
  softcut.fade_time(1, 0.01)
  -- voice 2: playback with variable rate/loop
  softcut.enable(2, 1)
  softcut.buffer(2, 1)
  softcut.level(2, 1)
  softcut.rate(2, 1)
  softcut.loop(2, 1)
  softcut.loop_start(2, 0)
  softcut.loop_end(2, TAPE_BUF_SEC)
  softcut.position(2, 0)
  softcut.rec(2, 0)
  softcut.play(2, 0)
  softcut.fade_time(2, 0.01)
  softcut.rate_slew_time(2, 0.1)
  softcut.level_slew_time(2, 0.05)
  -- engine output -> softcut input
  audio.level_eng_cut(1)
  -- phase polling
  softcut.phase_quant(2, 0.05)
  softcut.event_phase(function(voice, pos)
    if voice == 2 then
      tape_phase = pos
      screen_dirty = true
    end
  end)
  softcut.poll_start_phase()
end

local function start_recording()
  tape_recording = true
  tape_rec_start = 0
  softcut.position(1, 0)
  softcut.rec(1, 1)
  softcut.play(1, 1)
  screen_dirty = true
end

local function stop_recording()
  tape_recording = false
  softcut.rec(1, 0)
  softcut.play(1, 0)
  -- start playback
  tape_playing = true
  local gene = params:get("gene_size")
  softcut.loop_start(2, 0)
  softcut.loop_end(2, gene)
  softcut.position(2, 0)
  softcut.rate(2, params:get("varispeed"))
  softcut.level(2, params:get("morph_mix"))
  softcut.play(2, 1)
  screen_dirty = true
end

local function update_softcut()
  if tape_playing then
    local gene = params:get("gene_size")
    local slide = params:get("slide_pos")
    local start = slide * (TAPE_BUF_SEC - gene)
    softcut.loop_start(2, start)
    softcut.loop_end(2, start + gene)
    softcut.rate(2, params:get("varispeed"))
    softcut.level(2, params:get("morph_mix"))
    -- sound-on-sound overdub
    local sos = params:get("sos_level")
    if sos > 0.01 then
      softcut.rec_level(2, 0.5)
      softcut.pre_level(2, sos)
      softcut.rec(2, 1)
    else
      softcut.rec(2, 0)
    end
  end
end

-- ======== SCREEN DRAWING ========

local function draw_header(name)
  screen.level(15)
  screen.font_size(8)
  screen.move(2, 8)
  screen.text(name)
  -- page dots (left of explorer area)
  for i = 1, #PAGES do
    screen.level(i == current_page and 15 or 3)
    screen.rect(50 + (i - 1) * 6, 3, 3, 3)
    screen.fill()
  end
end

local function draw_step_indicator()
  -- explorer phase indicator (top right area, below page dots)
  if explorer_on then
    screen.level(15)
    screen.font_size(8)
    local phase_name = EXPLORER_PHASES[explorer_phase] or ""
    screen.move(90, 8)
    screen.text(phase_name)
    -- progress bar
    local prog = explorer_tick / explorer_phase_lengths[explorer_phase]
    screen.level(7)
    screen.rect(90, 10, prog * 38, 2)
    screen.fill()
  end

  -- step indicator at bottom
  if not playing then
    -- show hint when not playing
    screen.level(3)
    screen.font_size(8)
    screen.move(2, 62)
    screen.text("K2:play")
    if explorer_on then
      screen.level(12)
      screen.move(60, 62)
      screen.text("EXPLORING")
    end
    return
  end
  for i = 1, seq.NUM_STEPS do
    local x = 2 + (i - 1) * 15
    local step = seq.get_step(i)
    if i == seq.current then
      screen.level(15)
    elseif step and step.on then
      screen.level(3)
    else
      screen.level(1)
    end
    screen.rect(x, 60, 12, 3)
    screen.fill()
  end
end

local function draw_voice_page()
  draw_header("VOICE")

  -- oscilloscope waveform
  compute_waveform()
  screen.level(12)
  for i = 1, 63 do
    local y1 = 34 - waveform_buf[i] * 16
    local y2 = 34 - waveform_buf[i + 1] * 16
    screen.move(i + 32, y1)
    screen.line(i + 33, y2)
    screen.stroke()
  end

  -- axis line
  screen.level(2)
  screen.move(32, 34)
  screen.line(96, 34)
  screen.stroke()

  -- shape name
  local shape = params:get("shape")
  local shape_name
  if shape < 0.33 then shape_name = "TRI"
  elseif shape < 0.66 then shape_name = "SAW"
  else shape_name = "PLS" end
  screen.level(7)
  screen.font_size(8)
  screen.move(2, 20)
  screen.text(shape_name)

  -- fold bar
  screen.level(5)
  screen.move(2, 28)
  screen.text("FOLD")
  local fold = params:get("fold_amt")
  screen.level(10)
  screen.rect(2, 30, fold * 26, 3)
  screen.fill()

  -- FM indicator
  screen.level(5)
  screen.move(2, 42)
  screen.text("FM")
  screen.level(8)
  local fm = math.min(params:get("fm_amt") / 2, 1)
  screen.rect(2, 44, fm * 26, 3)
  screen.fill()

  -- waveguide indicator
  local wg = params:get("wg_mix")
  if wg > 0.01 then
    screen.level(5)
    screen.move(2, 52)
    screen.text("WG")
    screen.level(6)
    screen.rect(2, 54, wg * 26, 3)
    screen.fill()
  end

  draw_step_indicator()
end

local function draw_filter_page()
  draw_header("FILTER")

  local cutoff = params:get("cutoff")
  local res = params:get("res")
  local radiate = params:get("radiate")
  local lpg = params:get("lpg_mode")

  -- QPAS: four resonant peak bars
  local center_x = 64
  local offsets = {-1.5, -0.5, 0.5, 1.5}
  for i = 1, 4 do
    local spread = radiate * 20
    local x = center_x + offsets[i] * spread
    local bar_w = 6
    local height = 10 + res * 12
    -- brightness varies with position
    local brightness = 12 - math.abs(offsets[i]) * 2
    screen.level(math.floor(brightness))
    screen.rect(x - bar_w / 2, 50 - height, bar_w, height)
    screen.fill()

    -- peak line on top
    screen.level(15)
    screen.rect(x - bar_w / 2, 50 - height, bar_w, 1)
    screen.fill()
  end

  -- base line
  screen.level(3)
  screen.move(10, 50)
  screen.line(118, 50)
  screen.stroke()

  -- cutoff value
  screen.level(7)
  screen.font_size(8)
  screen.move(2, 20)
  screen.text("CUT " .. math.floor(cutoff))

  -- radiate value
  screen.move(2, 30)
  screen.text("RAD " .. string.format("%.2f", radiate))

  -- LPG indicator
  if lpg == 2 then
    screen.level(15)
    screen.move(100, 20)
    screen.text("LPG")
  end

  draw_step_indicator()
end

local function draw_space_page()
  draw_header("SPACE")

  local rev_mix = params:get("reverb_mix")
  local rev_size = params:get("reverb_size")
  local del_time = params:get("delay_time")
  local frozen = params:get("delay_freeze") == 2

  -- particle field
  local visible_count = math.floor(rev_mix * 30)
  for i = 1, math.min(visible_count, #particles) do
    local p = particles[i]
    local fade = 1 - (p.age / p.life)
    local lvl = math.floor(fade * 12) + 1
    screen.level(lvl)
    if frozen then
      -- frozen: square particles
      screen.rect(math.floor(p.x), math.floor(p.y), 2, 2)
      screen.fill()
    else
      screen.pixel(math.floor(p.x), math.floor(p.y))
      screen.fill()
    end
  end

  -- info
  screen.level(7)
  screen.font_size(8)
  screen.move(2, 20)
  screen.text("REV " .. string.format("%.0f%%", rev_mix * 100))
  screen.move(2, 30)
  screen.text("SIZ " .. string.format("%.2f", rev_size))
  screen.move(70, 20)
  screen.text("DLY " .. string.format("%.2f", del_time) .. "s")

  if frozen then
    screen.level(15)
    screen.move(70, 30)
    screen.text("FREEZE")
  end

  draw_step_indicator()
end

local function draw_morph_page()
  draw_header("MORPH")

  local gene = params:get("gene_size")
  local speed = params:get("varispeed")
  local sos = params:get("sos_level")

  -- tape reel visualization
  -- left reel (supply)
  local lx, ly = 40, 32
  local rx, ry = 88, 32
  local reel_r = 12

  -- rotate based on playback
  if tape_playing then
    tape_angle = tape_angle + speed * 0.15
  end

  -- left reel
  screen.level(8)
  screen.move(lx + math.cos(tape_angle) * reel_r, ly + math.sin(tape_angle) * reel_r)
  for a = 0, 6 do
    local angle = tape_angle + a * math.pi / 3
    screen.line(lx + math.cos(angle) * reel_r, ly + math.sin(angle) * reel_r)
  end
  screen.stroke()
  -- center hub
  screen.level(5)
  screen.rect(lx - 2, ly - 2, 4, 4)
  screen.fill()

  -- right reel
  screen.level(8)
  screen.move(rx + math.cos(-tape_angle) * reel_r, ry + math.sin(-tape_angle) * reel_r)
  for a = 0, 6 do
    local angle = -tape_angle + a * math.pi / 3
    screen.line(rx + math.cos(angle) * reel_r, ry + math.sin(angle) * reel_r)
  end
  screen.stroke()
  screen.level(5)
  screen.rect(rx - 2, ry - 2, 4, 4)
  screen.fill()

  -- tape path between reels
  screen.level(6)
  screen.move(lx + reel_r, ly - 4)
  screen.line(rx - reel_r, ry - 4)
  screen.stroke()
  screen.move(lx + reel_r, ly + 4)
  screen.line(rx - reel_r, ry + 4)
  screen.stroke()

  -- splice markers on tape path
  local splice_count = math.floor(1 / math.max(gene, 0.05))
  splice_count = math.min(splice_count, 12)
  for i = 1, splice_count do
    local sx = lx + reel_r + (i / (splice_count + 1)) * (rx - lx - reel_r * 2)
    screen.level(12)
    screen.move(sx, ly - 6)
    screen.line(sx, ly + 6)
    screen.stroke()
  end

  -- playhead position
  if tape_playing then
    local head_x = lx + reel_r + (tape_phase / TAPE_BUF_SEC) * (rx - lx - reel_r * 2)
    screen.level(15)
    screen.move(head_x, ly - 8)
    screen.line(head_x, ly + 8)
    screen.stroke()
  end

  -- indicators
  if tape_recording then
    screen.level(15)
    screen.move(2, 20)
    screen.text("REC")
  end
  if sos > 0.01 then
    screen.level(12)
    screen.move(2, 30)
    screen.text("SOS")
  end

  -- params
  screen.level(7)
  screen.font_size(8)
  screen.move(2, 55)
  screen.text("SPD " .. string.format("%.2f", speed))
  screen.move(60, 55)
  screen.text("GEN " .. string.format("%.2f", gene))

  draw_step_indicator()
end

local function draw_chaos_page()
  draw_header("CHAOS")

  -- random walk trail
  for i = 1, #chaos_trail do
    local p = chaos_trail[i]
    local fade = i / #chaos_trail
    screen.level(math.floor(fade * 12) + 1)
    screen.pixel(math.floor(p.x), math.floor(p.y))
    screen.fill()
  end

  -- current position: bright dot
  screen.level(15)
  screen.rect(math.floor(chaos_x) - 1, math.floor(chaos_y) - 1, 3, 3)
  screen.fill()

  -- burst flash
  if burst_flash > 0 then
    screen.level(burst_flash * 2)
    screen.rect(math.floor(chaos_x) - 3, math.floor(chaos_y) - 3, 7, 7)
    screen.stroke()
  end

  -- mod routing bars at bottom
  screen.level(5)
  screen.font_size(8)
  local c2f = params:get("chaos_to_fold")
  local c2c = params:get("chaos_to_cutoff")
  local c2d = params:get("chaos_to_delay")

  -- fold routing
  screen.move(2, 55)
  screen.text("F")
  screen.level(10)
  screen.rect(10, 51, c2f * 30, 3)
  screen.fill()

  -- cutoff routing
  screen.level(5)
  screen.move(46, 55)
  screen.text("C")
  screen.level(8)
  screen.rect(54, 51, c2c * 30, 3)
  screen.fill()

  -- delay routing
  screen.level(5)
  screen.move(90, 55)
  screen.text("D")
  screen.level(6)
  screen.rect(98, 51, c2d * 30, 3)
  screen.fill()

  -- correlation display
  screen.level(7)
  screen.move(2, 20)
  screen.text("CORR " .. string.format("%.2f", params:get("correlation")))

  -- explorer toggle hint
  screen.level(explorer_on and 15 or 5)
  screen.move(2, 30)
  screen.text("K3:" .. (explorer_on and "EXPLORING" or "explore"))

  draw_step_indicator()
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)

  if current_page == 1 then draw_voice_page()
  elseif current_page == 2 then draw_filter_page()
  elseif current_page == 3 then draw_space_page()
  elseif current_page == 4 then draw_morph_page()
  elseif current_page == 5 then draw_chaos_page()
  end

  screen.update()
end

-- ======== ENCODERS & KEYS ========

function enc(n, d)
  if n == 1 then
    -- page select
    current_page = util.clamp(current_page + d, 1, #PAGES)
    screen_dirty = true
    return
  end

  if current_page == 1 then
    -- VOICE: E2=shape+fold, E3=FM+waveguide
    if n == 2 then
      -- shape and fold macro
      local shape = params:get("shape")
      local fold = params:get("fold_amt")
      if d > 0 then
        -- increasing: first shape, then fold
        if shape < 1 then
          params:set("shape", util.clamp(shape + d * 0.02, 0, 1))
        else
          params:set("fold_amt", util.clamp(fold + d * 0.02, 0, 1))
        end
      else
        if fold > 0 then
          params:set("fold_amt", util.clamp(fold + d * 0.02, 0, 1))
        else
          params:set("shape", util.clamp(shape + d * 0.02, 0, 1))
        end
      end
    elseif n == 3 then
      local fm = params:get("fm_amt")
      local wg = params:get("wg_mix")
      if d > 0 then
        if fm < 1 then
          params:set("fm_amt", util.clamp(fm + d * 0.03, 0, 2))
        else
          params:set("wg_mix", util.clamp(wg + d * 0.02, 0, 1))
        end
      else
        if wg > 0 then
          params:set("wg_mix", util.clamp(wg + d * 0.02, 0, 1))
        else
          params:set("fm_amt", util.clamp(fm + d * 0.03, 0, 2))
        end
      end
    end

  elseif current_page == 2 then
    -- FILTER: E2=cutoff, E3=radiate
    if n == 2 then
      local cut = params:get("cutoff")
      params:set("cutoff", util.clamp(cut * (1 + d * 0.03), 20, 18000))
    elseif n == 3 then
      params:delta("radiate", d * 0.02)
    end

  elseif current_page == 3 then
    -- SPACE: E2=reverb size+decay, E3=delay time
    if n == 2 then
      params:delta("reverb_size", d * 0.02)
      params:delta("reverb_decay", d * 0.02)
    elseif n == 3 then
      local dt = params:get("delay_time")
      params:set("delay_time", util.clamp(dt * (1 + d * 0.03), 0.01, 2))
    end

  elseif current_page == 4 then
    -- MORPH: E2=varispeed, E3=gene_size
    if n == 2 then
      params:delta("varispeed", d * 0.05)
    elseif n == 3 then
      local gs = params:get("gene_size")
      params:set("gene_size", util.clamp(gs * (1 + d * 0.05), 0.01, 2))
    end

  elseif current_page == 5 then
    -- CHAOS: E2=rates, E3=correlation
    if n == 2 then
      local sr = params:get("smooth_rate")
      local st = params:get("stepped_rate")
      params:set("smooth_rate", util.clamp(sr * (1 + d * 0.05), 0.01, 20))
      params:set("stepped_rate", util.clamp(st * (1 + d * 0.05), 0.01, 20))
    elseif n == 3 then
      params:delta("correlation", d * 0.02)
    end
  end

  screen_dirty = true
end

function key(n, z)
  if n == 2 and z == 1 then
    -- K2: play/stop or record
    if current_page == 4 then
      if tape_recording then stop_recording() else start_recording() end
    else
      if playing then stop_seq() else start_seq() end
    end
  elseif n == 3 and z == 1 then
    if current_page == 1 then
      -- cycle waveguide excitation
      local wge = params:get("wg_excite")
      params:set("wg_excite", wge == 1 and 2 or 1)
    elseif current_page == 2 then
      -- toggle LPG mode
      local lpg = params:get("lpg_mode")
      params:set("lpg_mode", lpg == 1 and 2 or 1)
    elseif current_page == 3 then
      -- toggle delay freeze
      local frz = params:get("delay_freeze")
      params:set("delay_freeze", frz == 1 and 2 or 1)
    elseif current_page == 4 then
      -- toggle SOS
      local sos = params:get("sos_level")
      params:set("sos_level", sos > 0.01 and 0 or 0.7)
    elseif current_page == 5 then
      -- toggle explorer
      if explorer_on then
        stop_explorer()
        params:set("explorer_mode", 1, true) -- silent set
      else
        start_explorer()
        params:set("explorer_mode", 2, true)
      end
    end
  end

  screen_dirty = true
end

-- ======== INIT ========

function init()
  -- sequencer
  seq.init()

  -- MIDI
  midi_out_device = midi.connect(1)
  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_event

  -- ======== PARAMS ========

  params:add_separator("JAM COAST")

  -- SEQUENCE
  params:add_group("SEQUENCE", 8)
  params:add_number("root_note", "root note", 24, 96, 48)
  params:set_action("root_note", function() build_scale() end)
  params:add_option("scale_type", "scale", SCALE_DISPLAY, 1)
  params:set_action("scale_type", function() build_scale() end)
  params:add_number("swing", "swing", 0, 80, 0)
  params:set_action("swing", function(x) seq.swing = x end)
  params:add_control("gate_length", "gate length",
    controlspec.new(0.1, 2.0, "lin", 0.01, 0.8, ""))
  params:add_number("probability", "probability", 0, 100, 100)
  params:set_action("probability", function(x) seq.probability = x end)
  params:add_number("octave_shift", "octave shift", -2, 2, 0)
  params:add_option("burst_mode", "burst mode", {"off", "on"}, 1)
  params:set_action("burst_mode", function(x) seq.burst_mode = (x == 2) end)
  params:add_control("burst_density", "burst density",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:set_action("burst_density", function(x) seq.burst_density = x end)

  -- VOICE
  params:add_group("VOICE", 6)
  params:add_control("shape", "shape",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:set_action("shape", function(x) engine.shape(x) end)
  params:add_control("fold_amt", "fold amount",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:set_action("fold_amt", function(x) engine.fold_amt(x) end)
  params:add_control("fm_amt", "FM amount",
    controlspec.new(0, 2, "lin", 0.01, 0, ""))
  params:set_action("fm_amt", function(x) engine.fm_amt(x) end)
  params:add_control("fm_ratio", "FM ratio",
    controlspec.new(0.25, 8, "exp", 0.01, 1.5, ""))
  params:set_action("fm_ratio", function(x) engine.fm_ratio(x) end)
  params:add_control("sub_amt", "sub osc",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:set_action("sub_amt", function(x) engine.sub_amt(x) end)
  params:add_control("wg_mix", "waveguide mix",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:set_action("wg_mix", function(x) engine.wg_mix(x) end)

  -- WAVEGUIDE
  params:add_group("WAVEGUIDE", 3)
  params:add_control("wg_decay", "wg decay",
    controlspec.new(0.1, 10, "exp", 0.01, 2, "s"))
  params:set_action("wg_decay", function(x) engine.wg_decay(x) end)
  params:add_control("wg_damp", "wg damping",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:set_action("wg_damp", function(x) engine.wg_damp(x) end)
  params:add_option("wg_excite", "wg exciter", {"noise", "osc"}, 1)
  params:set_action("wg_excite", function(x) engine.wg_excite(x - 1) end)

  -- FILTER
  params:add_group("FILTER", 5)
  params:add_control("cutoff", "cutoff",
    controlspec.new(20, 18000, "exp", 1, 2000, "Hz"))
  params:set_action("cutoff", function(x) engine.cutoff(x) end)
  params:add_control("res", "resonance",
    controlspec.new(0, 4, "lin", 0.01, 0.3, ""))
  params:set_action("res", function(x) engine.res(x) end)
  params:add_control("radiate", "radiate",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:set_action("radiate", function(x) engine.radiate(x) end)
  params:add_option("lpg_mode", "LPG mode", {"filter", "LPG"}, 1)
  params:set_action("lpg_mode", function(x) engine.lpg_mode(x - 1) end)
  params:add_control("lpg_decay", "LPG decay",
    controlspec.new(0.01, 2, "exp", 0.01, 0.3, "s"))
  params:set_action("lpg_decay", function(x) engine.lpg_decay(x) end)

  -- ENVELOPE
  params:add_group("ENVELOPE", 4)
  params:add_control("env_attack", "attack",
    controlspec.new(0.001, 2, "exp", 0.001, 0.005, "s"))
  params:set_action("env_attack", function(x) engine.attack(x) end)
  params:add_control("env_decay", "decay",
    controlspec.new(0.01, 2, "exp", 0.01, 0.3, "s"))
  params:set_action("env_decay", function(x) engine.env_decay(x) end)
  params:add_control("env_sustain", "sustain",
    controlspec.new(0, 1, "lin", 0.01, 0.6, ""))
  params:set_action("env_sustain", function(x) engine.sustain_level(x) end)
  params:add_control("env_release", "release",
    controlspec.new(0.01, 5, "exp", 0.01, 0.5, "s"))
  params:set_action("env_release", function(x) engine.release(x) end)

  -- DELAY
  params:add_group("DELAY", 5)
  params:add_control("delay_time", "delay time",
    controlspec.new(0.01, 2, "exp", 0.01, 0.3, "s"))
  params:set_action("delay_time", function(x) engine.delay_time(x) end)
  params:add_control("delay_fb", "delay feedback",
    controlspec.new(0, 0.95, "lin", 0.01, 0.4, ""))
  params:set_action("delay_fb", function(x) engine.delay_fb(x) end)
  params:add_control("delay_color", "delay color",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:set_action("delay_color", function(x) engine.delay_color(x) end)
  params:add_option("delay_freeze", "delay freeze", {"off", "on"}, 1)
  params:set_action("delay_freeze", function(x) engine.delay_freeze(x - 1) end)
  params:add_control("delay_mix", "delay mix",
    controlspec.new(0, 1, "lin", 0.01, 0.2, ""))
  params:set_action("delay_mix", function(x) engine.delay_mix(x) end)

  -- REVERB
  params:add_group("REVERB", 6)
  params:add_control("reverb_mix", "reverb mix",
    controlspec.new(0, 1, "lin", 0.01, 0.15, ""))
  params:set_action("reverb_mix", function(x) engine.reverb_mix(x) end)
  params:add_control("reverb_size", "reverb size",
    controlspec.new(0, 1, "lin", 0.01, 0.7, ""))
  params:set_action("reverb_size", function(x) engine.reverb_size(x) end)
  params:add_control("reverb_decay", "reverb decay",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:set_action("reverb_decay", function(x) engine.reverb_decay(x) end)
  params:add_control("reverb_absorb", "reverb absorb",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:set_action("reverb_absorb", function(x) engine.reverb_absorb(x) end)
  params:add_control("reverb_mod_speed", "reverb mod speed",
    controlspec.new(0.01, 5, "exp", 0.01, 0.1, "Hz"))
  params:set_action("reverb_mod_speed", function(x) engine.reverb_mod_speed(x) end)
  params:add_control("reverb_mod_depth", "reverb mod depth",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:set_action("reverb_mod_depth", function(x) engine.reverb_mod_depth(x) end)

  -- MORPH (softcut/Morphagene)
  params:add_group("MORPH", 5)
  params:add_control("gene_size", "gene size",
    controlspec.new(0.01, 2, "exp", 0.01, 0.25, "s"))
  params:add_control("slide_pos", "slide position",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:add_control("varispeed", "varispeed",
    controlspec.new(-2, 2, "lin", 0.01, 1, "x"))
  params:add_control("sos_level", "SOS level",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:add_control("morph_mix", "morph mix",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))

  -- CHAOS (Wogglebug)
  params:add_group("CHAOS", 8)
  params:add_control("smooth_rate", "smooth rate",
    controlspec.new(0.01, 20, "exp", 0.01, 0.5, "Hz"))
  params:add_control("stepped_rate", "stepped rate",
    controlspec.new(0.01, 20, "exp", 0.01, 1, "Hz"))
  params:add_control("burst_rate", "burst rate",
    controlspec.new(0.1, 30, "exp", 0.1, 5, "Hz"))
  params:add_control("correlation", "correlation",
    controlspec.new(0, 1, "lin", 0.01, 0.5, ""))
  params:add_control("chaos_to_fold", "chaos > fold",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:add_control("chaos_to_cutoff", "chaos > cutoff",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:add_control("chaos_to_delay", "chaos > delay",
    controlspec.new(0, 1, "lin", 0.01, 0, ""))
  params:add_option("explorer_mode", "explorer", {"off", "on"}, 1)
  params:set_action("explorer_mode", function(x)
    if x == 2 and not explorer_on then start_explorer()
    elseif x == 1 and explorer_on then stop_explorer() end
  end)

  -- MIDI
  params:add_group("MIDI", 5)
  params:add_number("midi_out_ch", "midi out ch", 0, 16, 0)
  params:add_number("midi_in_ch", "midi in ch", 0, 16, 0)
  -- OP-XY
  local midi_devices = {"none"}
  for i = 1, #midi.vports do
    local name = midi.vports[i].name or ("port " .. i)
    table.insert(midi_devices, i .. ": " .. name)
  end
  params:add_option("opxy_device", "OP-XY device", midi_devices, 1)
  params:set_action("opxy_device", function(x)
    if x > 1 then
      opxy_device = midi.connect(x - 1)
    else
      opxy_device = nil
    end
  end)
  params:add_number("opxy_melody_ch", "OP-XY melody ch", 1, 16, 1)
  params:add_number("opxy_drum_ch", "OP-XY drum ch", 1, 16, 10)

  -- ======== SOFTCUT ========
  init_softcut()

  -- ======== PARTICLES ========
  init_particles()

  -- ======== WAVEFORM ========
  for i = 1, 64 do waveform_buf[i] = 0 end

  -- ======== SCALE ========
  build_scale()

  -- ======== SCREEN METRO ========
  screen_metro = metro.init()
  screen_metro.event = function()
    update_chaos()
    update_particles()
    update_softcut()
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
    -- always dirty when playing, exploring, or chaos active
    if playing or explorer_on then screen_dirty = true end
    if params:get("chaos_to_fold") > 0.01 or
       params:get("chaos_to_cutoff") > 0.01 or
       params:get("chaos_to_delay") > 0.01 then
      screen_dirty = true
    end
  end
  screen_metro.time = 1/15
  screen_metro:start()

  -- finalize
  params:read()
  params:bang()
end

-- ======== CLEANUP ========

function cleanup()
  stop_explorer()
  if seq_clock_id then clock.cancel(seq_clock_id) end
  if screen_metro then screen_metro:stop() end
  note_off()
  -- flush MIDI
  if midi_out_device then
    for note = 0, 127 do
      midi_out_device:note_off(note, 0, 1)
    end
  end
  if opxy_device then
    for ch = 1, 16 do
      for note = 0, 127 do
        opxy_device:note_off(note, 0, ch)
      end
    end
  end
  -- softcut cleanup
  softcut.rec(1, 0)
  softcut.play(1, 0)
  softcut.play(2, 0)
  softcut.buffer_clear()
  softcut.poll_stop_phase()
end
