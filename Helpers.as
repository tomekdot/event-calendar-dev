namespace Helpers {
    bool g_HasLoggedNullEvent = false;
    bool g_DebugEnabled = false;

    void SetDebugEnabled(bool v) {
        g_DebugEnabled = v;
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

    int64 StampFromUTC(int Y, int M, int D, int h, int m, int s) {
        int days = _DaysFromCivil(Y, M, D);
        return int64(days) * 86400 + int64(h) * 3600 + int64(m) * 60 + int64(s);
    }

    string AppendQueryParam(const string &in url, const string &in key, const string &in value) {
        if (url.IndexOf("?" + key + "=") != -1 || url.IndexOf("&" + key + "=") != -1) return url;
        if (url.IndexOf('?') == -1) return url + "?" + key + "=" + value;
        return url + "&" + key + "=" + value;
    }

    bool IsAllDigits(const string &in str) {
        string x = str.Trim();
        if (x.Length == 0) {
            return false;
        }

        int len = int(x.Length);
        for (int i = 0; i < len; i++) {
            string singleChar = x.SubStr(i, 1);
            if (singleChar < "0" || singleChar > "9") {
                return false; 
            }
        }
        return true;
    }

    bool ParseTimeString(const string &in timeStr, int &out h, int &out m, int &out s) {
    if (timeStr.Length == 0) {
            return false;
        }

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

        auto parts = t.Split(":");
        int partsLen = int(parts.Length);

        if (partsLen < 2 || partsLen > 3) {
            return false; 
        }

        if (!IsAllDigits(parts[0]) || !IsAllDigits(parts[1])) {
            return false;
        }

        h = Text::ParseInt(parts[0]);
        m = Text::ParseInt(parts[1]);

        if (partsLen == 3) {
            if (!IsAllDigits(parts[2])) {
                return false;
            }
            s = Text::ParseInt(parts[2]);
        } else {
            s = 0;
        }
        
        if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) {
            return false;
        }
        return true;
    }
}
