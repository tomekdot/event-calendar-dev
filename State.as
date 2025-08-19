// --- Time constants ---
const int64 kOneMinuteMs = 60 * 1000;
const int64 kOneHourMs = 60 * kOneMinuteMs;

// --- Default paths to sounds (placeholders) ---
const string kDefaultNotificationSound = "assets/sounds/moon-notification.wav";
const string kMoonSoundRel     = kDefaultNotificationSound;
const string kMoonSoundNMRel   = kDefaultNotificationSound;
const string kMoonSoundFQRel   = kDefaultNotificationSound;
const string kMoonSoundFMRel   = kDefaultNotificationSound;
const string kMoonSoundLQRel   = kDefaultNotificationSound;
const string kMoonSoundINTRel  = kDefaultNotificationSound;

// --- UI State ---
UIState g_UIState;

// --- Event data ---
array<EventItem@> g_Events;

// --- Loading State ---
bool g_IsLoading = false;
int g_LastFetchedYear = 0;
int g_LastFetchedMonth = 0;
bool g_InitialNotificationsShown = false;

// --- Month Event Cache ---
dictionary@ g_MonthEventCache = dictionary();

// --- Generic audio sample ---
Audio::Sample@ g_moonSample = null;
bool g_moonTriedLoad = false;

// --- Phase-specific audio arrays (index by PhaseKind) ---
array<Audio::Sample@> g_phaseSamples(PhaseKind::PK_COUNT);
array<bool> g_phaseTriedLoad(PhaseKind::PK_COUNT, false);
