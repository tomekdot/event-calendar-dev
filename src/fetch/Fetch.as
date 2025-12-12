/**
 * @namespace FetchInternal
 * Namespace for internal variables and constants related to data fetching.
 */
namespace FetchInternal {
    // Global counter to track unique network request IDs.
    uint g_FetchRequestID = 0;

    // Base URL for the USNO API.
    const string API_BASE_URL = "https://aa.usno.navy.mil/api/moon/phases/date";

    // Default number of moon phases to request.
    const int DEFAULT_NUM_PHASES = 50;

    // Maximum number of retry attempts after the initial request fails.
    const int MAX_RETRY_ATTEMPTS = 2;

    // Base sleep duration (in milliseconds) for the first retry.
    const int RETRY_SLEEP_MS = 500;

    // Multiplier for exponential backoff (e.g., 2 means delay doubles with each retry).
    const int RETRY_BACKOFF_BASE = 2;

    // Time-To-Live (TTL) for cached API responses, in milliseconds.
    const int64 CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

    // A safety cap on the total time allowed for all retries combined to prevent indefinite waiting.
    const int MAX_TOTAL_RETRY_MS = 15 * 1000; // 15 seconds
}

/**
 * @namespace Fetch
 * Main namespace for managing the fetching and processing of moon phase data.
 * Features a two-layer cache (raw response and parsed events) and robust retry logic
 * with exponential backoff.
 */
namespace Fetch {
    // Defines a function type (callback) for successful data fetches.
    funcdef void FetchSuccessHandler(const array<EventItem@>@ events, bool isInitial);

    // Dictionary to store success handlers for specific requests.
    dictionary@ g_FetchHandlers = dictionary();
    // Per-request metadata: requestID (string) -> isInitialFetch (bool)
    dictionary@ g_FetchRequestIsInitial = dictionary();

    // --- L1 Cache: Raw Response Body ---
    /** A cache storing the raw string body of successful API responses. Key: full URL. */
    dictionary@ g_ResponseCacheBodies = dictionary();
    /** A parallel dictionary storing the timestamp when each raw response was cached. Key: full URL. */
    dictionary@ g_ResponseCacheTs = dictionary();

    // --- L2 Cache: Parsed Event Objects ---
    /** A cache storing the fully parsed array of EventItem objects. Key: full URL. */
    dictionary@ g_ParsedCacheEvents = dictionary();
    /** A parallel dictionary storing the timestamp when each parsed event array was cached. Key: full URL. */
    dictionary@ g_ParsedCacheTs = dictionary();
    /** Map of in-flight requests to coalesce duplicate fetches: url -> array<uint> of requestIDs waiting for result. */
    dictionary@ g_InFlightRequests = dictionary();

    // URLs we've scheduled a coroutine start for but which haven't yet entered FetchCoroutine.
    dictionary@ g_PendingStarts = dictionary();
    // Optional per-URL last-start timestamp to avoid re-scheduling different starts too frequently (ms)
    dictionary@ g_LastStartTs = dictionary();


    // --- Raw Response Cache (L1) Helpers ---

    /** Attempts to retrieve a fresh raw response from the L1 cache. */
    bool GetCachedResponse(const string &in url, string &out outBody) {
        if (!g_ResponseCacheBodies.Exists(url) || !g_ResponseCacheTs.Exists(url)) return false;
        int64 cachedTimestamp = int64(g_ResponseCacheTs[url]);
        if ((int64(Time::Stamp) * 1000) - cachedTimestamp > FetchInternal::CACHE_TTL_MS) {
            g_ResponseCacheBodies.Delete(url);
            g_ResponseCacheTs.Delete(url);
            return false;
        }
        outBody = string(g_ResponseCacheBodies[url]);
        return true;
    }

    /** Stores a raw API response in the L1 cache. */
    void SetCachedResponse(const string &in url, const string &in body) {
        g_ResponseCacheBodies[url] = body;
        g_ResponseCacheTs[url] = int64(Time::Stamp) * 1000;
    }

    // --- Parsed Events Cache (L2) Helpers ---

