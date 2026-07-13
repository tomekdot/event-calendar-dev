// --- About / Support Toggles ---

/*
 * Toggle to show the About Project window from the plugin settings.
 */
[Setting category="About" name="About & Support" description="Show combined About and Support window"]
bool S_ShowAboutSupport = false;

// --- UI Scale ---

/*
 * How big the calendar and About windows appear on screen.
 * Pick the option that matches your screen — smaller choices are for
 * old 4:3 monitors and low resolutions where the default window is too big.
 */
enum EUiScale {
    VerySmall   = 0,   // old 4:3 low-res monitors (~800x600)   -> 0.55
    Small       = 1,   // 4:3 monitors (~1024x768)              -> 0.70
    Medium      = 2,   // 16:9 smaller screens (~1280x720)      -> 0.80
    Large       = 3,   // Full HD (1920x1080)                   -> 0.90
    ExtraLarge  = 4,   // Quad HD (2560x1440, default)          -> 1.00
    Huge        = 5,   // 4K (3840x2160)                        -> 1.20
    Custom      = 6    // your own width / height (see below)   -> see below
}

/*
 * UI size preset.
 * Choose the one that fits your screen — lower = smaller windows (good for
 * 4:3 or low-resolution displays), higher = bigger windows (good for 4K).
 * Pick "Custom" to set an exact width and height yourself.
 */
[Setting category="UI" name="UI Size" description="How big the plugin windows should be. Pick the option that matches your screen, or choose Custom for your own size."]
EUiScale S_UIScale = EUiScale::ExtraLarge;

// --- Custom size (only used when "Custom" is selected above) ---

/*
 * Exact window width in pixels. Only used when "UI Size" is set to "Custom".
 * You can still drag-resize the window freely afterwards.
 */
[Setting category="UI" name="Custom Width" description="Window width in pixels. Used only when UI Size = Custom. Type a value." if="S_UIScale Custom"]
int S_CustomWidth = 580;

/*
 * Exact window height in pixels. Only used when "UI Size" is set to "Custom".
 * You can still drag-resize the window freely afterwards.
 */
[Setting category="UI" name="Custom Height" description="Window height in pixels. Used only when UI Size = Custom. Type a value." if="S_UIScale Custom"]
int S_CustomHeight = 450;

// --- Window position (where the calendar window appears on screen) ---

/*
 * Horizontal position of the calendar window, in pixels from the left screen edge.
 * Changing this in the settings moves the window; the new position is applied immediately.
 */
[Setting category="UI" name="Position X" description="Horizontal position from the left screen edge (pixels)." if="S_UIScale Custom"]
int S_PosX = 100;

/*
 * Vertical position of the calendar window, in pixels from the top screen edge.
 * Changing this in the settings moves the window; the new position is applied immediately.
 */
[Setting category="UI" name="Position Y" description="Vertical position from the top screen edge (pixels)." if="S_UIScale Custom"]
int S_PosY = 100;

/*
 * When ON, the calendar window is locked to the Custom Width/Height and Position X/Y
 * from the settings (re-applies live as you change them). When OFF, those settings only
 * decide the size/position at first open, and you can freely drag / resize the window
 * afterwards — like the preset sizes. Only used when UI Size = Custom.
 */
[Setting category="UI" name="Lock Window To Settings" description="ON = window stays locked to the Custom size & position. OFF = you can drag and resize it freely after it opens." if="S_UIScale Custom"]
bool S_LockWindowToSettings = true;

// Turns the chosen preset into the actual scale number used for window and text size.
float UiScaleValue(EUiScale s) {
    if      (s == EUiScale::VerySmall)  return 0.55f;
    else if (s == EUiScale::Small)      return 0.70f;
    else if (s == EUiScale::Medium)     return 0.80f;
    else if (s == EUiScale::Large)      return 0.90f;
    else if (s == EUiScale::ExtraLarge) return 1.00f;
    else if (s == EUiScale::Huge)       return 1.20f;
    return 1.0f;
}

// Works out the window size and font scale for a given base size.
// When "Custom" is picked (and allowed for this window), the exact S_CustomWidth /
// S_CustomHeight are used and the font stays at its normal size so text stays readable.
// `applyAlways` is set true for Custom so the window resizes live as you change
// the Custom Width / Height in settings (otherwise FirstUseEver would ignore changes).
// `customAllowed` lets callers opt out — e.g. the About window ignores Custom and just
// uses its normal base size / font scale, since Custom size only makes sense for the calendar.
void ComputeWindowSize(float baseW, float baseH, vec2 &out winSize, float &out fontScale, bool &out applyAlways, bool customAllowed = true) {
    if (customAllowed && S_UIScale == EUiScale::Custom) {
        winSize     = vec2(float(S_CustomWidth), float(S_CustomHeight));
        fontScale   = 1.0f;
        applyAlways = true;
    } else {
        float s     = UiScaleValue(S_UIScale);
        winSize     = vec2(baseW * s, baseH * s);
        fontScale   = s;
        applyAlways = false;
    }
}

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
[Setting category="General" name="Show Calendar on Start" description="Show calendar window on startup"]
bool S_ShowCalendarOnStart = false;

/*
 * If true, the calendar also appears in Openplanet's main menu bar.
 */
[Setting category="General" name="Show Calendar in Main Menu" description="Show calendar in Openplanet's main menu bar"]
bool S_ShowCalendarInMainMenu = true;

/*
 * If true, the calendar opens as a modal popup and blocks the outside background.
 */
[Setting category="General" name="Block Outside Background for Calendar" description="Open the calendar as a modal popup"]
bool S_BlockOutsideCalendarBg = false;

/*
 * If true, the About & Support window opens as a modal popup and blocks the outside background.
 */
[Setting category="General" name="Block Outside Background for About & Support" description="Open About & Support as a modal popup"]
bool S_BlockOutsideAboutSupportBg = false;


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