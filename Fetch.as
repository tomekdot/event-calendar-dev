void StartFetchCoroutine(const string &in url, bool isInitial) {
    dictionary args;
    args["url"] = url;
    args["isInitialFetch"] = isInitial;
    startnew(FetchCoroutine, args);
}

string GetApiUrl() {
    int numPhases = S_USNO_NumP <= 0 ? 50 : S_USNO_NumP;

    if (S_AutoDate) {
        string baseUrl = S_MoonApiUrl.Length == 0 ? "https://aa.usno.navy.mil/api/moon/phases/date" : S_MoonApiUrl.Split('?')[0];
        Time::Info tm = Time::Parse(Time::Stamp);
        string dateForApi = tostring(tm.Year) + "-" + Two(tm.Month) + "-" + Two(tm.Day);
        return baseUrl + "?date=" + dateForApi + "&nump=" + tostring(numPhases);
    } else {
        if (S_MoonApiUrl.IndexOf("nump=") == -1) {
            if (S_MoonApiUrl.IndexOf('?') == -1) return S_MoonApiUrl + "?nump=" + tostring(numPhases);
            return S_MoonApiUrl + "&nump=" + tostring(numPhases);
        }
        return S_MoonApiUrl;
    }
}

void FetchLatestData() {
    if (!S_EnableMoon) return;
    StartFetchCoroutine(GetApiUrl(), true);
}

void FetchForCalendarView() {
    if (!S_EnableMoon) { g_Events.Resize(0); return; }
    if (g_UIState.CalYear == g_LastFetchedYear && g_UIState.CalMonth == g_LastFetchedMonth && !g_Events.IsEmpty()) return;

    string baseUrl = S_MoonApiUrl.Length == 0 ? "https://aa.usno.navy.mil/api/moon/phases/date" : S_MoonApiUrl.Split('?')[0];
    int numPhases = S_USNO_NumP <= 0 ? 50 : S_USNO_NumP;
    string dateForApi = tostring(g_UIState.CalYear) + "-" + Two(g_UIState.CalMonth) + "-01";
    string url = baseUrl + "?date=" + dateForApi + "&nump=" + tostring(numPhases);
    
    StartFetchCoroutine(url, false);
}

void ParsePhasedata(Json::Value@ root, array<EventItem@>@ local_events) {
    if (root is null || !root.HasKey("phasedata") || root["phasedata"].GetType() != Json::Type::Array) return;
    Json::Value@ arr = root["phasedata"];
    dictionary seenIds;
    for (uint i = 0; i < arr.Length; i++) {
        auto@ row = arr[i];
        if (!row.HasKey("phase") || !row.HasKey("year") || !row.HasKey("month") || !row.HasKey("day")) continue;

        string phase = string(row["phase"]);
        int Y = int(row["year"]); int M = int(row["month"]); int D = int(row["day"]);
        string timeStr = row.HasKey("time") ? string(row["time"]) : "";
        int h = 0; int m = 0; int s = 0;
        if (timeStr.Length > 0) {
            int hh = 0; int mm = 0; int ss = 0;
            if (!Helpers::ParseTimeString(timeStr, hh, mm, ss)) {
                warn("[Moon] Unrecognized time format from API: '" + timeStr + "' — defaulting to 00:00:00");
                h = 0; m = 0; s = 0;
            } else {
                h = hh; m = mm; s = ss;
            }
        }

        int64 epochSec = Helpers::StampFromUTC(Y, M, D, h, m, s);
        if (epochSec <= 0) continue;

        EventItem@ e = EventItem();
        e.id = "USNO-" + PhaseAbbrev(phase) + "-" + tostring(epochSec);
        if (seenIds.Exists(e.id)) continue;
        seenIds[e.id] = true;
        e.title = PhaseDisplayTitle(phase);
        e.startMs = epochSec * 1000;
        local_events.InsertLast(e);
    }
}

void FetchCoroutine(ref@ args_ref) {
    dictionary@ args = cast<dictionary>(args_ref);
    if(args is null || !args.Exists("url") || !args.Exists("isInitialFetch")) { error("[Moon] Invalid arguments for FetchCoroutine."); return; }
    string url = string(args["url"]);
    bool isInitialFetch = bool(args["isInitialFetch"]);

    if (!isInitialFetch) g_IsLoading = true;
    trace("[Moon] Fetching from: " + url);
    
    Net::HttpRequest@ req = Net::HttpGet(url);
    while (!req.Finished()) { yield(); }
    
    if (!isInitialFetch) g_IsLoading = false;

    if (req.ResponseCode() != 200) {
        string errorMsg = "[Moon] API call failed with HTTP " + req.ResponseCode();
        error(errorMsg);
        UI::ShowNotification("Moon Calendar Error", "Could not fetch data from the server (HTTP " + req.ResponseCode() + ").", vec4(1,0,0,1), 6000);
        return;
    }

    Json::Value@ root;
    try { 
        string body = req.String();
        @root = Json::Parse(body); 
    } catch { 
        string snippet = req.String().SubStr(0, Math::Min(512, req.String().Length));
        error("[Moon] Failed to parse JSON from API. Response snippet: " + snippet);
        UI::ShowNotification("Moon Calendar Error", "Received invalid data from the server.", vec4(1,0,0,1), 6000);
        return; 
    }

    array<EventItem@> local_events;
    ParsePhasedata(root, local_events);

    if (local_events.IsEmpty()) {
        warn("[Moon] No valid events found in the API response.");
        UI::ShowNotification("Moon Calendar Warning", "No moon phases found for the requested date.", vec4(1,1,0,1), 6000);
        return;
    }
    g_Events = local_events;
    
    if (isInitialFetch) {
        trace("[Moon] Successfully fetched " + g_Events.Length + " main events (initial).");
        if (g_Events.Length > 0) {
            int64 nowMs = int64(Time::Stamp) * 1000;
            int idx = -1;
                    for (uint ii = 0; ii < g_Events.Length; ii++) {
                        auto@ ev = g_Events[ii];
                        if (ev is null) continue;
                        if (ev.startMs > nowMs) { idx = int(ii); break; }
                    }
                    if (idx >= 0) {
                        auto@ nextEv = g_Events[idx];
                        if (nextEv !is null) trace("[Moon] Next upcoming event: " + nextEv.title + " at ms=" + nextEv.startMs + " (nowMs=" + nowMs + ")");
                        else trace("[Moon] Next upcoming event: <null handle> (nowMs=" + nowMs + ")");
                    }
            else trace("[Moon] No upcoming events found (all events are in the past). nowMs=" + nowMs);
        }
        if (!g_InitialNotificationsShown) {
            Event_ShowStartupNotifications();
            g_InitialNotificationsShown = true;
        } else {
            trace("[Moon] Successfully refreshed " + g_Events.Length + " main events.");
        }
    } else {
        g_LastFetchedYear = g_UIState.CalYear;
        g_LastFetchedMonth = g_UIState.CalMonth;
        trace("[Moon] Successfully fetched " + g_Events.Length + " events for calendar view.");
    }
}