    /** Attempts to retrieve a fresh array of parsed events from the L2 cache. */
    bool GetCachedParsedEvents(const string &in url, array<EventItem@>@ &out outEvents) {
        // Basic existence check
        if (!g_ParsedCacheEvents.Exists(url) || !g_ParsedCacheTs.Exists(url)) return false;

        // Defensive read of timestamp: cast and handle any unexpected value
        int64 cachedTimestamp = 0;
        try { cachedTimestamp = int64(g_ParsedCacheTs[url]); } catch {
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }

        if ((int64(Time::Stamp) * 1000) - cachedTimestamp > FetchInternal::CACHE_TTL_MS) {
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }

        // Return a shallow copy to avoid callers mutating the internal cached array.
        // Defensive retrieval: the stored object might be null or of unexpected type.
        array<EventItem@>@ stored = null;
        try {
            @stored = cast<array<EventItem@>@>(g_ParsedCacheEvents[url]);
        } catch {
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }
        if (stored is null) {
            // corrupted or null entry - purge and treat as miss
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }
        array<EventItem@> copy;
        try {
            copy.Resize(stored.Length);
            for (uint i = 0; i < stored.Length; i++) copy[i] = stored[i];
        } catch {
            // If anything odd happens while copying, purge and treat as miss
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }
        @outEvents = @copy;
        return true;
    }

    /** Stores an array of parsed events in the L2 cache. */
    void SetCachedParsedEvents(const string &in url, const array<EventItem@>@ events) {
        // Defensive store: protect internal cache from external mutation and avoid null derefs.
        if (url.Length == 0) return;
        if (events is null) {
            // store empty array to mark we've processed this URL
            g_ParsedCacheEvents[url] = array<EventItem@>();
            g_ParsedCacheTs[url] = int64(Time::Stamp) * 1000;
            return;
        }

        uint n = events.Length;
        array<EventItem@> stored;
        stored.Resize(n);
        for (uint i = 0; i < n; i++) {
            // allow null entries but copy reference safely
            @stored[i] = events[i];
        }

        // Protect cache writes from unexpected exceptions
        try {
            g_ParsedCacheEvents[url] = stored;
            g_ParsedCacheTs[url] = int64(Time::Stamp) * 1000;
            if (S_EnableDebug) trace("[Moon] L2 cache stored parsed events for: " + url + " (count=" + tostring(stored.Length) + ")");
        } catch {
            warn("[Moon] Failed to write parsed events cache for url: " + url);
        }
    }

    // (Optional integrations removed.)
    
    /** Build the API URL for a given date. Honors S_MoonApiUrl override and num phases setting. */
    string BuildApiUrl(int year, int month, int day) {
        string baseUrl = S_MoonApiUrl.Length == 0 ? FetchInternal::API_BASE_URL : S_MoonApiUrl.Split('?')[0];
        int numPhases = S_USNO_NumP <= 0 ? FetchInternal::DEFAULT_NUM_PHASES : S_USNO_NumP;
        string dateForApi = tostring(year) + "-" + TimeUtils::Two(month) + "-" + TimeUtils::Two(day);

        string url = baseUrl + "?date=" + dateForApi;
        return Helpers::AppendQueryParam(url, "nump", tostring(numPhases));
    }

    void StartFetchCoroutine(const string &in url, bool isInitial) {
        // Avoid scheduling duplicate starts for the same URL if one is already pending
        if (g_PendingStarts.Exists(url)) {
            if (S_EnableDebug) trace("[Moon] Start already pending for URL: " + url);
            return;
        }

        // Optional cooldown: do not start a new fetch for the same URL within 2 seconds
        int64 nowMs = int64(Time::Stamp) * 1000;
        if (g_LastStartTs.Exists(url)) {
            int64 last = int64(g_LastStartTs[url]);
            if (nowMs - last < 2000) {
                if (S_EnableDebug) trace("[Moon] Skipping rapid re-start for URL: " + url);
                return;
            }
        }

        FetchInternal::g_FetchRequestID++;
        uint requestID = FetchInternal::g_FetchRequestID;
        // remember per-request isInitial flag so primary can notify waiters correctly
        g_FetchRequestIsInitial[tostring(requestID)] = isInitial;

        dictionary args;
        args["url"] = url;
        args["isInitialFetch"] = isInitial;
        args["requestID"] = requestID;

        // mark pending before starting coroutine so other callers don't duplicate it
        g_PendingStarts[url] = true;
        g_LastStartTs[url] = nowMs;
        startnew(FetchCoroutine, args);
    }

