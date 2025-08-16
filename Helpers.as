namespace Helpers {
    bool g_HasLoggedNullEvent = false;
    bool g_DebugEnabled = false;

    void SetDebugEnabled(bool v) {
        g_DebugEnabled = v;
    }

    int64 StampFromUTC(int Y, int M, int D, int h, int m, int s) {
        int days = _DaysFromCivil(Y, M, D);
        return int64(days) * 86400 + int64(h) * 3600 + int64(m) * 60 + int64(s);
    }

    int _DaysFromCivil(int y, int mo, int d) {
        int y_adj = y - (mo <= 2 ? 1 : 0);
        int era = (y_adj >= 0 ? y_adj : y_adj - 399) / 400;
        int yoe = y_adj - era * 400;                
        int mp = mo + (mo > 2 ? -3 : 9);            
        int doy = (153 * mp + 2) / 5 + d - 1;       
        int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy; 
        return era * 146097 + doe - 719468;        
    }

    bool IsAllDigits(const string &in str) {
        string x = str.Trim();
        int xLen = int(x.Length);
        if (xLen == 0) return false;
        for (int ii = 0; ii < xLen; ii++) {
            int uc = int(x[ii]);
            if (uc < 48 || uc > 57) return false; 
        }
        return true;
    }

    bool ParseTimeString(const string &in timeStr, int &out h, int &out m, int &out s) {
        if (timeStr.Length == 0) return false;
    string t = timeStr.Trim();
    string tl = t.ToLower();
        if (tl.EndsWith(" utc")) {
            t = t.SubStr(0, int(t.Length) - 4).Trim();
        } else if (tl.EndsWith(" ut")) {
            t = t.SubStr(0, int(t.Length) - 3).Trim();
        } else if (tl.EndsWith("utc")) {
            t = t.SubStr(0, int(t.Length) - 3).Trim();
        } else if (tl.EndsWith("ut")) {
            t = t.SubStr(0, int(t.Length) - 2).Trim();
        }

        if (g_DebugEnabled) trace("[Moon][ParseTimeString] after trim/replace: '" + t + "'");

        auto parts = t.Split(":");
        if (g_DebugEnabled) {
            int partsLenDbg = int(parts.Length);
            trace("[Moon][ParseTimeString] parts.Length = " + tostring(partsLenDbg));
            for (int pi = 0; pi < partsLenDbg; pi++)
                trace("[Moon][ParseTimeString] part[" + tostring(pi) + "]='" + parts[pi] + "'");
        }

        int partsLen = int(parts.Length);
        if (partsLen < 2) return false; 
        if (!IsAllDigits(parts[0]) || !IsAllDigits(parts[1])) return false;

        h = Text::ParseInt(parts[0]);
        m = Text::ParseInt(parts[1]);

        if (partsLen >= 3) {
            if (!IsAllDigits(parts[2])) return false;
            s = Text::ParseInt(parts[2]);
        } else {
            s = 0;
        }
        
        if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return false;
        return true;
    }
}