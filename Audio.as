Audio::Sample@ LoadSampleRel(const string &in relPath) {
    if (relPath.Length == 0) {
        return null;
    }

    try {
        Audio::Sample@ s = Audio::LoadSample(relPath);
        if (s !is null) {
            return s;
        }
    } catch {
        warn("[Moon] LoadSample threw for path: " + relPath);
    }

    auto@ self = Meta::ExecutingPlugin();
    if (self !is null) {
    string absPath = Path::Join(self.SourcePath, relPath);
        
        try {
            if (IO::FileExists(absPath)) {
                return Audio::LoadSampleFromAbsolutePath(absPath);
            } else {
                warn("[Moon] Audio file not found: " + absPath);
            }
        } catch {
            warn("[Moon] LoadSampleFromAbsolutePath threw for path: " + absPath);
        }
    }
    
    return null;
}

void LoadSpecificSample(PhaseKind k) {
    if (g_phaseTriedLoad[k]) {
        return;
    }

    g_phaseTriedLoad[k] = true;
    
    string path = "";
    switch (k) {
        case PhaseKind::PK_NM:  path = kMoonSoundNMRel; break;
        case PhaseKind::PK_FQ:  path = kMoonSoundFQRel; break;
        case PhaseKind::PK_FM:  path = kMoonSoundFMRel; break;
        case PhaseKind::PK_LQ:  path = kMoonSoundLQRel; break;
        case PhaseKind::PK_INT: path = kMoonSoundINTRel; break;
    }

    if (path.Length > 0) {
        @g_phaseSamples[k] = LoadSampleRel(path);
    }
}

void LoadMoonAudioAssets() {
    if (!S_MoonPlaySounds) return;

    if (g_moonSample is null && !g_moonTriedLoad) {
        g_moonTriedLoad = true;
        @g_moonSample = LoadSampleRel(kMoonSoundRel);
    trace("[Moon] Loaded generic audio sample: " + (g_moonSample !is null));
    }

    if (S_MoonPhaseSounds) {
        for (uint k = 0; k < PhaseKind::PK_COUNT; k++) {
            LoadSpecificSample(PhaseKind(k));
        }
    }
}

void PreloadSounds() {
    if (!S_MoonPlaySounds) return;
    
    startnew(LoadMoonAudioAssets);
}

void PlayTestSound() {
    if (g_moonSample is null && !g_moonTriedLoad) {
        LoadMoonAudioAssets();
    }

    if (g_moonSample !is null) {
        float gain = S_MoonSoundGain <= 0.0f ? 0.5f : S_MoonSoundGain;
        Audio::Play(g_moonSample, gain);
    } else {
    warn("[Moon] Test sound playback failed — sample not loaded.");
    }
}

void PlayMoonSound(PhaseKind k) {
    if (!S_MoonPlaySounds) return;

    Audio::Sample@ sampleToPlay = g_moonSample;

    if (S_MoonPhaseSounds) {
        if (!g_phaseTriedLoad[k]) {
            LoadSpecificSample(k);
        }
        
        if (g_phaseSamples[k] !is null) {
            @sampleToPlay = g_phaseSamples[k];
        }
    }

    if (sampleToPlay is null && !g_moonTriedLoad) {
        g_moonTriedLoad = true;
        @g_moonSample = LoadSampleRel(kMoonSoundRel);
        @sampleToPlay = g_moonSample;
    }

    if (sampleToPlay !is null) {
        Audio::Play(sampleToPlay, S_MoonSoundGain);
    }
}