    void StartFetchCoroutineWithHandler(const string &in url, bool isInitial, FetchSuccessHandler@ handler) {
        // Avoid scheduling duplicate starts for the same URL
        if (g_PendingStarts.Exists(url)) {
            if (S_EnableDebug) trace("[Moon] StartWithHandler already pending for URL: " + url);
            return;
        }

        int64 nowMs = int64(Time::Stamp) * 1000;
        if (g_LastStartTs.Exists(url)) {
            int64 last = int64(g_LastStartTs[url]);
            if (nowMs - last < 2000) {
                if (S_EnableDebug) trace("[Moon] Skipping rapid re-startWithHandler for URL: " + url);
                return;
            }
        }

        FetchInternal::g_FetchRequestID++;
        uint requestID = FetchInternal::g_FetchRequestID;

        // remember per-request isInitial flag
        g_FetchRequestIsInitial[tostring(requestID)] = isInitial;

        if (handler !is null) {
            g_FetchHandlers[tostring(requestID)] = handler;
        }

        dictionary args;
        args["url"] = url;
        args["isInitialFetch"] = isInitial;
        args["requestID"] = requestID;

        // mark pending before starting coroutine so other callers don't duplicate it
        g_PendingStarts[url] = true;
        g_LastStartTs[url] = nowMs;
        startnew(FetchCoroutine, args);
    }

    void ClearHandlers() {
        g_FetchHandlers.DeleteAll();
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
        // Fetch USNO moon phases
        if (!S_EnableMoon) return;

        Time::Info currentTime = Time::Parse(Time::Stamp);
        string url = BuildApiUrl(currentTime.Year, currentTime.Month, currentTime.Day);
        StartFetchCoroutine(url, true);
    }

    void FetchForCalendarView() {
        bool isDataAlreadyFetched = (g_UIState.CalYear == g_LastFetchedYear && g_UIState.CalMonth == g_LastFetchedMonth);
        if (isDataAlreadyFetched && !g_Events.IsEmpty()) {
            return;
        }
        if (S_EnableMoon) {
            string url = BuildApiUrl(g_UIState.CalYear, g_UIState.CalMonth, 1);
            StartFetchCoroutine(url, false);
        } else {
            g_Events.Resize(0);
            RebuildMonthEventCache();
        }
    }
    
    /**
     * The core network request function. It performs an HTTP GET with a raw response cache (L1)
     * check and a retry mechanism with exponential backoff for failures.
     * @param url The URL to fetch.
     * @param outCode An output parameter that will be set to the final HTTP response code.
     * @return The response body as a string. Returns an empty string on failure.
     */
    string FetchResponseWithRetries(const string &in url, int &out outCode) {
        // 1. Try L1 cache first.
        string cachedBody;
        if (GetCachedResponse(url, cachedBody)) {
            outCode = 200;
            return cachedBody;
        }

        // 2. Perform network request with retries if L1 cache misses.
        Net::HttpRequest@ req;
        int lastCode = -1;
        int64 retryStartTime = int64(Time::Stamp) * 1000;

        for (int attempt = 0; attempt <= FetchInternal::MAX_RETRY_ATTEMPTS; attempt++) {
            @req = Net::HttpGet(url);
            while (!req.Finished()) yield();

            lastCode = req.ResponseCode();
            if (lastCode == 200) {
                string body = req.String();
                SetCachedResponse(url, body); // Populate L1 cache on success
                outCode = 200;
                return body;
            }
            // For 4xx errors (other than 429) do not retry — client error.
            if (lastCode >= 400 && lastCode < 500 && lastCode != 429) {
                if (S_EnableDebug) trace("[Moon] HTTP " + lastCode + " is a non-retryable client error.");
                break;
            }

            // If we are going to retry, calculate the sleep duration with exponential backoff.
            if (attempt < FetchInternal::MAX_RETRY_ATTEMPTS) {
                int backoffMs = FetchInternal::RETRY_SLEEP_MS * int(Math::Pow(FetchInternal::RETRY_BACKOFF_BASE, attempt));

                // Safety check: ensure we don't exceed the total allowed retry time.
                int64 elapsedMs = (int64(Time::Stamp) * 1000) - retryStartTime;
                if (elapsedMs + backoffMs > FetchInternal::MAX_TOTAL_RETRY_MS) {
                    if (S_EnableDebug) trace("[Moon] Exceeded max total retry time. Aborting retries.");
                    break;
                }

                sleep(backoffMs);
            }
        }
        
        outCode = lastCode;
        return "";
    }
    
