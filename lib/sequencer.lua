-- sequencer.lua
-- 8-step sequencer with Wogglebug-inspired burst mode
-- per-step wavefold and FM overrides

local seq = {}

seq.NUM_STEPS = 8
seq.steps = {}
seq.current = 0
seq.playing = false
seq.burst_mode = false
seq.burst_density = 0.5
seq.probability = 100
seq.swing = 0
seq.swing_count = 0

-- initialize default pattern
function seq.init()
  for i = 1, seq.NUM_STEPS do
    seq.steps[i] = {
      note = 0,         -- semitone offset from root
      vel = 0.8,        -- 0-1
      gate_len = 0.5,   -- multiplier on step duration
      fold_amt = -1,    -- -1 = use global, 0-1 = per-step override
      fm_amt = -1,      -- -1 = use global, 0-1 = per-step override
      on = true         -- step active
    }
  end
  -- default pattern: west coast melodic sequence
  -- intervals that sound good through a wavefolder
  local default_notes = {0, 7, 3, 12, 5, -5, 10, 7}
  local default_vels =  {0.9, 0.7, 0.6, 0.85, 0.8, 0.5, 0.75, 0.65}
  local default_gates = {0.6, 0.4, 0.8, 0.3, 0.5, 1.0, 0.4, 0.7}
  local default_on =    {true, true, true, true, true, false, true, true}
  for i = 1, seq.NUM_STEPS do
    seq.steps[i].note = default_notes[i]
    seq.steps[i].vel = default_vels[i]
    seq.steps[i].gate_len = default_gates[i]
    seq.steps[i].on = default_on[i]
  end
end

-- advance to next step, returns step data or nil if skipped
function seq.advance()
  seq.current = seq.current + 1
  if seq.current > seq.NUM_STEPS then seq.current = 1 end

  local step = seq.steps[seq.current]

  -- step disabled
  if not step.on then return nil end

  -- probability gate
  if math.random(100) > seq.probability then return nil end

  -- burst mode: Wogglebug-style probabilistic triggering
  if seq.burst_mode then
    if math.random() > seq.burst_density then return nil end
  end

  return step
end

-- get swing delay in beats for current step
function seq.get_swing_delay()
  seq.swing_count = seq.swing_count + 1
  if seq.swing_count % 2 == 0 then
    return (seq.swing / 100) * 0.5  -- delay even steps
  end
  return 0
end

-- reset to beginning
function seq.reset()
  seq.current = 0
  seq.swing_count = 0
end

-- get step data
function seq.get_step(n)
  if n >= 1 and n <= seq.NUM_STEPS then
    return seq.steps[n]
  end
  return nil
end

-- set step field
function seq.set_step(n, field, value)
  if n >= 1 and n <= seq.NUM_STEPS and seq.steps[n] then
    seq.steps[n][field] = value
  end
end

-- toggle step on/off
function seq.toggle_step(n)
  if n >= 1 and n <= seq.NUM_STEPS then
    seq.steps[n].on = not seq.steps[n].on
  end
end

return seq
