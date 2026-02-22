/*
 * @namespace Moon
 * A collection of utility functions and constants related to moon phases.
 * This namespace handles formatting, abbreviations, enum conversions, and color coding.
 */
namespace Moon {
    // The standard log tag for moon-related messages. 
    const string kLogTag = "[Moon]";

    // Canonical string representations of the primary moon phases, as received from the API.
    const string PHASE_NEW_MOON      = "new moon";
    const string PHASE_FIRST_QUARTER = "first quarter";
    const string PHASE_FULL_MOON     = "full moon";
    const string PHASE_LAST_QUARTER  = "last quarter";

    /*
     * Formats a raw phase string (e.g., "full moon") into a display-friendly,
     * capitalized version (e.g., "Full Moon").
     * @param p The raw phase string from the API.
     * @return The formatted string for display.
     */
    string PhaseDisplayTitle(const string &in p) {
        if (p.Length == 0) {
            return "";
        }
        string temp = p.SubStr(0, 1).ToUpper() + p.SubStr(1);
        return temp.Replace("moon", "Moon").Replace("quarter", "Quarter");
    }

    /*
     * Converts a full phase string into a short, two-letter abbreviation (e.g., "NM", "FQ").
     * Non-primary phases return "INT" for "Intermediate".
     * @param p The raw phase string.
     * @return A two-letter abbreviation string.
     */
    string PhaseAbbrev(const string &in p) {
        string lower = p.ToLower();
        if (lower == PHASE_NEW_MOON)        return "NM";
        if (lower == PHASE_FIRST_QUARTER)   return "FQ";
        if (lower == PHASE_FULL_MOON)       return "FM";
        if (lower == PHASE_LAST_QUARTER)    return "LQ";
        return "INT"; // Intermediate
    }

    /*
     * Converts a full phase string into its corresponding `PhaseKind` enum value.
     * @param t The phase title string.
     * @return The `PhaseKind` enum member.
     */
    PhaseKind GetPhaseKind(const string &in t) {
        string lower = t.ToLower();
        if (lower.Contains(PHASE_NEW_MOON))        return PhaseKind::PK_NM;
        if (lower.Contains(PHASE_FIRST_QUARTER))   return PhaseKind::PK_FQ;
        if (lower.Contains(PHASE_FULL_MOON))       return PhaseKind::PK_FM;
        if (lower.Contains(PHASE_LAST_QUARTER))    return PhaseKind::PK_LQ;
        return PhaseKind::PK_INT;
    }

    /*
     * Returns a specific color (`vec4`) for a given moon phase, suitable for UI highlighting.
     * @param t The phase title string.
     * @return A color vector (RGBA).
     */
    vec4 PhaseColorForTitleLower(const string &in t) {
        switch (GetPhaseKind(t)) { 
            case PhaseKind::PK_NM: return vec4(0.5, 0.5, 0.5, 1.0); // Grey
            case PhaseKind::PK_FQ: return vec4(0.6, 0.6, 0.6, 1.0); // Light Grey
            case PhaseKind::PK_FM: return vec4(0.7, 0.7, 0.7, 1.0); // Lighter Grey
            case PhaseKind::PK_LQ: return vec4(0.4, 0.4, 0.4, 1.0); // Dark Grey
            default: return vec4(0.3, 0.3, 0.3, 1.0);               // Darkest Grey (Intermediate)
        }
    }
}

/*
 * @namespace TimeUtils
 * Provides helper functions for time and date manipulation and formatting.
 */
namespace TimeUtils {
    /*
     * Converts a time delta in milliseconds into a human-readable string (e.g., "1d 0h", "5m 30s").
     * The format adapts based on the magnitude of the delta.
     * @param deltaMs The time difference in milliseconds.
     * @return A formatted string representation.
     */
    string FriendlyDeltaLong(int64 deltaMs) {
        int64 totalSeconds = Math::Abs(deltaMs) / 1000;

        int days = int(totalSeconds / 86400); totalSeconds %= 86400;
        int hours = int(totalSeconds / 3600); totalSeconds %= 3600;
        int minutes = int(totalSeconds / 60);
        int seconds = int(totalSeconds % 60);

        if (days > 0) return tostring(days) + "d " + tostring(hours) + "h";
        if (hours > 0) return tostring(hours) + "h " + tostring(minutes) + "m";
        if (minutes > 0) return tostring(minutes) + "m " + tostring(seconds) + "s";
        return tostring(seconds) + "s";
    }