    /**
     * The main coroutine that orchestrates the data fetching process. It uses a two-layer
     * cache (L2 for parsed events, L1 for raw responses) and delegates network calls
     * to `FetchResponseWithRetries`.
     */
    void FetchCoroutine(ref@ args_ref) {
        dictionary@ args = cast<dictionary>(args_ref);
        string url;
        bool isInitialFetch = false;
        uint requestID = 0;
        if (!UnpackFetchArgs(args, url, isInitialFetch, requestID)) {
            error("[Moon] Invalid args for FetchCoroutine.");
            return;
        }

        // We marked this URL as pending before starting the coroutine; clear it now that the coroutine has begun.
        if (g_PendingStarts.Exists(url)) g_PendingStarts.Delete(url);

        if (!isInitialFetch) g_IsLoading = true;

        // 1. Try the L2 cache first (parsed events).
        array<EventItem@>@ cachedParsed = null;
        if (GetCachedParsedEvents(url, cachedParsed)) {
            if (S_EnableDebug) trace("[Moon] L2 Cache Hit (parsed events) for: " + url);
            UpdateEventsAndCache(cachedParsed);
            if (!isInitialFetch) g_IsLoading = false;
            
            // Handle success logic directly from cache.
            if (isInitialFetch) HandleInitialFetchSuccess();
            else HandleCalendarFetchSuccess();

            // Invoke any registered handler.
            string requestKeyCached = tostring(requestID);
            if (g_FetchHandlers.Exists(requestKeyCached)) {
                FetchSuccessHandler@ handler = cast<FetchSuccessHandler>(g_FetchHandlers[requestKeyCached]);
                if (handler !is null) {
                    try { handler(@g_Events, isInitialFetch); }
                    catch { warn("[Moon] Fetch handler threw an exception."); }
                }
                g_FetchHandlers.Delete(requestKeyCached);
            }
            return;
        }

        // 2. If L2 misses, attempt to coalesce with any in-flight fetch for the same URL.
        if (S_EnableDebug) trace("[Moon] L2 Cache Miss. Checking in-flight for URL (ID: " + requestID + "): " + url);

        // If there's already an in-flight request for this URL, join it and return: primary will notify waiters.
        if (g_InFlightRequests.Exists(url)) {
            array<uint>@ waitList = cast<array<uint>@>(g_InFlightRequests[url]);
            if (waitList is null) {
                array<uint> newList;
                newList.InsertLast(requestID);
                g_InFlightRequests[url] = newList;
            } else {
                waitList.InsertLast(requestID);
            }

            if (S_EnableDebug) trace("[Moon] Joined existing in-flight request for URL: " + url + " (ID: " + requestID + ")");
            return;
        }

        if (S_EnableDebug) trace("[Moon] Performing network fetch (ID: " + requestID + "): " + url);
        g_InFlightRequests[url] = array<uint>();
        array<uint>@ primaryList = cast<array<uint>@>(g_InFlightRequests[url]);
        primaryList.InsertLast(requestID);

        int httpCode = -1;
        string body = FetchResponseWithRetries(url, httpCode);

        // 3. After the fetch is complete, check for staleness.
        if (requestID != FetchInternal::g_FetchRequestID) {
            if (S_EnableDebug) trace("[Moon] Ignoring stale fetch response (ID: " + requestID + ")");
            if (!isInitialFetch) g_IsLoading = false;
            return;
        }
        
        if (!isInitialFetch) g_IsLoading = false;

        // 4. Handle fetch result.
        if (httpCode != 200) {
            string errorMsg = Moon::kLogTag + " API call failed after retries with HTTP " + httpCode;
            error(errorMsg);
            if (S_EnableNotifications) UI::ShowNotification("Moon Calendar Error", "Server connection failed (HTTP " + httpCode + ").", vec4(1, 0, 0, 1), 6000);
            return;
        }

        // 5. Parse the response body.
        Json::Value@ root;
        try {
            @root = Json::Parse(body);
        } catch {
            // Handle JSON parsing error
            string responsePreview = body;
            if (responsePreview.Length > 200) responsePreview = responsePreview.SubStr(0, 200) + "...";
            error(Moon::kLogTag + " Failed to parse JSON. Response starts with: " + responsePreview);
            if (S_EnableNotifications) UI::ShowNotification("Moon Calendar Error", "Invalid data received from server.", vec4(1, 0, 0, 1), 6000);
            return;
        }

        // 6. Process the parsed data.
        ProcessApiResponse(root, isInitialFetch);
        
        // 7. Populate the L2 cache with the newly parsed events.
        SetCachedParsedEvents(url, g_Events);

        // 8. Invoke any registered handler for the primary request.
        string requestKey = tostring(requestID);
        if (g_FetchHandlers.Exists(requestKey)) {
            FetchSuccessHandler@ handler = cast<FetchSuccessHandler>(g_FetchHandlers[requestKey]);
            if (handler !is null) {
                try { handler(@g_Events, isInitialFetch); }
                catch { warn("[Moon] Fetch handler threw an exception."); }
            }
            g_FetchHandlers.Delete(requestKey);
        }
    if (g_FetchRequestIsInitial.Exists(requestKey)) g_FetchRequestIsInitial.Delete(requestKey);

        // Notify and invoke handlers for any waiting requestIDs that joined this in-flight request.
        if (g_InFlightRequests.Exists(url)) {
            array<uint>@ waitList = cast<array<uint>@>(g_InFlightRequests[url]);
            if (waitList !is null) {
                for (uint i = 0; i < waitList.Length; i++) {
                    uint waiterID = waitList[i];
                    string waiterKey = tostring(waiterID);
                    // Determine isInitial for this waiter (stored earlier)
                    bool waiterIsInitial = g_FetchRequestIsInitial.Exists(waiterKey) ? bool(g_FetchRequestIsInitial[waiterKey]) : false;
                    if (g_FetchHandlers.Exists(waiterKey)) {
                        FetchSuccessHandler@ wHandler = cast<FetchSuccessHandler>(g_FetchHandlers[waiterKey]);
                        if (wHandler !is null) {
                            try { wHandler(@g_Events, waiterIsInitial); } catch { warn("[Moon] Waiter handler threw an exception."); }
                        }
                        g_FetchHandlers.Delete(waiterKey);
                    }
                    // remove stored isInitial meta
                    if (g_FetchRequestIsInitial.Exists(waiterKey)) g_FetchRequestIsInitial.Delete(waiterKey);
                }
            }
            g_InFlightRequests.Delete(url);
        }
    }
    
