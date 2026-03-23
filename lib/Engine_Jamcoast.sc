// Engine_Jamcoast
// West Coast synthesizer inspired by Make Noise instruments
//
// DPO:         triangle-core oscillator, wavefolding, complex FM
// Mysteron:    digital waveguide physical modeling
// QPAS:        quad-peak animated filter (formant vowels)
// Optomix:     low-pass gate (coupled amplitude + brightness)
// Maths:       function generator envelopes
// Strega:      feedback delay with color filter
// Erbe-Verb:   resonant reverb with modulation
// Morphagene:  granular via softcut (Lua side)
// Wogglebug:   chaotic modulation (Lua side)
//
// Signal: voice -> fxBus -> delay -> reverb -> out

Engine_Jamcoast : CroneEngine {

    var pg;
    var fxGroup;
    var voices;
    var params;
    var fxBus;
    var delaySynth;
    var reverbSynth;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        fxBus = Bus.audio(context.server, 2);

        pg = ParGroup.new(context.xg);
        fxGroup = Group.after(pg);

        voices = Dictionary.new;
        params = Dictionary.new;

        // --- defaults ---
        params[\shape] = 0;
        params[\foldAmt] = 0;
        params[\fmAmt] = 0;
        params[\fmRatio] = 1.5;
        params[\subAmt] = 0;
        params[\wgMix] = 0;
        params[\wgDecay] = 2;
        params[\wgDamp] = 0.5;
        params[\wgExcite] = 0;
        params[\cutoff] = 2000;
        params[\res] = 0.3;
        params[\radiate] = 0;
        params[\lpgMode] = 0;
        params[\lpgDecay] = 0.3;
        params[\attack] = 0.005;
        params[\decay] = 0.3;
        params[\sustain] = 0.6;
        params[\release] = 0.5;
        params[\pan] = 0;

        // ======== SYNTHDEFS ========

        // --- Main voice (DPO + Mysteron + QPAS + Optomix) ---
        SynthDef(\jc_voice, {
            arg out, freq=440, amp=0.5, pan=0, gate=1,
                shape=0, foldAmt=0,
                fmAmt=0, fmRatio=1.5,
                subAmt=0,
                wgMix=0, wgDecay=2, wgDamp=0.5, wgExcite=0,
                cutoff=2000, res=0.3, radiate=0,
                lpgMode=0, lpgDecay=0.3,
                attack=0.005, decay=0.3, sustain=0.6, release=0.5;

            var sig, env, fm, sub, osc, wg, filt;
            var lpgEnv, lpgCut, lpgAmp;
            var exciter, trig;

            // ---- DPO: complex oscillator ----

            // FM modulator (internal oscillator B)
            fm = SinOsc.ar(freq * fmRatio) * fmAmt * freq;

            // triangle-core with continuous shape morph
            // 0 = triangle, 0.5 = saw, 1.0 = pulse
            osc = SelectX.ar(shape * 2, [
                LFTri.ar(freq + fm),
                LFSaw.ar(freq + fm),
                Pulse.ar(freq + fm, 0.5)
            ]);

            // sub oscillator (octave down sine)
            sub = SinOsc.ar(freq * 0.5) * subAmt;
            osc = osc + sub;

            // Buchla-style multi-stage wavefolder
            // this is THE Make Noise sound — harmonically rich folding
            sig = osc * foldAmt.linexp(0, 1, 1, 16);
            sig = sig.fold2(1.0);
            sig = sig.fold2(1.0);
            sig = sig.fold2(1.0);
            sig = sig.fold2(1.0);
            // gain compensation
            sig = sig * foldAmt.linexp(0, 1, 1, 16).reciprocal.sqrt;
            // blend: dry osc at fold=0, fully folded at fold=1
            sig = (osc * (1 - foldAmt)) + (sig * foldAmt);

            // ---- Mysteron: waveguide physical model ----

            trig = gate;  // trigger on note-on
            // exciter: 0=noise burst, 1=oscillator feed
            exciter = SelectX.ar(wgExcite, [
                WhiteNoise.ar * EnvGen.ar(Env.perc(0.001, 0.01), trig),
                osc * EnvGen.ar(Env.perc(0.001, 0.03), trig) * 0.5
            ]);

            wg = Pluck.ar(
                exciter,
                trig,
                1/20,               // max delay (lowest freq ~20Hz)
                1/freq,             // delay = 1/freq for pitch
                wgDecay,            // decay time
                wgDamp.linlin(0, 1, 0.99, 0.1)  // coef: 0=bright, 1=dark
            );

            // crossfade oscillator and waveguide
            sig = (sig * (1 - wgMix)) + (wg * wgMix);

            // ---- QPAS: quad-peak animated filter ----

            // four bandpass filters with radiate-controlled spacing
            // wider bandwidth (rq) so peaks don't lose energy
            filt = Mix.new([
                BPF.ar(sig, (cutoff * (1 + (radiate * -1.5))).clip(40, 16000), 1 / (res.max(0.5) * 1.5)),
                BPF.ar(sig, (cutoff * (1 + (radiate * -0.5))).clip(40, 16000), 1 / (res.max(0.5) * 1.5)),
                BPF.ar(sig, (cutoff * (1 + (radiate * 0.5))).clip(40, 16000), 1 / (res.max(0.5) * 1.5)),
                BPF.ar(sig, (cutoff * (1 + (radiate * 1.5))).clip(40, 16000), 1 / (res.max(0.5) * 1.5))
            ]);

            // blend filtered with dry: always keep strong dry signal
            // radiate controls how much of the formant character comes through
            sig = (sig * (1 - (radiate * 0.5))) + (filt * radiate.max(0.1) * 2);

            // main low-pass so cutoff always does something audible
            sig = RLPF.ar(sig, cutoff.clip(60, 18000), (1 / (res.max(0.3) + 1)).clip(0.1, 1));

            // ---- Optomix: low-pass gate ----

            // vactrol-style: fast attack, slow logarithmic decay
            lpgEnv = EnvGen.kr(
                Env.perc(0.001, lpgDecay * 3, 1, -8),
                trig
            );
            // LPG cutoff never goes below 400 (stays audible)
            lpgCut = lpgEnv.linexp(0, 1, 400, 12000);
            lpgAmp = lpgEnv.max(0.05); // never fully silent

            // standard ADSR envelope (always active)
            env = EnvGen.kr(
                Env.adsr(attack, decay, sustain, release),
                gate, doneAction: Done.freeSelf
            );

            // LPG mode: blend between ADSR-only and LPG-coupled
            sig = Select.ar(lpgMode, [
                // mode 0: standard RLPF + ADSR
                sig * env,
                // mode 1: LPG adds vactrol character on top of ADSR
                LPF.ar(sig, lpgCut) * env * lpgAmp
            ]);

            sig = sig * amp;
            sig = Pan2.ar(sig, pan.clip(-1, 1));

            Out.ar(out, sig);
        }).add;

        // --- Strega/Mimeophon delay ---
        SynthDef(\jc_delay, {
            arg in, out, time=0.3, fb=0.4, mix=0.2, color=0.5, freeze=0;
            var dry, wet, fbSig;

            dry = In.ar(in, 2);

            // feedback with color filter
            fbSig = LocalIn.ar(2) * fb;
            // color: 0=dark (LPF dominant), 1=bright (HPF boost)
            fbSig = LPF.ar(fbSig, color.linexp(0, 1, 800, 12000));
            fbSig = HPF.ar(fbSig, color.linexp(0, 1, 20, 400));

            // freeze: when on, no new input enters, feedback loops infinitely
            wet = Select.ar(freeze, [
                dry + fbSig,
                fbSig * 1.0  // frozen: only feedback, boosted to sustain
            ]);

            wet = DelayC.ar(wet, 2.0, time.clip(0.001, 2.0));
            // soft saturation in feedback path (Strega-like warmth)
            wet = wet.tanh;

            LocalOut.ar(wet);

            Out.ar(out, (dry * (1 - mix)) + (wet * mix));
        }).add;

        // --- Erbe-Verb inspired reverb ---
        SynthDef(\jc_reverb, {
            arg bus, mix=0.15, size=0.7, decayTime=0.5, absorb=0.5,
                modSpeed=0.1, modDepth=0;
            var sig, wet;
            var combTimes, combSigs;

            sig = In.ar(bus, 2);

            // base reverb
            wet = FreeVerb2.ar(sig[0], sig[1], 1.0, size, absorb);

            // extended decay: parallel comb filters for resonant/infinite mode
            // adds shimmer and sustain beyond what FreeVerb can do
            combTimes = [0.0397, 0.0453, 0.0541, 0.0631];
            combSigs = Mix.new(combTimes.collect({ arg t, i;
                var modT = t * size.linlin(0, 1, 0.5, 2.0);
                var mod = SinOsc.kr(modSpeed * (i + 1) * 0.7) * modDepth * 0.002;
                CombL.ar(sig, 0.2, (modT + mod).clip(0.001, 0.2), decayTime.linlin(0, 1, 0.5, 20))
            })) * 0.15;

            // blend combs with freeverb
            wet = wet + (combSigs * decayTime.linlin(0, 0.5, 0, 1).clip(0, 1));

            // absorb: additional HF damping on the total wet signal
            wet = LPF.ar(wet, absorb.linexp(0, 1, 18000, 2000));

            // final mix
            wet = (sig * (1 - mix)) + (wet * mix);

            ReplaceOut.ar(bus, wet);
        }).add;

        context.server.sync;

        // start effects chain
        delaySynth = Synth(\jc_delay, [
            \in, fxBus, \out, context.out_b,
            \time, 0.3, \fb, 0.4, \mix, 0.2, \color, 0.5, \freeze, 0
        ], fxGroup);

        reverbSynth = Synth.after(delaySynth, \jc_reverb, [
            \bus, context.out_b, \mix, 0.15, \size, 0.7,
            \decayTime, 0.5, \absorb, 0.5, \modSpeed, 0.1, \modDepth, 0
        ]);

        // ======== COMMANDS ========

        // --- note on/off ---
        this.addCommand("note_on", "iff", { arg msg;
            var note = msg[1].asInteger;
            var freq = msg[2].asFloat;
            var vel = msg[3].asFloat;
            if(voices[note].notNil, {
                voices[note].set(\gate, 0);
                voices[note] = nil;
            });
            voices[note] = Synth(\jc_voice, [
                \out, fxBus, \freq, freq, \amp, vel, \gate, 1,
                \shape, params[\shape], \foldAmt, params[\foldAmt],
                \fmAmt, params[\fmAmt], \fmRatio, params[\fmRatio],
                \subAmt, params[\subAmt],
                \wgMix, params[\wgMix], \wgDecay, params[\wgDecay],
                \wgDamp, params[\wgDamp], \wgExcite, params[\wgExcite],
                \cutoff, params[\cutoff], \res, params[\res],
                \radiate, params[\radiate],
                \lpgMode, params[\lpgMode], \lpgDecay, params[\lpgDecay],
                \attack, params[\attack], \decay, params[\decay],
                \sustain, params[\sustain], \release, params[\release],
                \pan, params[\pan]
            ], pg);
        });

        this.addCommand("note_off", "i", { arg msg;
            var note = msg[1].asInteger;
            if(voices[note].notNil, {
                voices[note].set(\gate, 0);
                voices[note] = nil;
            });
        });

        // --- oscillator / voice ---
        this.addCommand("shape", "f", { arg msg;
            params[\shape] = msg[1].asFloat;
            voices.do({ arg s; s.set(\shape, msg[1].asFloat) });
        });
        this.addCommand("fold_amt", "f", { arg msg;
            params[\foldAmt] = msg[1].asFloat;
            voices.do({ arg s; s.set(\foldAmt, msg[1].asFloat) });
        });
        this.addCommand("fm_amt", "f", { arg msg;
            params[\fmAmt] = msg[1].asFloat;
            voices.do({ arg s; s.set(\fmAmt, msg[1].asFloat) });
        });
        this.addCommand("fm_ratio", "f", { arg msg;
            params[\fmRatio] = msg[1].asFloat;
            voices.do({ arg s; s.set(\fmRatio, msg[1].asFloat) });
        });
        this.addCommand("sub_amt", "f", { arg msg;
            params[\subAmt] = msg[1].asFloat;
        });

        // --- waveguide ---
        this.addCommand("wg_mix", "f", { arg msg;
            params[\wgMix] = msg[1].asFloat;
            voices.do({ arg s; s.set(\wgMix, msg[1].asFloat) });
        });
        this.addCommand("wg_decay", "f", { arg msg;
            params[\wgDecay] = msg[1].asFloat;
            voices.do({ arg s; s.set(\wgDecay, msg[1].asFloat) });
        });
        this.addCommand("wg_damp", "f", { arg msg;
            params[\wgDamp] = msg[1].asFloat;
            voices.do({ arg s; s.set(\wgDamp, msg[1].asFloat) });
        });
        this.addCommand("wg_excite", "f", { arg msg;
            params[\wgExcite] = msg[1].asFloat;
        });

        // --- filter ---
        this.addCommand("cutoff", "f", { arg msg;
            params[\cutoff] = msg[1].asFloat;
            voices.do({ arg s; s.set(\cutoff, msg[1].asFloat) });
        });
        this.addCommand("res", "f", { arg msg;
            params[\res] = msg[1].asFloat;
            voices.do({ arg s; s.set(\res, msg[1].asFloat) });
        });
        this.addCommand("radiate", "f", { arg msg;
            params[\radiate] = msg[1].asFloat;
            voices.do({ arg s; s.set(\radiate, msg[1].asFloat) });
        });
        this.addCommand("lpg_mode", "f", { arg msg;
            params[\lpgMode] = msg[1].asFloat;
        });
        this.addCommand("lpg_decay", "f", { arg msg;
            params[\lpgDecay] = msg[1].asFloat;
        });

        // --- envelope ---
        this.addCommand("attack", "f", { arg msg; params[\attack] = msg[1].asFloat; });
        this.addCommand("env_decay", "f", { arg msg; params[\decay] = msg[1].asFloat; });
        this.addCommand("sustain_level", "f", { arg msg; params[\sustain] = msg[1].asFloat; });
        this.addCommand("release", "f", { arg msg; params[\release] = msg[1].asFloat; });

        // --- delay ---
        this.addCommand("delay_time", "f", { arg msg; delaySynth.set(\time, msg[1].asFloat); });
        this.addCommand("delay_fb", "f", { arg msg; delaySynth.set(\fb, msg[1].asFloat); });
        this.addCommand("delay_color", "f", { arg msg; delaySynth.set(\color, msg[1].asFloat); });
        this.addCommand("delay_freeze", "f", { arg msg; delaySynth.set(\freeze, msg[1].asFloat); });
        this.addCommand("delay_mix", "f", { arg msg; delaySynth.set(\mix, msg[1].asFloat); });

        // --- reverb ---
        this.addCommand("reverb_mix", "f", { arg msg; reverbSynth.set(\mix, msg[1].asFloat); });
        this.addCommand("reverb_size", "f", { arg msg; reverbSynth.set(\size, msg[1].asFloat); });
        this.addCommand("reverb_decay", "f", { arg msg; reverbSynth.set(\decayTime, msg[1].asFloat); });
        this.addCommand("reverb_absorb", "f", { arg msg; reverbSynth.set(\absorb, msg[1].asFloat); });
        this.addCommand("reverb_mod_speed", "f", { arg msg; reverbSynth.set(\modSpeed, msg[1].asFloat); });
        this.addCommand("reverb_mod_depth", "f", { arg msg; reverbSynth.set(\modDepth, msg[1].asFloat); });

        // --- misc ---
        this.addCommand("pan", "f", { arg msg; params[\pan] = msg[1].asFloat; });
    }

    free {
        voices.do({ arg s; s.free });
        delaySynth.free;
        reverbSynth.free;
        fxBus.free;
    }
}
