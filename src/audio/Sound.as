/*
 * Loads an audio sample from a relative path with a fallback mechanism.
 * First, it tries to load the sample directly using the relative path.
 * If that fails, it constructs an absolute path based on the plugin's source
 * directory and attempts to load from there.
 * @param relPath The path to the audio file, relative to the plugin's execution directory.
 * @return A handle to the loaded Audio::Sample, or null if loading fails.
 */
Audio::Sample@ LoadSampleRel(const string &in relPath) {
    if (relPath.Length == 0) {
        return null;
    }

    // First attempt: Load using the relative path directly.
    // This often works when the executable's working directory is set correctly.
    try {
        Audio::Sample@ sample = Audio::LoadSample(relPath);
        if (sample !is null) {
            return sample;
        }
    } catch {
        warn("[Moon] LoadSample threw an exception for path: " + relPath);
    }

    // Fallback attempt: Construct an absolute path.
    // This is more reliable as it doesn't depend on the working directory.
    auto@ self = Meta::ExecutingPlugin();
    if (self !is null) {
        string absPath = Path::Join(self.SourcePath, relPath);
        
        try {
            if (IO::FileExists(absPath)) {
                return Audio::LoadSampleFromAbsolutePath(absPath);
            } else {
                warn("[Moon] Audio file not found at absolute path: " + absPath);
            }
        } catch {
            warn("[Moon] LoadSampleFromAbsolutePath threw an exception for path: " + absPath);
        }
    }
    
    return null; // Return null if all attempts fail.
}

/*
 * Loads the audio sample for a specific moon phase.
 * Uses a flag to ensure the loading attempt is only made once per phase.
 * @param phase The specific moon phase (e.g., New Moon, Full Moon) to load a sample for.
 */
void LoadSpecificSample(PhaseKind phase) {
    // Avoid re-attempting to load a sample that has already been tried.
    if (g_phaseTriedLoad[phase]) {
        return;
    }
    g_phaseTriedLoad[phase] = true;

    string path = "";
    switch (phase) {
        case PhaseKind::PK_NM:  path = kMoonSoundNMRel;  break;
        case PhaseKind::PK_FQ:  path = kMoonSoundFQRel;  break;
        case PhaseKind::PK_FM:  path = kMoonSoundFMRel;  break;
        case PhaseKind::PK_LQ:  path = kMoonSoundLQRel;  break;
        case PhaseKind::PK_INT: path = kMoonSoundINTRel; break;
        default: return; // Do nothing for unknown or unhandled phases.
    }

    if (path.Length > 0) {
        @g_phaseSamples[phase] = LoadSampleRel(path);
    }
}

/*
 * Loads all required audio assets.
 * This includes a generic sound and, if enabled, phase-specific sounds.
 * This function is designed to be run in a separate coroutine to avoid blocking.
 */
void LoadMoonAudioAssets() {
    if (!S_MoonPlaySounds) return;

    // Load the generic, default moon sound if it hasn't been attempted yet.
    if (g_moonSample is null && !g_moonTriedLoad) {
        g_moonTriedLoad = true;
        @g_moonSample = LoadSampleRel(kMoonSoundRel);
        trace("[Moon] Generic audio sample loaded: " + (g_moonSample !is null));
    }

    // If enabled, load samples for each specific moon phase.
    if (S_MoonPhaseSounds) {
        for (uint i = 0; i < PhaseKind::PK_COUNT; i++) {
            LoadSpecificSample(PhaseKind(i));
        }
    }
}

/*
 * Preloads all audio assets on startup in a new coroutine.
 * This prevents the main thread from lagging while audio files are loaded from disk.
 */
void PreloadSounds() {
    if (!S_MoonPlaySounds) return;
    
    startnew(LoadMoonAudioAssets);
}

/*
 * Plays a test sound using the generic moon sample.
 * If the sample isn't loaded, it will attempt to load it synchronously.
 * Note: This might cause a small stutter if called from the main thread.
 */
void PlayTestSound() {
    // Lazy-load the assets if they haven't been loaded yet.
    if (g_moonSample is null && !g_moonTriedLoad) {
        LoadMoonAudioAssets();
    }

    if (g_moonSample !is null) {
        // Use a default gain if the configured value is invalid.
        float effectiveGain = S_MoonSoundGain <= 0.0f ? 0.5f : S_MoonSoundGain;
        Audio::Play(g_moonSample, effectiveGain);
    } else {
        warn("[Moon] Test sound playback failed: sample is not loaded.");
    }
}

/*
 * Plays the appropriate sound for a given moon phase.
 * It will prioritize a phase-specific sound if available and enabled.
 * Otherwise, it falls back to the generic moon sound. 
 * @param phase The phase of the moon for which to play a sound.
 */
void PlayMoonSound(PhaseKind phase) {
    if (!S_MoonPlaySounds) return;

    Audio::Sample@ sampleToPlay = null;

    // If phase-specific sounds are enabled, try to use one.
    if (S_MoonPhaseSounds) {
        // Lazy-load the specific sample if it hasn't been attempted yet.
        if (!g_phaseTriedLoad[phase]) {
            LoadSpecificSample(phase);
        }
        
        // If the specific sample is now available, select it.
        if (g_phaseSamples[phase] !is null) {
            @sampleToPlay = g_phaseSamples[phase];
        }
    }

    // If no specific sample was found or they are disabled, fall back to the generic one.
    if (sampleToPlay is null) {
        // Lazy-load the generic sample as a last resort if it was never loaded.
        if (g_moonSample is null && !g_moonTriedLoad) {
            g_moonTriedLoad = true;
            @g_moonSample = LoadSampleRel(kMoonSoundRel);
        }
        @sampleToPlay = g_moonSample;
    }

    // Finally, play the selected sample if it's valid.
    if (sampleToPlay !is null) {
        Audio::Play(sampleToPlay, S_MoonSoundGain);
    }
}