    /*
     * Pads a single-digit integer with a leading zero to ensure it is two characters long.
     * @param val The integer value (e.g., 7).
     * @return The formatted string (e.g., "07").
     */
    string Two(int val) { 
        return val < 10 ? "0" + tostring(val) : tostring(val); 
    }

    /*  
     * Extracts the Year, Month, and Day from a UTC millisecond timestamp.
     * @param ms The timestamp in milliseconds since the Unix epoch.
     * @param Y Output parameter for the year.
     * @param M Output parameter for the month.
     * @param D Output parameter for the day.
     */
    void UtcYMDFromMs(int64 ms, int &out Y, int &out M, int &out D) {
        Time::Info tm = Time::ParseUTC(ms / 1000);
        Y = tm.Year; M = tm.Month; D = tm.Day;
    }

    /*  
     * Extracts all date and time components from a UTC millisecond timestamp.
     * @param ms The timestamp in milliseconds since the Unix epoch.
     */
    void UtcYMDHMSFromMs(int64 ms, int &out Y, int &out M, int &out D, int &out h, int &out m, int &out s) {
        Time::Info tm = Time::ParseUTC(ms / 1000);
        Y = tm.Year; M = tm.Month; D = tm.Day; h = tm.Hour; m = tm.Minute; s = tm.Second;
    }
}

/*
 * @namespace UIHelpers
 * Contains helper functions specifically for rendering and managing the calendar UI.
 */
namespace UIHelpers {
    /*
     * An array of month names, indexed 1 - 12. 
     * Index 0 is a placeholder for invalid month values.
     */
    const string[] MONTH_NAMES = {
        "Invalid", "January", "February", "March", "April", "May", "June", 
        "July", "August", "September", "October", "November", "December"
    };

    /*
     * Determines if a given year is a leap year.
     * @param year The year to check.
     * @return True if it is a leap year, false otherwise.
     */
    bool IsLeapYear(int year) { 
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0); 
    }

    /*
     * Calculates the number of days in a given month and year, accounting for leap years.
     * @param year The year.
     * @param month The month (1-12).
     * @return The number of days in that month.
     */
    int GetDaysInMonth(int year, int month) {
        if (month == 2) return IsLeapYear(year) ? 29 : 28;
        if (month == 4 || month == 6 || month == 9 || month == 11) return 30;
        return 31;
    }

    /*
     * Calculates the day of the week for a given date.
     * @return An integer representing the day of the week (0=Sunday, 1=Monday, ..., 6=Saturday).
     */
    int GetDayOfWeek(int y, int m, int d) {
        if (y < 1 || m < 1 || m > 12 || d < 1 || d > GetDaysInMonth(y, m)) {
            return -1; // Invalid date
        }

        // This implementation uses Zeller's congruence to find the day of the week.
        int year = y;
        int month = m;
        if (month < 3) {
            month += 12;
            year -= 1;
        }

        int K = year % 100;
        int J = year / 100;

        int h = (d + (13 * (month + 1)) / 5 + K + K / 4 + J / 4 + 5 * J) % 7;

        // The formula returns 0 = Saturday, 1 = Sunday, etc. Adjust to make 0 = Sunday.
        return (h + 6) % 7; 
    }

    /*
     * Returns the full name of a month from its number (1 - 12).
     * @param month The month number.
     * @return The full month name (e.g., "January").
     */
    string GetMonthName(int month) {
        return (month >= 1 && month <= 12) ? MONTH_NAMES[month] : MONTH_NAMES[0];
    }
}