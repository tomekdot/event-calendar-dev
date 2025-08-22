[Setting category="General" name="Enable Moon Phase Fetching" description="Enable moon phase fetching"]
bool S_EnableMoon = true;

[Setting category="General" name="Show Calendar on Start" description="Show calendar on startup"]
bool S_ShowCalendarOnStart = false;

[Setting category="Fetch" name="API URL" description="USNO API endpoint"]
string S_MoonApiUrl = "https://aa.usno.navy.mil/api/moon/phases/date";

[Setting category="Fetch" name="Auto Date" description="Start from today's date"]
bool S_AutoDate = true;

[Setting category="Fetch" name="Phases to Fetch" description="Number of entries to request" min=4 max=99]
int S_USNO_NumP = 50;

[Setting category="Fetch" name="Refresh Interval" description="Polling interval (seconds)" min=30 max=3600]
int S_PollIntervalSec = 900;

[Setting category="Notifications" name="Notify Minutes Before" description="Minutes before event notification" min=0 max=120]
int S_NotifyMinutesBefore = 15;

[Setting category="Notifications" name="Max Immediate Notifications" description="Max notifications for close events" min=1 max=5]
int S_MaxImmediateNotifications = 1;

[Setting category="Notifications" name="Play Sounds" description="Enable sound notifications"]
bool S_MoonPlaySounds = true;

[Setting category="Notifications" name="Test Sound" description="Test notification sound"]
bool S_MoonTestSound = false;

[Setting category="Notifications" name="Phase-specific Sounds" description="Play sounds for specific phases only"]
bool S_MoonPhaseSounds = false;

[Setting category="Notifications" name="Sound Gain" description="Notification sound volume" min=0.0 max=2.0]
float S_MoonSoundGain = 0.5;

[Setting category="Notifications" name="Notification Duration" description="Popup notification duration" min=1 max=30]
int S_NotificationDurationSec = 8;

[Setting category="Advanced" name="Debug Traces" description="Enable debug traces"]
bool S_EnableDebug = false;

[Setting category="Support" name="Donate URL" description="Donation URL"]
string S_SupportDonateUrl = "https://www.paypal.me/tomekdot";

[Setting category="Support" name="GitHub URL" description="Project GitHub URL"]
string S_SupportGithubUrl = "https://github.com/tomekdot/event-calendar-dev";

[Setting category="Support" name="Discord URL" description="Pursuit Discord URL"]
string S_SupportDiscordUrl = "https://discord.me/pursuit";
