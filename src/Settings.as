// --- About / Support Toggles ---

/*
 * Toggle to show the About Project window from the plugin settings.
 */
[Setting category="About" name="About & Support" description="Show combined About and Support window"]
bool S_ShowAboutSupport = false;

// --- General Settings ---

/*
 * Master switch to enable or disable the entire moon phase fetching and display feature.
 * If set to false, no API calls will be made and no UI will be rendered.
 */
[Setting category="General" name="Enable Moon Phase Fetching" description="Enable moon phase fetching"]
bool S_EnableMoon = true;

/*
 * If true, the main calendar window will be visible immediately upon plugin startup.
 * If false, the user must open it manually from the menu.
 */
[Setting category="General" name="Show Calendar on Start" description="Show calendar on startup"]
bool S_ShowCalendarOnStart = false;


// --- Fetch Settings ---

/*
 * The base URL for the USNO API. This should not be changed by the user unless
 * the official API endpoint moves to a new address.
 */
[Setting category="Fetch" name="API URL" description="USNO API endpoint"]
string S_MoonApiUrl = "https://aa.usno.navy.mil/api/moon/phases/date";

/*
 * If true, the plugin will always fetch data starting from the current system date.
 * (Currently, this is the default behavior for initial and periodic fetches).
 */
[Setting category="Fetch" name="Auto Date" description="Start from today's date"]
bool S_AutoDate = true;

/*
 * Specifies the number of moon phase events to request from the API in a single call.
 * A higher number means fewer API calls but a larger initial data payload.
 */
[Setting category="Fetch" name="Phases to Fetch" description="Number of entries to request" min=4 max=99]
int S_USNO_NumP = 20;

/*
 * The interval in seconds at which the plugin will automatically re-fetch data
 * in the background to keep events up-to-date.
 */
[Setting category="Fetch" name="Refresh Interval" description="Polling interval (seconds)" min=30 max=3600]
int S_PollIntervalSec = 900; // Default: 15 minutes


// --- Notification Settings ---

/*
 * How many minutes before a moon phase event a notification should be displayed.
 * Setting this to 0 effectively disables timed notifications.
 */
[Setting category="Notifications" name="Notify Minutes Before" description="Minutes before event notification" min=0 max=120]
int S_NotifyMinutesBefore = 15;

/*
 * Master switch to enable or disable all visual UI notifications from the plugin.
 * When false, any calls that would show a UI popup will be suppressed.
 */
[Setting category="Notifications" name="Enable Notifications" description="Enable visual UI notifications"]
bool S_EnableNotifications = true;

/*
 * The maximum number of notifications to show at once during startup for events
 * that are occurring today or in the near future. Prevents notification spam.
 */
[Setting category="Notifications" name="Max Immediate Notifications" description="Max notifications for close events" min=1 max=5]
int S_MaxImmediateNotifications = 1;

/*
 * Master switch to enable or disable all notification sounds.
 */
[Setting category="Notifications" name="Play Sounds" description="Enable sound notifications"]
bool S_MoonPlaySounds = true;

/*
 * A trigger to play the test sound. Setting this to true via the UI will play
 * the configured sound once and then this setting will automatically reset to false.
 */
[Setting category="Notifications" name="Test Sound" description="Test notification sound"]
bool S_MoonTestSound = false;

/*
 * If true, enables the use of different sounds for different moon phases (e.g., a specific
 * sound for Full Moon). Requires 'Play Sounds' to be enabled.
 */
[Setting category="Notifications" name="Phase-specific Sounds" description="Play sounds for specific phases only"]
bool S_MoonPhaseSounds = false;

/*
 * The volume (gain) for notification sounds. 0.0 is silent, 1.0 is normal volume.
 */
[Setting category="Notifications" name="Sound Gain" description="Notification sound volume" min=0.0 max=2.0]
float S_MoonSoundGain = 0.5;

/*
 * The duration in seconds for how long a UI notification popup remains visible on the screen.
 */
[Setting category="Notifications" name="Notification Duration" description="Popup notification duration" min=1 max=30]
int S_NotificationDurationSec = 8;


// --- Advanced Settings ---

/*
 * If true, enables verbose logging to the console for debugging purposes.
 * This can help diagnose issues with API fetching or event processing.
 */
[Setting category="Advanced" name="Debug Traces" description="Enable debug traces"]
bool S_EnableDebug = false;

/*
 * One-shot setting: when set to true from the Settings UI, the plugin will
 * start the Helpers tests (if debug is enabled) and then reset this setting
 * back to false automatically.
 */
[Setting category="Advanced" name="Run Helpers Tests" description="Run internal helpers tests once"]
bool S_RunHelpersTests = false;


// --- Support Settings ---

/*
 * The URL for the project's donation page, used in the 'Support' window.
 */
[Setting category="Support" name="Donate URL" description="Donation URL"]
string S_SupportDonateUrl = "https://www.paypal.me/tomekdot";

/*
 * The URL for the project's GitHub repository, used in the 'Support' window.
 */
[Setting category="Support" name="GitHub URL" description="Project GitHub URL"]
string S_SupportGithubUrl = "https://github.com/tomekdot/event-calendar-dev";

/*
 * The URL for the project's or community's Discord server, used in the 'Support' window.
 */
[Setting category="Support" name="Discord URL" description="Pursuit Discord URL"]
string S_SupportDiscordUrl = "https://discord.me/pursuit";