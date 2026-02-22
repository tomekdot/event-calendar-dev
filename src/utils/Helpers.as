/*
 * @namespace Helpers
 * A collection of generic, low-level utility functions used across the plugin.
 * This includes functions for date/time conversion, URL manipulation, and string parsing.
 */
namespace Helpers {
    // A flag to prevent spamming the log with the same warning about null events.
    bool g_HasLoggedNullEvent = false;
    // A global flag to enable/disable verbose debug logging throughout the plugin.
    bool g_DebugEnabled = false;

    /*
     * Sets the global debug flag, which controls verbose logging in certain functions.
     * @param value True to enable debug logging, false to disable.
     */
    void SetDebugEnabled(bool value) {
        g_DebugEnabled = value;
    }

    /*
     * [Internal Helper] Calculates the number of days since the proleptic Gregorian epoch.
     * This is a highly efficient algorithm for converting a Gregorian date to a serial day count.
     * Based on Howard Hinnant's public domain date algorithms.
     * @return The number of days since 0000-03-01.
     */
    int _DaysFromCivil(int year, int month, int day) {
        int year_adjusted = year - (month <= 2 ? 1 : 0);
        int era = (year_adjusted >= 0 ? year_adjusted : year_adjusted - 399) / 400;                     // 400-year era
        int year_of_era = year_adjusted - era * 400;                                                    // Year of era
        int month_of_year = month + (month > 2 ? -3 : 9);                                             // Month of year
        int day_of_year = (153 * month_of_year + 2) / 5 + day - 1;                                    // Day of year
        int day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;       // Day of era

        return era * 146097 + day_of_era - 719468; // Total days, adjusted for epoch
    }

    /*
     * Converts a UTC date and time into a 64-bit Unix timestamp (seconds since 1970-01-01 00:00:00 UTC).
     * @param Y The year.
     * @param M The month (1 - 12).
     * @param D The day (1 - 31).
     * @param h The hour (0 - 23).
     * @param m The minute (0 - 59).
     * @param s The second (0 - 59).
     * @return The corresponding Unix timestamp.
     */
    int64 StampFromUTC(int Y, int M, int D, int h, int m, int s) {
        int days = _DaysFromCivil(Y, M, D);
        return int64(days) * 86400 + int64(h) * 3600 + int64(m) * 60 + int64(s);
    }

    /*
     * Safely appends a key-value pair as a query parameter to a URL.
     * It correctly handles URLs with or without existing query parameters and preserves
     * URL fragments (e.g., #anchor). If the key already exists, the original URL is returned.
     * @param url The base URL.
     * @param key The query parameter key.
     * @param value The query parameter value.
     * @return The new URL with the appended parameter.
     */
    string AppendQueryParam(const string &in url, const string &in key, const string &in value) {
        if (key.Length == 0) {
            return url;
        }

        // 1. Separate the base URL from the fragment (#)
        int hashPos = url.IndexOf('#');
        string base = url;
        string fragment = "";
        if (hashPos != -1) {
            base = url.SubStr(0, hashPos);
            fragment = url.SubStr(hashPos);
        }

        // 2. If the key already exists, do nothing.
        if (base.IndexOf("?" + key + "=") != -1 || base.IndexOf("&" + key + "=") != -1) {
            return url;
        }
        
        // 3. Append the new parameter.
        if (base.IndexOf('?') == -1) {
            base += "?" + key + "=" + value;
        } else {
            base += "&" + key + "=" + value;
        }

        // 4. Re-attach the fragment and return.
        return base + fragment;
    }

    /*
     * Checks if a string consists exclusively of digits ('0'-'9').
     * Whitespace is trimmed before checking. An empty or whitespace-only string returns false.
     * @param str The string to check.
     * @return True if the string contains only digits, false otherwise.
     */
    bool IsAllDigits(const string &in str) {
        string trimmed = str.Trim();
        if (trimmed.Length == 0) {
            return false;
        }

        for (int i = 0; i < int(trimmed.Length); i++) {
            // Extract single-character substring and compare as strings to avoid
            // implicit conversions between string and numeric types.
            string ch = trimmed.SubStr(uint(i), 1);
            if (ch < "0" || ch > "9") {
                return false;
            }
        }
        return true;
    }

    /*
     * Parses a time string in HH:MM or HH:MM:SS format into integer components.
     * It is robust against leading/trailing whitespace and common UTC suffixes (e.g., 'UTC', 'ut').
     * @param timeStr The time string to parse.
     * @param h Output parameter for hours.
     * @param m Output parameter for minutes.
     * @param s Output parameter for seconds (defaults to 0).
     * @return True on successful parse, false otherwise.
     */
    bool ParseTimeString(const string &in timeStr, int &out h, int &out m, int &out s) {
    if (timeStr.Length == 0) {
            return false;
        }

        // 1. Sanitize input and remove common UTC suffixes.
        string t = timeStr.Trim();
        string tl = t.ToLower();
        const string[] suffixes = {" utc", " ut", "utc", "ut"};
        for (uint i = 0; i < suffixes.Length; i++) {
            if (tl.EndsWith(suffixes[i])) {
                t = t.SubStr(0, t.Length - suffixes[i].Length).Trim();
                break;
            }
        }
        
        if (g_DebugEnabled) {
            trace("[Moon][ParseTimeString] After suffix removal: '" + t + "'");
        }

        // 2. Split into parts and validate.
        auto parts = t.Split(":");
        if (parts.Length < 2 || parts.Length > 3) {
            return false; 
        }

        if (!IsAllDigits(parts[0]) || !IsAllDigits(parts[1])) {
            return false;
        }

        // 3. Parse parts into integers.
        h = Text::ParseInt(parts[0]);
        m = Text::ParseInt(parts[1]);
        s = 0; // Default seconds to 0

        if (parts.Length == 3) {
            if (!IsAllDigits(parts[2])) {
                return false;
            }
            s = Text::ParseInt(parts[2]);
        }
        
        // 4. Validate the numeric ranges.
        if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) {
            return false;
        }

        return true;
    }

    /*
     * Sort an array of EventItem@ by startMs ascending (in-place). 
     * Simple insertion sort to avoid deps.
     */
    void SortEventsByStart(array<EventItem@>@ arr) {
        if (arr is null || arr.Length <= 1) return;
        for (uint i = 1; i < arr.Length; i++) {
            EventItem@ key = arr[i];
            int j = int(i) - 1;
            while (j >= 0) {
                EventItem@ prev = arr[uint(j)];
                int64 prevMs = prev is null ? 0 : prev.startMs;
                int64 keyMs = key is null ? 0 : key.startMs;
                if (prevMs <= keyMs) break;
                @arr[uint(j + 1)] = prev;
                j--;
            }
            @arr[uint(j + 1)] = key;
        }
    }
}