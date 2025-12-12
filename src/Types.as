/**
 * @enum PhaseKind
 * Defines the types of moon phases used throughout the plugin.
 * This is used for logic, audio playback, and color coding.
 */
enum PhaseKind {
    PK_NM,      // New Moon
    PK_FQ,      // First Quarter
    PK_FM,      // Full Moon
    PK_LQ,      // Last Quarter
    PK_INT,     // Intermediate phase (e.g., Waxing Crescent, Waning Gibbous)
    
    /** 
     * A special member used to get the count of actual phase types.
     * Useful for iterating or sizing arrays, e.g., for (i = 0; i < PK_COUNT; i++).
     */
    PK_COUNT,   
    
    /**
     * A sentinel value representing an unknown or invalid phase.
     */
    PK_UNKNOWN  
}

/**
 * @class EventItem
 * A simple data structure that holds all the necessary information for a single
 * calendar event, typically a moon phase.
 */
class EventItem {
    /** A unique identifier for the event (e.g., "USNO-FM-1673895600"). */
    string id = "";
    
    /** The human-readable title of the event (e.g., "Full Moon"). */
    string title = "";
    
    /** The start time of the event, represented as milliseconds since the Unix epoch (UTC). */
    int64 startMs = 0;

    /** Optional duration in seconds. 0 if unknown/instant. */
    int durationSec = 0;

    /** Optional long description/content. */
    string description = "";

    /** Optional link to external resource (event page, etc.). */
    string url = "";

    /** Optional source label (e.g., where the event came from). */
    string source = "";

    /** Optional game discriminator (if applicable). */
    string game = "";
}

/**
 * @class UIState
 * A container for all state variables related to the user interface.
 * This helps keep track of what the user is seeing and interacting with.
 */
class UIState {
    /** The year currently being displayed in the calendar view. */
    int CalYear = 0;

    /** The month currently being displayed in the calendar view (1 - 12). */
    int CalMonth = 0;

    /** The day of the month currently selected by the user in the calendar grid. */
    int SelectedDay = 0;

    /** A flag to control the visibility of the main calendar window. */
    bool ShowCalendarWindow = true;

    /** A flag to control the visibility of the overlay calendar window. */
    bool ShowOverlayCalendar = false;
}