    // (The remaining functions like ParsePhaseData, ProcessApiResponse, UpdateEventsAndCache, etc.,
    // would follow here without changes, as their logic remains the same.)
    
    void ParsePhaseData(Json::Value@ root, array<EventItem@>@ local_events) {
        if (root is null || !root.HasKey("phasedata") || root["phasedata"].GetType() != Json::Type::Array) {
            return;
        }
        Json::Value@ phaseDataArray = root["phasedata"];
        dictionary seenIds;
        for (uint i = 0; i < phaseDataArray.Length; i++) {
            auto@ row = phaseDataArray[i];
            if (!row.HasKey("phase") || !row.HasKey("year") || !row.HasKey("month") || !row.HasKey("day")) continue;
            string phase = string(row["phase"]);
            int Y = int(row["year"]), M = int(row["month"]), D = int(row["day"]);
            string timeStr = row.HasKey("time") ? string(row["time"]) : "00:00:00";
            int h = 0, m = 0, s = 0;
            if (!Helpers::ParseTimeString(timeStr, h, m, s)) warn(Moon::kLogTag + " Unrecognized time format: '" + timeStr + "'");
            int64 epochSec = Helpers::StampFromUTC(Y, M, D, h, m, s);
            if (epochSec <= 0) continue;
            EventItem@ e = EventItem();
            e.id = "USNO-" + Moon::PhaseAbbrev(phase) + "-" + tostring(epochSec);
            if (seenIds.Exists(e.id)) continue;
            seenIds[e.id] = true;
            e.title = Moon::PhaseDisplayTitle(phase);
            e.startMs = epochSec * 1000;
            e.source = "UNSO";
            local_events.InsertLast(e);
        }
    }

