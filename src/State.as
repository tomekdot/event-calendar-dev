// --- Time Constants ---
// These constants are defined for convenience and to make time-based calculations more readable.

// The number of milliseconds in one minute. 
const int64 kOneMinuteMs = 60 * 1000;
// The number of milliseconds in one hour. 
const int64 kOneHourMs = 60 * kOneMinuteMs;


// --- Default Audio Asset Paths ---
// These constants define the relative paths to audio samples.
// They are defined separately to allow for easy customization in the future.

// A constant holding the default relative path for notification sounds.
const string kDefaultNotificationSound = "assets/sounds/moon-notification.wav";
// The path for the generic, fallback moon sound.
const string kMoonSoundRel     = kDefaultNotificationSound;
// The path for the New Moon sound. 
const string kMoonSoundNMRel   = kDefaultNotificationSound;
// The path for the First Quarter sound. 
const string kMoonSoundFQRel   = kDefaultNotificationSound;
// The path for the Full Moon sound. 
const string kMoonSoundFMRel   = kDefaultNotificationSound;
// The path for the Last Quarter sound. 
const string kMoonSoundLQRel   = kDefaultNotificationSound;
// The path for intermediate phase sounds (e.g., crescent, gibbous). 
const string kMoonSoundINTRel  = kDefaultNotificationSound;


// --- UI State ---

/*
 * A global instance of the UIState class. This object holds all state related
 * to the user interface, such as window visibility and calendar selection.
 */
UIState g_UIState;


// --- Event Data ---

/*
 * The main global array that stores all fetched moon phase events.
 * This list is populated by the Fetch namespace and is the source of truth for the UI and notifications.
 * Initialize to an empty array to avoid null pointer access in cache and fetch logic.
 */
array<EventItem@> g_Events = array<EventItem@>();


// --- Loading and Caching State ---

// A flag that indicates whether a network request for calendar data is currently in progress. Used to display "Loading..." indicators.
bool g_IsLoading = false;
// Stores the year of the last successful calendar data fetch. Used to prevent unnecessary API calls.
int g_LastFetchedYear = 0;
// Stores the month of the last successful calendar data fetch. Used to prevent unnecessary API calls.
int g_LastFetchedMonth = 0;
// A flag to ensure that startup notifications are only shown once per application session.
bool g_InitialNotificationsShown = false;
// Stores the last API error message. Empty string means no error.
string g_ApiError = "";


// --- Month Event Cache ---

/*
 * A cache to provide fast lookups of events for the currently displayed month.
 * Key: Day of the month (as a string, e.g., "15").
 * Value: array<EventItem@> of events for that day.
 */
dictionary@ g_MonthEventCache = dictionary();

/* Rebuilds the month cache from g_Events for current g_UIState.CalYear/CalMonth. */
void RebuildMonthEventCache() {
	g_MonthEventCache.DeleteAll();
	if (S_EnableDebug) {
		trace("[Moon] RebuildMonthEventCache: processing " + tostring(g_Events.Length) + " events for " + tostring(g_UIState.CalYear) + "-" + tostring(g_UIState.CalMonth));
	}
	for (uint i = 0; i < g_Events.Length; i++) {
		auto@ evt = g_Events[i];
		if (evt is null) continue;
		int Y, M, D;
		TimeUtils::UtcYMDFromMs(evt.startMs, Y, M, D);
		if (Y == g_UIState.CalYear && M == g_UIState.CalMonth) {
			string key = tostring(D);
			array<EventItem@>@ dayList = g_MonthEventCache.Exists(key)
				? cast<array<EventItem@>@>(g_MonthEventCache[key])
				: array<EventItem@>();
			dayList.InsertLast(evt);
			g_MonthEventCache[key] = dayList;
		}
	}
	// Log per-day counts only in debug mode
	if (S_EnableDebug) {
		array<string> dayKeys = g_MonthEventCache.GetKeys();
		for (uint k = 0; k < dayKeys.Length; k++) {
			string day = dayKeys[k];
			array<EventItem@>@ list = cast<array<EventItem@>@>(g_MonthEventCache[day]);
			int cnt = list is null ? 0 : int(list.Length);
			trace("[Moon] RebuildMonthEventCache: day=" + day + " count=" + tostring(cnt));
		}
	}
}


// --- Audio Sample Handles and State ---

// A handle to the generic, default audio sample that is played for notifications.
Audio::Sample@ g_moonSample = null;
// A flag to track whether an attempt has been made to load g_moonSample. This prevents repeated load attempts on failure. */
bool g_moonTriedLoad = false;

// An array to hold handles to audio samples for specific moon phases. Indexed by the PhaseKind enum. */
array<Audio::Sample@> g_phaseSamples(PhaseKind::PK_COUNT);
// A parallel array of flags to track whether a load attempt has been made for each specific phase sound. */
array<bool> g_phaseTriedLoad(PhaseKind::PK_COUNT, false);