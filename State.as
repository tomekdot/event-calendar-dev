array<EventItem@> g_Events;
array<string> g_ShownNotificationIDs;
bool g_IsLoading = false;
int g_LastFetchedYear = 0;
int g_LastFetchedMonth = 0;
bool g_InitialNotificationsShown = false;
Audio::Sample@ g_moonSample; bool g_moonTriedLoad = false;
Audio::Sample@ g_moonNM; bool g_moonTriedNM = false;
Audio::Sample@ g_moonFQ; bool g_moonTriedFQ = false;
Audio::Sample@ g_moonFM; bool g_moonTriedFM = false;
Audio::Sample@ g_moonLQ; bool g_moonTriedLQ = false;
Audio::Sample@ g_moonINT; bool g_moonTriedINT = false;
UIState g_UIState;

const string kDefaultNotificationSound = "assets/sounds/776182__soundandmelodies__sfx-notification2-interface-gui.wav";
const string kMoonSoundRel = kDefaultNotificationSound;
const string kMoonSoundNMRel = kDefaultNotificationSound;
const string kMoonSoundFQRel = kDefaultNotificationSound;
const string kMoonSoundFMRel = kDefaultNotificationSound;
const string kMoonSoundLQRel = kDefaultNotificationSound;
const string kMoonSoundINTRel = kDefaultNotificationSound;

const int64 kOneMinuteMs = 60 * 1000;
const int64 kOneHourMs = 60 * kOneMinuteMs;
