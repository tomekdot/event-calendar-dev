namespace FetchInternal {
    uint g_FetchRequestID = 0;
    const string API_BASE_URL = "https://aa.usno.navy.mil/api/moon/phases/date";
}

string BuildApiUrl(int year, int month, int day) {
    string baseUrl = S_MoonApiUrl.Length == 0 ? FetchInternal::API_BASE_URL : S_MoonApiUrl.Split('?')[0];
    int numPhases = S_USNO_NumP <= 0 ? 50 : S_USNO_NumP;
    string dateForApi = tostring(year) + "-" + Two(month) + "-" + Two(day);

    return baseUrl + "?date=" + dateForApi + "&nump=" + tostring(numPhases);
}

void StartFetchCoroutine(const string &in url, bool isInitial) {
    FetchInternal::g_FetchRequestID++; 

    dictionary args;
    args["url"] = url;
    args["isInitialFetch"] = isInitial;
    args["requestID"] = FetchInternal::g_FetchRequestID; 

    startnew(FetchCoroutine, args);
}

void FetchLatestData() {
    if (!S_EnableMoon) return;

    Time::Info tm = Time::Parse(Time::Stamp);
    string url = BuildApiUrl(tm.Year, tm.Month, tm.Day);

    StartFetchCoroutine(url, true);
}

void FetchForCalendarView() {
    if (!S_EnableMoon) { 
        g_Events.Resize(0); 
        return; 
    }

    if (g_UIState.CalYear == g_LastFetchedYear && g_UIState.CalMonth == g_LastFetchedMonth && !g_Events.IsEmpty()) {
        return;
    }

    string url = BuildApiUrl(g_UIState.CalYear, g_UIState.CalMonth, 1);
    StartFetchCoroutine(url, false);
}

void ParsePhasedata(Json::Value@ root, array<EventItem@>@ local_events) {
    if (root is null || !root.HasKey("phasedata") || root["phasedata"].GetType() != Json::Type::Array) {
        return;
    }

    Json::Value@ arr = root["phasedata"];
    dictionary seenIds;

    for (uint i = 0; i < arr.Length; i++) {
        auto@ row = arr[i];
        if (!row.HasKey("phase") || !row.HasKey("year") || !row.HasKey("month") || !row.HasKey("day")) {
            continue;
        }

        string phase = string(row["phase"]);
        int Y = int(row["year"]); 
        int M = int(row["month"]); 
        int D = int(row["day"]);
        string timeStr = row.HasKey("time") ? string(row["time"]) : "";

        int h = 0, m = 0, s = 0;
        if (timeStr.Length > 0) {
            if (!Helpers::ParseTimeString(timeStr, h, m, s)) {
                warn("[Moon] Unrecognized time format: '" + timeStr + "' -> using 00:00:00");
            }
        }
        
        int64 epochSec = Helpers::StampFromUTC(Y, M, D, h, m, s);
        if (epochSec <= 0) {
            continue;
        }

        EventItem@ e = EventItem();
        e.id = "USNO-" + PhaseAbbrev(phase) + "-" + tostring(epochSec);
        
        if (seenIds.Exists(e.id)) {
            continue;
        }
        seenIds[e.id] = true;

        e.title = PhaseDisplayTitle(phase);
        e.startMs = epochSec * 1000;
        local_events.InsertLast(e);
    }
}

void ProcessApiResponse(Json::Value@ root, bool isInitialFetch) {
    array<EventItem@> local_events;
    ParsePhasedata(root, local_events);

    if (local_events.IsEmpty()) {
        warn("[Moon] No valid events found in the API response.");
        UI::ShowNotification("Moon Calendar", "No moon phases found for this date.", vec4(1,1,0,1), 5000);
        return;
    }
    
    g_Events = local_events;
    g_MonthEventCache.DeleteAll();
    for (uint i = 0; i < g_Events.Length; i++) {
        auto@ evt = g_Events[i];
        if (evt is null) continue;

        int Y, M, D;
        UtcYMDFromMs(evt.startMs, Y, M, D);
        if (Y == g_UIState.CalYear && M == g_UIState.CalMonth) {
            string key = tostring(D);
            if (!g_MonthEventCache.Exists(key)) {
                g_MonthEventCache[key] = evt;
            }
        }
    }
    
    if (isInitialFetch) {
        trace("[Moon] Successfully fetched " + g_Events.Length + " main events.");
        if (!g_InitialNotificationsShown) {
            Event_ShowStartupNotifications();
            g_InitialNotificationsShown = true;
        }
    } else {
        g_LastFetchedYear = g_UIState.CalYear;
        g_LastFetchedMonth = g_UIState.CalMonth;
        trace("[Moon] Fetched " + g_Events.Length + " events for calendar: " + g_UIState.CalYear + "-" + g_UIState.CalMonth);
    }
}

void FetchCoroutine(ref@ args_ref) {
    dictionary@ args = cast<dictionary>(args_ref);
    if (args is null || !args.Exists("url") || !args.Exists("requestID")) { 
        error("[Moon] Invalid args for FetchCoroutine."); 
        return; 
    }
    
    string url = string(args["url"]);
    bool isInitialFetch = bool(args["isInitialFetch"]);
    uint requestID = uint(args["requestID"]);

    if (!isInitialFetch) {
        g_IsLoading = true;
    }
    trace("[Moon] Fetching (ID: " + requestID + "): " + url);
    
    Net::HttpRequest@ req = Net::HttpGet(url);
    while (!req.Finished()) { 
        yield(); 
    }
    
    if (requestID != FetchInternal::g_FetchRequestID) {
        trace("[Moon] Ignoring stale fetch response (ID: " + requestID + ", current: " + FetchInternal::g_FetchRequestID + ")");
        if (!isInitialFetch) g_IsLoading = false; 
        return;
    }
    
    if (!isInitialFetch) {
        g_IsLoading = false;
    }

    if (req.ResponseCode() != 200) {
        string errorMsg = "[Moon] API call failed with HTTP " + req.ResponseCode();
        error(errorMsg);
        UI::ShowNotification("Moon Calendar Error", "Server connection failed (HTTP " + req.ResponseCode() + ").", vec4(1,0,0,1), 6000);
        return;
    }

    Json::Value@ root;
    try { 
        @root = Json::Parse(req.String()); 
    } catch { 
        error("[Moon] Failed to parse JSON. Response starts with: " + req.String().SubStr(0, 200));
        UI::ShowNotification("Moon Calendar Error", "Invalid data received from server.", vec4(1,0,0,1), 6000);
        return; 
    }

    ProcessApiResponse(root, isInitialFetch);
}