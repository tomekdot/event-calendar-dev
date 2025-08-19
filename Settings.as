[Setting category="General" name="Enable Moon Phase Fetching" description="Toggle automatic fetching of upcoming moon phases"]
bool S_EnableMoon = true;

[Setting category="General" name="Show Calendar on Start" description="Open calendar window automatically when the plugin starts"]
bool S_ShowCalendarOnStart = false;

[Setting category="Fetch" name="API URL (USNO)" description="USNO API endpoint used to fetch moon phase data"]
string S_MoonApiUrl = "https://aa.usno.navy.mil/api/moon/phases/date";

[Setting category="Fetch" name="Use Today's Date Automatically" description="Automatically request data starting from today's date (when enabled)"]
bool S_AutoDate = true;

[Setting category="Fetch" name="Number of Phases to Fetch" description="How many upcoming phase entries to request from the API" min=4 max=99]
int S_USNO_NumP = 50;

[Setting category="Fetch" name="Refresh Interval (seconds)" description="Polling interval to refresh fetched phase data" min=30 max=3600]
int S_PollIntervalSec = 900;

[Setting category="Notifications" name="Notify Minutes Before" description="Minutes before an event to show a notification" min=0 max=120]
int S_NotifyMinutesBefore = 15;

[Setting category="Notifications" name="Max Immediate Notifications" description="Maximum number of notifications shown at once for close events" min=1 max=5]
int S_MaxImmediateNotifications = 1;

[Setting category="Notifications" name="Play Notification Sounds" description="Enable audible notification for upcoming phases"]
bool S_MoonPlaySounds = true;

[Setting category="Notifications" name="Test Notification Sound" description="Click to play the notification sound once for testing"]
bool S_MoonTestSound = false;

[Setting category="Notifications" name="Play Sounds for Specific Phases" description="Only play sounds for configured phase types when enabled"]
bool S_MoonPhaseSounds = false;

[Setting category="Notifications" name="Sound Gain" description="Multiplier applied to notification sound (0.0–2.0)" min=0.0 max=2.0]
float S_MoonSoundGain = 0.5;

[Setting category="Notifications" name="Notification Duration (seconds)" description="How long to show popup notifications" min=1 max=30]
int S_NotificationDurationSec = 8;

[Setting category="Advanced" name="Enable Debug Traces" description="Show detailed debug logs; use only for troubleshooting"]
bool S_EnableDebug = false;