    void ProcessApiResponse(Json::Value@ root, bool isInitialFetch) {
        array<EventItem@> parsedEvents;
        ParsePhaseData(root, parsedEvents);
        if (parsedEvents.Length == 0) {
            warn("[Moon] No valid events found in the API response.");
            if (S_EnableNotifications) UI::ShowNotification("Moon Calendar", "No moon phases found for this date.", vec4(1, 1, 0, 1), 5000);
            return;
        }
        UpdateEventsAndCache(parsedEvents);
        if (isInitialFetch) HandleInitialFetchSuccess();
        else HandleCalendarFetchSuccess();
    }

    void UpdateEventsAndCache(const array<EventItem@>@ local_events) {
        if (local_events is null) {
            g_Events = array<EventItem@>();
        } else {
            g_Events = local_events;
        }
        
        if (S_EnableDebug) {
            trace("[Moon] UpdateEventsAndCache: incoming=" + tostring(local_events is null ? 0 : local_events.Length));
            trace("[Moon] UpdateEventsAndCache: g_Events now=" + tostring(g_Events.Length));
        }

        // Dump first few events to help debug why they may not appear in UI (only in debug mode)
        if (S_EnableDebug) {
            int dumpCount = int(g_Events.Length);
            if (dumpCount > 0) {
                int limit = dumpCount < 5 ? dumpCount : 5;
                for (int di = 0; di < limit; di++) {
                    auto@ ev = g_Events[uint(di)];
                    if (ev is null) {
                        trace("[Moon] EventDump idx=" + tostring(di) + " <null>");
                        continue;
                    }
                    int Y, M, D, h, m, s;
                    TimeUtils::UtcYMDHMSFromMs(ev.startMs, Y, M, D, h, m, s);
                    string dt = tostring(Y) + "-" + TimeUtils::Two(M) + "-" + TimeUtils::Two(D) + " " + TimeUtils::Two(h) + ":" + TimeUtils::Two(m) + ":" + TimeUtils::Two(s);
                    trace("[Moon] EventDump idx=" + tostring(di) + " id=" + ev.id + " date=" + dt + " title=\"" + ev.title + "\" source=" + ev.source);
                }
            }
        }

        RebuildMonthEventCache();
    }
    
    void HandleInitialFetchSuccess() {
        if (S_EnableDebug) trace("[Moon] Successfully fetched " + g_Events.Length + " main events.");
        if (!g_InitialNotificationsShown) {
            Notifications::ShowStartupNotifications();
            g_InitialNotificationsShown = true;
        }
    }
    
    void HandleCalendarFetchSuccess() {
        g_LastFetchedYear = g_UIState.CalYear;
        g_LastFetchedMonth = g_UIState.CalMonth;
        if (S_EnableDebug) trace("[Moon] Fetched " + g_Events.Length + " events for calendar: " + g_UIState.CalYear + "-" + g_UIState.CalMonth);
    }
    
}
