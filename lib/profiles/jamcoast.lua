-- jamcoast
-- engine: Jamcoast
-- west coast synthesizer inspired by Make Noise
--
-- robot strategy: WAVEFOLDER FIRST. the wavefolder is the soul of
-- west coast synthesis — robot rides it like a DJ rides a filter.
-- chaos modulation (wogglebug) is the secondary lever — routing
-- random voltages into fold depth creates organic, living timbres.
--
-- FM amount and ratio for timbral complexity shifts.
-- QPAS radiate for formant morphing (vowel-like sweeps).
-- waveguide mix for physical modeling resonance moments.
-- reverb decay/freeze for dramatic structural moments.
-- delay freeze for building tension.
--
-- the philosophy: Make Noise instruments reward exploration and
-- happy accidents. robot should push toward unexpected territories
-- while maintaining musical coherence. chaos is a creative force,
-- not noise — every random change should feel intentional.

return {
  name = "jamcoast",
  description = "West coast synth - wavefolder, waveguide, QPAS filter, granular, chaos modulation",
  phrase_len = 8,

  recommended_modes = {2, 4, 6, 10, 7},  -- SPIRITUAL, AMBIENT, MINIMALIST, CHAOS, DRUNK

  never_touch = {
    "clock_tempo",
    "clock_source",
    "midi_out_ch",
    "midi_in_ch",
    "opxy_device",
    "opxy_melody_ch",
    "opxy_drum_ch",
    "root_note",      -- player territory
    "scale_type",     -- player territory
  },

  params = {
    ---------- PRIMARY: wavefolder is THE Make Noise lever ----------
    fold_amt = {
      group = "timbral",
      weight = 1.0,
      sensitivity = 1.0,
      direction = "both",
      -- robot should RIDE this. slow sweeps for builds, sudden
      -- jumps for timbral explosions. the heart of west coast.
      range_lo = 0,
      range_hi = 0.85,
      euclidean_pulses = 7,
    },
    chaos_to_fold = {
      group = "timbral",
      weight = 0.9,
      sensitivity = 0.7,
      direction = "both",
      -- routing wogglebug into the wavefolder creates organic,
      -- breathing timbral evolution. the make noise secret sauce.
      range_lo = 0,
      range_hi = 0.8,
      euclidean_pulses = 7,
    },

    ---------- TIMBRAL ----------
    shape = {
      group = "timbral",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0,
      range_hi = 1,
      euclidean_pulses = 5,
    },
    fm_amt = {
      group = "timbral",
      weight = 0.8,
      sensitivity = 0.6,
      direction = "both",
      -- FM creates metallic, clangorous DPO-style timbres.
      -- moderate amounts are musical; extreme = harsh.
      range_lo = 0,
      range_hi = 1.2,
      euclidean_pulses = 5,
    },
    fm_ratio = {
      group = "timbral",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      -- integer ratios = harmonic. non-integer = inharmonic/metallic.
      range_lo = 0.5,
      range_hi = 4,
      euclidean_pulses = 3,
    },
    sub_amt = {
      group = "timbral",
      weight = 0.3,
      sensitivity = 0.3,
      direction = "up",
      range_lo = 0,
      range_hi = 0.6,
      euclidean_pulses = 3,
    },
    wg_mix = {
      group = "timbral",
      weight = 0.7,
      sensitivity = 0.5,
      direction = "both",
      -- waveguide blend for mysteron-style plucked resonance.
      -- beautiful for transitional moments.
      range_lo = 0,
      range_hi = 0.8,
      euclidean_pulses = 5,
    },
    wg_decay = {
      group = "timbral",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.5,
      range_hi = 6,
      euclidean_pulses = 3,
    },
    wg_damp = {
      group = "timbral",
      weight = 0.4,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0.1,
      range_hi = 0.9,
      euclidean_pulses = 5,
    },
    cutoff = {
      group = "timbral",
      weight = 0.9,
      sensitivity = 0.8,
      direction = "both",
      -- classic filter sweeps. QPAS center frequency.
      range_lo = 200,
      range_hi = 8000,
      euclidean_pulses = 7,
    },
    res = {
      group = "timbral",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
      -- high res = screaming peaks. keep musical.
      range_lo = 0,
      range_hi = 2.5,
      euclidean_pulses = 5,
    },
    radiate = {
      group = "timbral",
      weight = 0.7,
      sensitivity = 0.6,
      direction = "both",
      -- QPAS formant spread. sweeping this creates vowel
      -- morphing — the most vocal, human quality in the synth.
      range_lo = 0,
      range_hi = 0.8,
      euclidean_pulses = 5,
    },
    lpg_decay = {
      group = "rhythmic",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.05,
      range_hi = 1.5,
      euclidean_pulses = 5,
    },
    pan = {
      group = "timbral",
      weight = 0.4,
      sensitivity = 0.5,
      direction = "both",
      range_lo = -0.7,
      range_hi = 0.7,
      euclidean_pulses = 7,
    },

    ---------- RHYTHMIC ----------
    env_attack = {
      group = "rhythmic",
      weight = 0.4,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.001,
      range_hi = 0.5,
      euclidean_pulses = 3,
    },
    env_decay = {
      group = "rhythmic",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.05,
      range_hi = 1.5,
      euclidean_pulses = 5,
    },
    env_sustain = {
      group = "rhythmic",
      weight = 0.3,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0.1,
      range_hi = 0.9,
      euclidean_pulses = 5,
    },
    env_release = {
      group = "rhythmic",
      weight = 0.4,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.05,
      range_hi = 3,
      euclidean_pulses = 3,
    },
    gate_length = {
      group = "rhythmic",
      weight = 0.5,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0.15,
      range_hi = 1.8,
      euclidean_pulses = 5,
    },
    probability = {
      group = "rhythmic",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 50,
      range_hi = 100,
      euclidean_pulses = 7,
    },
    burst_density = {
      group = "rhythmic",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
      -- wogglebug burst density — controls how often steps fire
      -- in burst mode. higher = more dense, lower = sparse.
      range_lo = 0.1,
      range_hi = 0.8,
      euclidean_pulses = 7,
    },
    swing = {
      group = "rhythmic",
      weight = 0.3,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0,
      range_hi = 50,
      euclidean_pulses = 3,
    },

    ---------- SPACE (structural — changes the whole character) ----------
    reverb_size = {
      group = "structural",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.1,
      range_hi = 0.95,
      euclidean_pulses = 3,
    },
    reverb_decay = {
      group = "structural",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
      -- near-infinite for erbe-verb moments. dramatic.
      range_lo = 0.2,
      range_hi = 0.95,
      euclidean_pulses = 3,
    },
    reverb_mix = {
      group = "structural",
      weight = 0.4,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0,
      range_hi = 0.6,
      euclidean_pulses = 3,
    },
    reverb_mod_depth = {
      group = "structural",
      weight = 0.3,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0,
      range_hi = 0.5,
      euclidean_pulses = 5,
    },
    delay_time = {
      group = "structural",
      weight = 0.4,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.05,
      range_hi = 1.0,
      euclidean_pulses = 3,
    },
    delay_fb = {
      group = "structural",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0.1,
      range_hi = 0.85,
      euclidean_pulses = 5,
    },
    delay_color = {
      group = "structural",
      weight = 0.3,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0.1,
      range_hi = 0.9,
      euclidean_pulses = 5,
    },
    delay_mix = {
      group = "structural",
      weight = 0.3,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0,
      range_hi = 0.5,
      euclidean_pulses = 3,
    },

    ---------- MORPH (granular — textural transformation) ----------
    gene_size = {
      group = "structural",
      weight = 0.7,
      sensitivity = 0.5,
      direction = "both",
      -- morphagene gene size. small = granular clouds,
      -- large = recognizable loops.
      range_lo = 0.02,
      range_hi = 1.5,
      euclidean_pulses = 5,
    },
    varispeed = {
      group = "structural",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
      -- tape speed. negative = reverse. zero = frozen.
      range_lo = -1.5,
      range_hi = 1.5,
      euclidean_pulses = 3,
    },
    morph_mix = {
      group = "structural",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0,
      range_hi = 0.7,
      euclidean_pulses = 3,
    },

    ---------- CHAOS (wogglebug — generative evolution) ----------
    smooth_rate = {
      group = "melodic",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0.05,
      range_hi = 8,
      euclidean_pulses = 5,
    },
    stepped_rate = {
      group = "melodic",
      weight = 0.5,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0.1,
      range_hi = 10,
      euclidean_pulses = 5,
    },
    correlation = {
      group = "melodic",
      weight = 0.8,
      sensitivity = 0.6,
      direction = "both",
      -- how much each random value relates to the previous.
      -- high = smooth melodic drift. low = wild jumps.
      range_lo = 0.1,
      range_hi = 0.95,
      euclidean_pulses = 7,
    },
    chaos_to_cutoff = {
      group = "melodic",
      weight = 0.7,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0,
      range_hi = 0.7,
      euclidean_pulses = 5,
    },
    chaos_to_delay = {
      group = "melodic",
      weight = 0.4,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 0,
      range_hi = 0.5,
      euclidean_pulses = 3,
    },

    ---------- RARE STRUCTURAL ----------
    octave_shift = {
      group = "structural",
      weight = 0.15,
      sensitivity = 0.2,
      direction = "both",
      range_lo = -1,
      range_hi = 1,
      euclidean_pulses = 3,
    },
  },
}
