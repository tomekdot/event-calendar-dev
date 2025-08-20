namespace FetchInternal {
    uint g_FetchRequestID = 0;
    const string API_BASE_URL = "https://aa.usno.navy.mil/api/moon/phases/date";
}

funcdef void FetchSuccessHandler(const array<EventItem@>@ events, bool isInitial);

array<FetchSuccessHandler@> g_FetchHandlers;

string BuildApiUrl(int year, int month, int day) {
    string baseUrl = S_MoonApiUrl.Length == 0 ? FetchInternal::API_BASE_URL : S_MoonApiUrl.Split('?')[0];
    int numPhases = S_USNO_NumP <= 0 ? 50 : S_USNO_NumP;
    string dateForApi = tostring(year) + "-" + Two(month) + "-" + Two(day);

    string url = baseUrl + "?date=" + dateForApi;
    return Helpers::AppendQueryParam(url, "nump", tostring(numPhases));
}

void StartFetchCoroutine(const string &in url, bool isInitial) {
    FetchInternal::g_FetchRequestID++; 

    dictionary args;
    args["url"] = url;
    args["isInitialFetch"] = isInitial;
    args["requestID"] = FetchInternal::g_FetchRequestID; 

    startnew(FetchCoroutine, args);
}

void StartFetchCoroutineWithHandler(const string &in url, bool isInitial, FetchSuccessHandler@ handler) {
    FetchInternal::g_FetchRequestID++;

    int handlerIdx = -1;
    if (handler !is null) {
        g_FetchHandlers.InsertLast(handler);
        handlerIdx = int(g_FetchHandlers.Length) - 1;
    }

    dictionary args;
    args["url"] = url;
    args["isInitialFetch"] = isInitial;
    args["requestID"] = FetchInternal::g_FetchRequestID;
    if (handlerIdx >= 0) args["handlerIdx"] = handlerIdx;

    startnew(FetchCoroutine, args);
}

bool UnpackFetchArgs(dictionary@ args, string &out url, bool &out isInitialFetch, uint &out requestID) {
    if (args is null) return false;
    if (!args.Exists("url") || !args.Exists("requestID")) return false;
    url = string(args["url"]);
    isInitialFetch = args.Exists("isInitialFetch") ? bool(args["isInitialFetch"]) : false;
    requestID = uint(args["requestID"]);
    return true;
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

    UpdateEventsAndCache(local_events);

    if (isInitialFetch) {
        HandleInitialFetchSuccess();
    } else {
        HandleCalendarFetchSuccess();
    }
}

void UpdateEventsAndCache(const array<EventItem@>@ local_events) {
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
}

void HandleInitialFetchSuccess() {
    if (S_EnableDebug) trace("[Moon] Successfully fetched " + g_Events.Length + " main events.");
    if (!g_InitialNotificationsShown) {
        Event_ShowStartupNotifications();
        g_InitialNotificationsShown = true;
    }
}

void HandleCalendarFetchSuccess() {
    g_LastFetchedYear = g_UIState.CalYear;
    g_LastFetchedMonth = g_UIState.CalMonth;
    if (S_EnableDebug) trace("[Moon] Fetched " + g_Events.Length + " events for calendar: " + g_UIState.CalYear + "-" + g_UIState.CalMonth);
}

void FetchCoroutine(ref@ args_ref) {
    dictionary@ args = cast<dictionary>(args_ref);

    string url;
    bool isInitialFetch = false;
    uint requestID = 0;
    if (!UnpackFetchArgs(args, url, isInitialFetch, requestID)) {
        error("[Moon] Invalid args for FetchCoroutine.");
        return;
    }

    if (!isInitialFetch) {
        g_IsLoading = true;
    }
    if (S_EnableDebug) trace("[Moon] Fetching (ID: " + requestID + "): " + url);
    
    Net::HttpRequest@ req = Net::HttpGet(url);
    while (!req.Finished()) { 
        yield(); 
    }
    
    if (requestID != FetchInternal::g_FetchRequestID) {
        if (S_EnableDebug) trace("[Moon] Ignoring stale fetch response (ID: " + requestID + ", current: " + FetchInternal::g_FetchRequestID + ")");
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

    if (args !is null && args.Exists("handlerIdx")) {
        int idx = int(args["handlerIdx"]);
        if (idx >= 0 && idx < int(g_FetchHandlers.Length)) {
            FetchSuccessHandler@ h = g_FetchHandlers[idx];
            if (h !is null) {
                try { h(@g_Events, isInitialFetch); } catch { warn("[Moon] Fetch handler threw an exception."); }
            }
        }
    }
}