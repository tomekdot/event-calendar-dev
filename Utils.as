const string PHASE_NEW_MOON      = "new moon";
const string PHASE_FIRST_QUARTER = "first quarter";
const string PHASE_FULL_MOON     = "full moon";
const string PHASE_LAST_QUARTER  = "last quarter";

string PhaseDisplayTitle(const string &in p) {
    if (p.Length == 0) return "";

    string temp = p.SubStr(0, 1).ToUpper() + p.SubStr(1);
    return temp.Replace("moon", "Moon").Replace("quarter", "Quarter");
}

string PhaseAbbrev(const string &in p) {
    string lower = p.ToLower();
    if (lower == PHASE_NEW_MOON) return "NM";
    else if (lower == PHASE_FIRST_QUARTER) return "FQ";
    else if (lower == PHASE_FULL_MOON) return "FM";
    else if (lower == PHASE_LAST_QUARTER) return "LQ";
    return "INT";
}

PhaseKind GetPhaseKind(const string &in t) {
    string lower = t.ToLower();
    if (lower == PHASE_NEW_MOON) return PhaseKind::PK_NM;
    else if (lower == PHASE_FIRST_QUARTER) return PhaseKind::PK_FQ;
    else if (lower == PHASE_FULL_MOON) return PhaseKind::PK_FM;
    else if (lower == PHASE_LAST_QUARTER) return PhaseKind::PK_LQ;
    return PhaseKind::PK_INT;
}

vec4 PhaseColorForTitleLower(const string &in t) {
    switch (GetPhaseKind(t)) { 
        case PhaseKind::PK_NM: return vec4(0.5, 0.5, 0.5, 1.0);
        case PhaseKind::PK_FQ: return vec4(0.6, 0.6, 0.6, 1.0);
        case PhaseKind::PK_FM: return vec4(0.7, 0.7, 0.7, 1.0);
        case PhaseKind::PK_LQ: return vec4(0.4, 0.4, 0.4, 1.0);
        default: return vec4(0.3, 0.3, 0.3, 1.0);
    }
}

string FriendlyDeltaLong(int64 deltaMs) {
    int64 secs = Math::Abs(deltaMs) / 1000;

    int d = int(secs / 86400); secs %= 86400;
    int h = int(secs / 3600); secs %= 3600;
    int m = int(secs / 60);

    if (d > 0) return tostring(d) + "d " + tostring(h) + "h";
    if (h > 0) return tostring(h) + "h " + tostring(m) + "m";
    if (m > 0) return tostring(m) + "m";

    return tostring(int(secs)) + "s";
}

string Two(int val) { 
    return val < 10 ? "0" + tostring(val) : tostring(val); 
}

void UtcYMDFromMs(int64 ms, int &out Y, int &out M, int &out D) {
    Time::Info tm = Time::ParseUTC(ms / 1000);
    Y = tm.Year; M = tm.Month; D = tm.Day;
}

void UtcYMDHMSFromMs(int64 ms, int &out Y, int &out M, int &out D, int &out h, int &out m, int &out s) {
    Time::Info tm = Time::ParseUTC(ms / 1000);
    Y = tm.Year; M = tm.Month; D = tm.Day; h = tm.Hour; m = tm.Minute; s = tm.Second;
}

namespace UIHelpers {
    const string[] MONTH_NAMES = {
        "Invalid", "January", "February", "March", "April", "May", "June", 
        "July", "August", "September", "October", "November", "December"
    };

    bool IsLeapYear(int year) { 
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0); 
    }

    int GetDaysInMonth(int year, int month) {
        if (month == 2) return IsLeapYear(year) ? 29 : 28;
        if (month == 4 || month == 6 || month == 9 || month == 11) return 30;
        return 31;
    }

    int GetDayOfWeek(int y, int m, int d) {
        if (m < 3) { m += 12; y -= 1; }

        int K = y % 100;
        int J = y / 100;
        int h = (d + (13 * (m + 1)) / 5 + K + K / 4 + J / 4 + 5 * J) % 7;

        return (h + 6) % 7; 
    }

    string GetMonthName(int month) {
        return (month >= 1 && month <= 12) ? MONTH_NAMES[month] : MONTH_NAMES[0];
    }

    bool DayHasEvent(int day, int month, int year, const array<EventItem@> &in events) {
        for (uint i = 0; i < events.Length; i++) {
            if (events[i] is null) continue;

            int Y, M, D;
            UtcYMDFromMs(events[i].startMs, Y, M, D);

            if (Y == year && M == month && D == day) {
                return true;
            }
        }
        return false;
    }

    bool DayHasEvent(int day) {
        return DayHasEvent(day, g_UIState.CalMonth, g_UIState.CalYear, g_Events);
    }
}
