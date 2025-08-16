Audio::Sample@ LoadSampleRel(const string &in rel) {
    if (rel.Length == 0) return null;
    Audio::Sample@ s = null;
    bool looksLikeParentRef = rel.IndexOf("..") != -1;
    auto@ self = Meta::ExecutingPlugin();

    if (!looksLikeParentRef) {
        try {
            @s = Audio::LoadSample(rel);
        } catch {
            warn("[Moon] Audio::LoadSample threw for rel='" + rel + "'");
            @s = null;
        }
        if (s !is null) return s;
    }

    if (self !is null) {
        string base = self.SourcePath;
        if (base.Length > 0) {
            string sep = "/";
            if (!base.EndsWith("/") && !base.EndsWith("\\")) base += sep;
            string absPath = base + rel;
            absPath = absPath.Replace("//", "/");
            try {
                if (IO::FileExists(absPath)) {
                    @s = Audio::LoadSampleFromAbsolutePath(absPath);
                    if (s !is null) return s;
                } else {
                    warn("[Moon] Sound file does not exist at absolute path: " + absPath + " (relative: " + rel + ")");
                }
            } catch {
                warn("[Moon] Audio::LoadSampleFromAbsolutePath threw for path='" + absPath + "'");
            }
        }
    }
    return null;
}

void PreloadSounds() {
    if (!S_MoonPlaySounds) return;
    LoadMoonAudioAssets();
}

void LoadMoonAudioAssets() {
    if (!S_MoonPlaySounds) return;
    if (g_moonSample is null && !g_moonTriedLoad) {
        g_moonTriedLoad = true;
        @g_moonSample = LoadSampleRel(kMoonSoundRel);
        if (g_moonSample is null) trace("[Moon] LoadAudio: generic sample not loaded.");
        else trace("[Moon] LoadAudio: generic sample loaded.");
    }
    if (S_MoonPhaseSounds) {
        if (g_moonNM is null && !g_moonTriedNM) { g_moonTriedNM = true; @g_moonNM = LoadSampleRel(kMoonSoundNMRel); }
        if (g_moonFQ is null && !g_moonTriedFQ) { g_moonTriedFQ = true; @g_moonFQ = LoadSampleRel(kMoonSoundFQRel); }
        if (g_moonFM is null && !g_moonTriedFM) { g_moonTriedFM = true; @g_moonFM = LoadSampleRel(kMoonSoundFMRel); }
        if (g_moonLQ is null && !g_moonTriedLQ) { g_moonTriedLQ = true; @g_moonLQ = LoadSampleRel(kMoonSoundLQRel); }
        if (g_moonINT is null && !g_moonTriedINT) { g_moonTriedINT = true; @g_moonINT = LoadSampleRel(kMoonSoundINTRel); }
    }
}

void PlayTestSound() {
    if (g_moonSample is null) {
        g_moonTriedLoad = false;
        LoadMoonAudioAssets();
    }
    if (g_moonSample !is null) {
        float gain = S_MoonSoundGain;
        if (gain <= 0.0) gain = 0.5;
        Audio::Play(g_moonSample, gain);
    } else {
        warn("[Moon] Test sound failed — sample not loaded.");
    }
}

void PlayMoonSound(PhaseKind k) {
    if (!S_MoonPlaySounds) return;
    if (S_MoonPhaseSounds) {
        EnsurePhaseSampleLoaded(k);
        Audio::Sample@ s = null;
        if (k == PhaseKind::PK_NM) @s = g_moonNM;
        else if (k == PhaseKind::PK_FQ) @s = g_moonFQ;
        else if (k == PhaseKind::PK_FM) @s = g_moonFM;
        else if (k == PhaseKind::PK_LQ) @s = g_moonLQ;
        else if (k == PhaseKind::PK_INT) @s = g_moonINT;
        if (s !is null) { Audio::Play(s, S_MoonSoundGain); return; }
    }
    if (g_moonSample is null && !g_moonTriedLoad) {
        g_moonTriedLoad = true;
        @g_moonSample = LoadSampleRel(kMoonSoundRel);
    }
    if (g_moonSample !is null) Audio::Play(g_moonSample, S_MoonSoundGain);
}

void EnsurePhaseSampleLoaded(PhaseKind k) {
    if (k == PhaseKind::PK_NM && g_moonNM is null && !g_moonTriedNM) { g_moonTriedNM = true; @g_moonNM = LoadSampleRel(kMoonSoundNMRel); }
    else if (k == PhaseKind::PK_FQ && g_moonFQ is null && !g_moonTriedFQ) { g_moonTriedFQ = true; @g_moonFQ = LoadSampleRel(kMoonSoundFQRel); }
    else if (k == PhaseKind::PK_FM && g_moonFM is null && !g_moonTriedFM) { g_moonTriedFM = true; @g_moonFM = LoadSampleRel(kMoonSoundFMRel); }
    else if (k == PhaseKind::PK_LQ && g_moonLQ is null && !g_moonTriedLQ) { g_moonTriedLQ = true; @g_moonLQ = LoadSampleRel(kMoonSoundLQRel); }
    else if (k == PhaseKind::PK_INT && g_moonINT is null && !g_moonTriedINT) { g_moonTriedINT = true; @g_moonINT = LoadSampleRel(kMoonSoundINTRel); }
}
