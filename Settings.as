[Setting category="Moon Calendar" name="Enable Moon Phase Fetching"]
bool S_EnableMoon = true;
[Setting category="Moon Calendar" name="API URL (USNO)"]
string S_MoonApiUrl = "https://aa.usno.navy.mil/api/moon/phases/date";
[Setting category="Moon Calendar" name="Use Today's Date Automatically"]
bool S_AutoDate = true;
[Setting category="Moon Calendar" name="Number of Phases to Fetch" min=4 max=99]
int S_USNO_NumP = 50;
[Setting category="Moon Calendar" name="Refresh Interval (seconds)" min=30 max=3600]
int S_PollIntervalSec = 900;
[Setting category="Moon Calendar" name="Notify Minutes Before" min=0 max=120]
int S_NotifyMinutesBefore = 15;
[Setting category="Moon Calendar" name="Max Immediate Notifications" min=1 max=5]
int S_MaxImmediateNotifications = 1;
[Setting category="Moon Calendar" name="Play Notification Sounds"]
bool S_MoonPlaySounds = true;
[Setting category="Moon Calendar" name="Test Notification Sound" description="Click to test the notification sound"]
bool S_MoonTestSound = false;
[Setting category="Moon Calendar" name="Play Sounds for Specific Phases"]
bool S_MoonPhaseSounds = false;
[Setting category="Moon Calendar" name="Sound Gain" min=0.0 max=2.0]
float S_MoonSoundGain = 1.0;
[Setting category="Moon Calendar" name="Notification Duration (seconds)" min=1 max=30]
int S_NotificationDurationSec = 8;
[Setting category="Moon Calendar" name="Enable Debug Traces (Advanced)" description="Show detailed debug logs. For troubleshooting only."]
bool S_EnableDebug = false;
[Setting category="Moon Calendar" name="Show Calendar on Start" description="Open calendar window automatically on plugin start"]
bool S_ShowCalendarOnStart = false;
