/*
 * @namespace FetchInternal
 * Internal namespace for constants and shared state used by the Fetch module.
 */
namespace FetchInternal {
    // Global counter to generate unique request IDs for tracking and coalescing.
    uint g_FetchRequestID = 0;

    // --- API Configuration ---
    const string API_BASE_URL = "https://aa.usno.navy.mil/api/moon/phases/date";
    const int DEFAULT_NUM_PHASES = 50;

    // --- Retry Configuration ---
    const int MAX_RETRY_ATTEMPTS = 3;          // Total attempts = initial + retries
    const int RETRY_SLEEP_MS = 1000;           // Initial backoff (1 second)
    const int RETRY_BACKOFF_BASE = 2;          // Exponential multiplier
    const int MAX_TOTAL_RETRY_MS = 60 * 1000;  // 60 seconds safety cap
    const int MAX_CONSECUTIVE_FAILURES = 5;    // Max consecutive failures before forced cooldown
    int g_ConsecutiveFailures = 0;             // Track consecutive failures
    int64 g_LastFailureMs = 0;                 // Timestamp of last failure

    // --- Cache Configuration ---
    const int64 CACHE_TTL_MS = 5 * 60 * 1000;           // 5 minutes normal TTL
    const int64 STALE_CACHE_TTL_MS = 60 * 60 * 1000;    // 60 minutes stale cache (usable when offline)

    // --- Auto-Reconnect Configuration ---
    const int AUTO_RETRY_INTERVAL_MS = 10000;           // Retry failed fetches every 10 seconds
    bool g_AutoRetryEnabled = true;                     // Enable automatic background retries
    int64 g_LastAutoRetryMs = 0;                        // Timestamp of last auto-retry

    // --- File Cache Configuration ---
    const string FILE_CACHE_DIR = "cache";                          // Directory for file-based cache
    const int64 FILE_CACHE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;    // 7 days max age for file cache

    // --- Debounce Configuration ---
    const int SAME_URL_DEBOUNCE_MS = 5000;   // Cooldown when re-fetching same URL
    const int DIFF_URL_DEBOUNCE_MS = 250;    // Cooldown when fetching different URL

    // --- Shared State ---
    int64 g_LastGlobalFetchStartMs = 0;
    string g_LastGlobalFetchUrl = "";
}

/*
 * @namespace Fetch
 * Manages fetching and processing of moon phase data with two-layer caching
 * (raw response and parsed events) and robust retry logic with exponential backoff.
 */
namespace Fetch {
    // --- Type Definitions ---
    funcdef void FetchSuccessHandler(const array<EventItem@>@ events, bool isInitial);

    // --- Request Tracking ---
    dictionary@ g_FetchHandlers = dictionary();
    dictionary@ g_FetchRequestIsInitial = dictionary();

    // --- L1 Cache: Raw Response Body ---
    dictionary@ g_ResponseCacheBodies = dictionary();
    dictionary@ g_ResponseCacheTs = dictionary();

    // --- L2 Cache: Parsed Event Objects ---
    dictionary@ g_ParsedCacheEvents = dictionary();
    dictionary@ g_ParsedCacheTs = dictionary();

    // --- Request Coalescing ---
    dictionary@ g_InFlightRequests = dictionary();      // url -> array of requestIDs
    dictionary@ g_PendingStarts = dictionary();         // url -> bool

    // --- File Cache Operations ---

    // Gets the cache directory path, creates it if needed
    string GetCacheDir() {
        string dir = "";
        try { dir = IO::FromStorageFolder(FetchInternal::FILE_CACHE_DIR); } catch { dir = ""; }
        if (dir.Length == 0) {
            try { dir = IO::FromUserGameFolder(FetchInternal::FILE_CACHE_DIR); } catch { dir = ""; }
        }
        if (dir.Length == 0 || !IO::FolderExists(dir)) {
            try { IO::CreateFolder(dir, true); } catch {}
        }
        return dir;
    }

    // Generate filename for month cache file
    string GetCacheFilePath(int year, int month) {
        return GetCacheDir() + "/moon_" + tostring(year) + "_" + tostring(month) + ".json";
    }

    // Persists the current month payload so the calendar can recover instantly after restart.
    void SaveToFileCache(int year, int month, const array<EventItem@>@ events) {
        string filepath = GetCacheFilePath(year, month);
        
        // Serialize only the fields the UI actually needs.
        Json::Value arr = Json::Array();
        for (uint i = 0; i < events.Length; i++) {
            auto@ ev = events[i];
            if (ev is null) continue;
            Json::Value item = Json::Object();
            item["id"] = ev.id;
            item["title"] = ev.title;
            item["startMs"] = ev.startMs;
            item["durationSec"] = ev.durationSec;
            item["description"] = ev.description;
            item["url"] = ev.url;
            item["source"] = ev.source;
            item["game"] = ev.game;
            arr.Add(item);
        }
        
        // Add minimal metadata used for expiry checks.
        Json::Value meta = Json::Object();
        meta["year"] = year;
        meta["month"] = month;
        meta["cachedAt"] = int64(Time::Stamp) * 1000;
        // Store the timestamp twice to avoid precision loss in parsers that coerce large ints.
        meta["cachedAtStr"] = tostring(int64(Time::Stamp) * 1000);
        meta["events"] = arr;
        
        string json = Json::Write(meta);
        try {
            IO::File f(filepath, IO::FileMode::Write);
            f.Write(json);
            f.Close();
        } catch {
            warn("[Moon] Failed to write file cache: " + filepath);
        }
        
        if (S_EnableDebug) trace("[Moon] Saved " + tostring(events.Length) + " events to file cache: " + filepath);
    }

    // Loads a previously saved month snapshot. When ignoreExpiration is true we still
    // accept stale data so the user can keep browsing offline.
    bool LoadFromFileCache(int year, int month, array<EventItem@>@ &out events, bool ignoreExpiration = false) {
        if (events is null) {
            @events = array<EventItem@>();
        } else {
           // Ensure we are working with a valid handle if passed from outside
           // although in current usage it should be fine.
        }

        string filepath = GetCacheFilePath(year, month);
        
        if (!IO::FileExists(filepath)) {
            if (S_EnableDebug) trace("[Moon] File cache not found: " + filepath);
            return false;
        }
        
        // Read and parse JSON once; avoid extra filesystem work outside this branch.
        string json = "";
        try {
            IO::File f(filepath, IO::FileMode::Read);
            while (!f.EOF()) {
                json += f.ReadLine();
            }
            f.Close();
        } catch {
            warn("[Moon] Failed to read file cache: " + filepath);
            return false;
        }
        
        Json::Value@ root = null;
        try { @root = Json::Parse(json); } catch {
            warn("[Moon] Failed to parse file cache: " + filepath);
            return false;
        }
        
        if (root is null) return false;
        
        // Recover cache age from either the current string field or the legacy numeric field.
        int64 cachedAtMs = 0;
        if (root.HasKey("cachedAtStr")) {
             // Prefer string version if available (new format)
             cachedAtMs = Text::ParseInt64(string(root["cachedAtStr"]));
        } else if (root.HasKey("cachedAt")) {
             auto@ val = root["cachedAt"];
             if (val.GetType() == Json::Type::String) {
                 cachedAtMs = Text::ParseInt64(string(val));
             } else {
                 // Convert through double to avoid 32-bit truncation in some Openplanet builds.
                 cachedAtMs = int64(double(val));
             }
        }
        
        // Reject missing/broken timestamps unless the caller explicitly asked for stale fallback.
        int64 currentMs = int64(Time::Stamp) * 1000;
        int64 maxFutureMs = 7 * 24 * 60 * 60 * 1000; // 1 week
        
        // Debug: log what's happening
        if (S_EnableDebug) {
            trace("[Moon] LoadFromFileCache: cachedAtMs=" + tostring(cachedAtMs) + " currentMs=" + tostring(currentMs));
            trace("[Moon] cachedAtMs < 2020? " + tostring(cachedAtMs < 1577836800000));
            trace("[Moon] cachedAtMs > currentMs? " + tostring(cachedAtMs > currentMs));
            if (cachedAtMs > currentMs) {
                trace("[Moon] cachedAtMs - currentMs = " + tostring(cachedAtMs - currentMs) + "ms");
            }
        }
        
        bool invalidTimestamp = (cachedAtMs == 0 || cachedAtMs < 1577836800000 || (cachedAtMs > currentMs && cachedAtMs - currentMs > maxFutureMs));
        
        if (!ignoreExpiration && invalidTimestamp) { // 2020-01-01 epoch
            if (S_EnableDebug) trace("[Moon] File cache has invalid timestamp: " + tostring(cachedAtMs));
            return false;
        } else if (ignoreExpiration && invalidTimestamp) {
            if (S_EnableDebug) trace("[Moon] Ignoring invalid timestamp (" + tostring(cachedAtMs) + ") due to force load");
        }
        
        if (!ignoreExpiration && currentMs - cachedAtMs > FetchInternal::FILE_CACHE_MAX_AGE_MS) {
            if (S_EnableDebug) trace("[Moon] File cache expired (age: " + tostring((currentMs - cachedAtMs) / 1000 / 60) + " min)");
            return false;
        }
        
        if (!root.HasKey("events")) {
            return false;
        }
        
        Json::Value@ arr = root["events"];
        if (arr is null || arr.GetType() != Json::Type::Array) return false;
        if (S_EnableDebug) trace("[Moon] LoadFromFileCache: Found events array");
        
        events.Resize(0);
        if (S_EnableDebug) trace("[Moon] LoadFromFileCache: events.Resize(0) ok");

        for (uint i = 0; i < arr.Length; i++) {
            try {
                if (S_EnableDebug && i == 0) trace("[Moon] LoadFromFileCache: processing first item");
                
                Json::Value@ item = arr[i];
                EventItem@ ev = EventItem();
                if (item.HasKey("id")) ev.id = string(item["id"]);
                if (item.HasKey("title")) ev.title = string(item["title"]);
                
                if (item.HasKey("startMs")) {
                    auto@ val = item["startMs"];
                    if (val.GetType() == Json::Type::String) {
                        ev.startMs = Text::ParseInt64(string(val));
                    } else {
                        ev.startMs = int64(double(val));
                    }
                }
                
                if (item.HasKey("durationSec")) ev.durationSec = int(item["durationSec"]);
                if (item.HasKey("description")) ev.description = string(item["description"]);
                if (item.HasKey("url")) ev.url = string(item["url"]);
                if (item.HasKey("source")) ev.source = string(item["source"]);
                if (item.HasKey("game")) ev.game = string(item["game"]);
                events.InsertLast(ev);
            } catch {
                warn("[Moon] Error parsing event item index " + i);
            }
        }
        
        if (S_EnableDebug) trace("[Moon] Loaded " + tostring(events.Length) + " events from file cache");
        return events.Length > 0;
    }

    // --- L1 Cache Operations ---

    bool GetCachedResponse(const string &in url, string &out outBody) {
        if (!g_ResponseCacheBodies.Exists(url) || !g_ResponseCacheTs.Exists(url)) return false;

        int64 cachedTimestamp = int64(g_ResponseCacheTs[url]);
        int64 nowMs = int64(Time::Stamp) * 1000;

        if (nowMs - cachedTimestamp > FetchInternal::CACHE_TTL_MS) {
            g_ResponseCacheBodies.Delete(url);
            g_ResponseCacheTs.Delete(url);
            return false;
        }
        outBody = string(g_ResponseCacheBodies[url]);
        return true;
    }

    void SetCachedResponse(const string &in url, const string &in body) {
        g_ResponseCacheBodies[url] = body;
        g_ResponseCacheTs[url] = int64(Time::Stamp) * 1000;
    }

    // --- L2 Cache Operations ---

    // Gets parsed events from memory cache. Returns true only for fresh entries.
    // With useStale=true, outEvents may still be populated with stale data for instant UI fallback.
    bool GetCachedParsedEvents(const string &in url, array<EventItem@>@ &out outEvents, bool useStale = false) {
        if (!g_ParsedCacheEvents.Exists(url) || !g_ParsedCacheTs.Exists(url)) return false;

        int64 cachedTimestamp = 0;
        
        try { cachedTimestamp = int64(g_ParsedCacheTs[url]); } catch {
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }

        int64 nowMs = int64(Time::Stamp) * 1000;
        int64 maxAge = useStale ? FetchInternal::STALE_CACHE_TTL_MS : FetchInternal::CACHE_TTL_MS;

        if (nowMs - cachedTimestamp > maxAge) {
            // Cache expired - delete if it's way past expiration
            if (nowMs - cachedTimestamp > FetchInternal::CACHE_TTL_MS * 12) {
                g_ParsedCacheEvents.Delete(url);
                g_ParsedCacheTs.Delete(url);
            }
            return false;
        }

        // Get cached events
        array<EventItem@>@ stored = null;
        try { @stored = cast<array<EventItem@>@>(g_ParsedCacheEvents[url]); } catch {
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }

        if (stored is null) {
            g_ParsedCacheEvents.Delete(url);
            g_ParsedCacheTs.Delete(url);
            return false;
        }

        // Return a detached array so callers can safely sort/filter without mutating cache state.
        array<EventItem@> copy;
        for (uint i = 0; i < stored.Length; i++) {
            if (stored[i] !is null) {
                copy.InsertLast(stored[i]);
            }
        }
        
        @outEvents = @copy;

        // Return true only if cache is fresh (not stale)
        return (nowMs - cachedTimestamp) <= FetchInternal::CACHE_TTL_MS;
    }

    void SetCachedParsedEvents(const string &in url, const array<EventItem@>@ events) {
        if (url.Length == 0) return;

        if (events is null) {
            g_ParsedCacheEvents[url] = array<EventItem@>();
            g_ParsedCacheTs[url] = int64(Time::Stamp) * 1000;
            return;
        }

        array<EventItem@> stored;
        stored.Resize(events.Length);
        for (uint i = 0; i < events.Length; i++) @stored[i] = events[i];

        try {
            g_ParsedCacheEvents[url] = stored;
            g_ParsedCacheTs[url] = int64(Time::Stamp) * 1000;
            if (S_EnableDebug) trace("[Moon] L2 cache stored: " + url + " (count=" + tostring(stored.Length) + ")");
        } catch {
            warn("[Moon] Failed to write L2 cache for: " + url);
        }
    }


    string BuildApiUrl(int year, int month, int day) {
        string baseUrl = S_MoonApiUrl.Length == 0 ? FetchInternal::API_BASE_URL : S_MoonApiUrl.Split('?')[0];
        int numPhases = S_USNO_NumP <= 0 ? FetchInternal::DEFAULT_NUM_PHASES : S_USNO_NumP;
        string dateStr = tostring(year) + "-" + TimeUtils::Two(month) + "-" + TimeUtils::Two(day);
        return Helpers::AppendQueryParam(baseUrl + "?date=" + dateStr, "nump", tostring(numPhases));
    }

    string GetCurrentCalendarUrl() {
        return BuildApiUrl(g_UIState.CalYear, g_UIState.CalMonth, 1);
    }

    // --- Debounce Helper ---

    // Rejects bursts of identical navigation requests before we spin up another coroutine.
    bool ShouldDebounce(const string &in url) {
        int64 nowMs = int64(Time::Stamp) * 1000;

        // Check if already pending
        if (g_PendingStarts.Exists(url)) {
            if (S_EnableDebug) trace("[Moon] Skip: pending start for URL");
            return true;
        }

        // Check global debounce
        int debounceMs = (url == FetchInternal::g_LastGlobalFetchUrl)
            ? FetchInternal::SAME_URL_DEBOUNCE_MS
            : FetchInternal::DIFF_URL_DEBOUNCE_MS;

        if (nowMs - FetchInternal::g_LastGlobalFetchStartMs < debounceMs) {
            if (S_EnableDebug) trace("[Moon] Skip: debounce (" + tostring(debounceMs) + "ms)");
            return true;
        }

        return false;
    }

    // --- Core Fetch Logic ---

    void _CleanupRequestState(const string &in url, bool clearPendingStart = false) {
        if (clearPendingStart && g_PendingStarts.Exists(url)) {
            g_PendingStarts.Delete(url);
        }
        if (g_InFlightRequests.Exists(url)) {
            g_InFlightRequests.Delete(url);
        }
    }

    void _FinishFetchState(bool isInitialFetch) {
        if (!isInitialFetch) {
            g_IsLoading = false;
        }
    }

    void _ClearPendingStart(const string &in url) {
        if (g_PendingStarts.Exists(url)) {
            g_PendingStarts.Delete(url);
        }
    }

    void _ApplyEvents(const array<EventItem@>@ events, bool persistToFile = false) {
        UpdateEventsAndCache(events, persistToFile);
        HandleCalendarFetchSuccess();
    }

    bool _TryApplyMemoryCache(const string &in url, bool allowStale = true) {
        array<EventItem@>@ cached = null;
        bool isFresh = GetCachedParsedEvents(url, cached, allowStale);
        if (cached is null || cached.Length == 0) {
            return false;
        }

        if (S_EnableDebug) {
            string cacheType = isFresh ? "fresh" : "stale";
            trace("[Moon] Using " + cacheType + " memory cache for: " + url);
        }

        _ApplyEvents(cached, false);
        if (!isFresh) {
            StartFetchCoroutine(url, false);
        }
        return true;
    }

    bool _TryApplyFileCacheForCurrentMonth(bool ignoreExpiration = false) {
        if (g_UIState.CalYear == 0 || g_UIState.CalMonth == 0) {
            return false;
        }

        try {
            array<EventItem@> fileCacheEvents;
            if (!LoadFromFileCache(g_UIState.CalYear, g_UIState.CalMonth, fileCacheEvents, ignoreExpiration)) {
                return false;
            }

            if (S_EnableDebug) {
                trace("[Moon] Using file cache for: " + tostring(g_UIState.CalMonth) + "/" + tostring(g_UIState.CalYear));
            }

            _ApplyEvents(fileCacheEvents, false);
            return true;
        } catch {
            warn("[Moon] Error loading from file cache");
            return false;
        }
    }

    void _ClearCurrentCalendarEvents() {
        g_Events.Resize(0);
        RebuildMonthEventCache();
    }

    void _SetApiErrorFromCode(int httpCode) {
        if (httpCode == -1) {
            g_ApiError = "Connection lost.";
        } else if (httpCode == 0) {
            g_ApiError = "Network unavailable.";
        } else {
            g_ApiError = "Server error (HTTP " + tostring(httpCode) + ").";
        }
    }

    void _HandleFetchFailure(const string &in url, int httpCode, bool isInitialFetch) {
        if (S_EnableDebug) {
            trace("[Moon] Fetch failed after retries: HTTP " + tostring(httpCode));
        }

        _SetApiErrorFromCode(httpCode);

        if (S_EnableNotifications) {
            UI::ShowNotification("Moon Calendar", g_ApiError, vec4(1, 0.5, 0, 1), 3000);
        }

        array<EventItem@>@ staleCache = null;
        if (GetCachedParsedEvents(url, staleCache, true) && staleCache !is null && staleCache.Length > 0) {
            if (S_EnableDebug) trace("[Moon] Using stale memory cache after fetch failure");
            _ApplyEvents(staleCache, false);
        } else {
            _TryApplyFileCacheForCurrentMonth(true);
        }

        _NotifyWaiters(url);
        _CleanupRequestState(url);

        if (!g_PendingStarts.Exists(url)) {
            if (S_EnableDebug) trace("[Moon] Scheduling automatic retry for: " + url);
            sleep(2000);
            StartFetchCoroutine(url, isInitialFetch);
        }
    }

    void StartFetchCoroutine(const string &in url, bool isInitial) {
        if (ShouldDebounce(url)) return;
        _InitAndStartFetch(url, isInitial, null);
    }

    void StartFetchCoroutineWithHandler(const string &in url, bool isInitial, FetchSuccessHandler@ handler) {
        if (ShouldDebounce(url)) return;
        _InitAndStartFetch(url, isInitial, handler);
    }

    void _InitAndStartFetch(const string &in url, bool isInitial, FetchSuccessHandler@ handler) {
        FetchInternal::g_FetchRequestID++;
        uint requestID = FetchInternal::g_FetchRequestID;

        g_FetchRequestIsInitial[tostring(requestID)] = isInitial;
        if (handler !is null) {
            g_FetchHandlers[tostring(requestID)] = handler;
        }

        dictionary args;
        args["url"] = url;
        args["isInitialFetch"] = isInitial;
        args["requestID"] = requestID;

        int64 nowMs = int64(Time::Stamp) * 1000;
        g_PendingStarts[url] = true;
        FetchInternal::g_LastGlobalFetchStartMs = nowMs;
        FetchInternal::g_LastGlobalFetchUrl = url;

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

    // --- Public Fetch Entry Points ---

    void FetchLatestData() {
        if (!S_EnableMoon) return;
        Time::Info currentTime = Time::Parse(Time::Stamp);

        // Always fetch from the 1st of the current month so we don't miss early phases
        StartFetchCoroutine(BuildApiUrl(currentTime.Year, currentTime.Month, 1), true);
    }

    void FetchForCalendarView() {
        string url = GetCurrentCalendarUrl();

        // Memory cache is the fastest path for month switching.
        if (_TryApplyMemoryCache(url, true)) {
            return;
        }

        // File cache is still fast enough to keep the UI responsive while network refresh happens later.
        if (_TryApplyFileCacheForCurrentMonth(false)) {
            StartFetchCoroutine(url, false);
            return;
        }

        // No cache available for this month, so clear the view and fetch asynchronously.
        _ClearCurrentCalendarEvents();
        
        if (S_EnableMoon) {
            StartFetchCoroutine(url, false);
        } else {
            g_ApiError = "Network disabled.";
        }
    }

    // Manual refresh keeps current month selected but clears failure cooldown state first.
    void RefreshCalendarData() {
        // Clear consecutive failures to allow fresh retry
        FetchInternal::g_ConsecutiveFailures = 0;
        FetchInternal::g_LastFailureMs = 0;
        FetchForCalendarView();
    }

    // Background auto-retry keeps the calendar alive after temporary connectivity issues.
    void AutoRetryFailedFetches() {
        // Auto-retry is only enabled when the feature is enabled and we have seen at least one failure, to avoid unnecessary work on stable connections.
        if (!FetchInternal::g_AutoRetryEnabled) return;
        if (!S_EnableMoon) return;
        int64 nowMs = int64(Time::Stamp) * 1000;
        // Rate-limit auto-retries to avoid hammering the endpoint during extended outages.
        if (nowMs - FetchInternal::g_LastAutoRetryMs < FetchInternal::AUTO_RETRY_INTERVAL_MS) return;

        FetchInternal::g_LastAutoRetryMs = nowMs;

        // Only retry if we have some failures but not too many
        if (FetchInternal::g_ConsecutiveFailures > 0 && FetchInternal::g_ConsecutiveFailures < FetchInternal::MAX_CONSECUTIVE_FAILURES) {
            if (g_UIState.CalYear != 0 && g_UIState.CalMonth != 0) {
                string url = GetCurrentCalendarUrl();
                if (!g_PendingStarts.Exists(url) && !g_InFlightRequests.Exists(url)) {
                    if (S_EnableDebug) trace("[Moon] Auto-retry fetch for: " + url);
                    StartFetchCoroutine(url, false);
                }
            }
        }
    }

    // --- Fetch Network Layer ---

    // Performs HTTP request with capped exponential backoff.
    bool FetchWithAutoRetry(const string &in url, string &out outBody) {
        int lastCode = -1;
        int64 retryStartTime = int64(Time::Stamp) * 1000;
        int attempt = 0;
        int consecutiveNetErrors = 0;

        while (attempt <= FetchInternal::MAX_RETRY_ATTEMPTS) {
            // After too many failures, pause briefly instead of hammering the endpoint every frame.
            if (FetchInternal::g_ConsecutiveFailures >= FetchInternal::MAX_CONSECUTIVE_FAILURES) {
                int64 cooldownMs = 30 * 1000; // 30 second cooldown after too many failures
                int64 timeSinceFailure = (int64(Time::Stamp) * 1000) - FetchInternal::g_LastFailureMs;
                if (timeSinceFailure < cooldownMs) {
                    if (S_EnableDebug) trace("[Moon] Cooldown after consecutive failures: " + tostring(cooldownMs - timeSinceFailure) + "ms");
                    sleep(int(cooldownMs - timeSinceFailure));
                }
            }

            Net::HttpRequest@ req = Net::HttpGet(url);
            while (!req.Finished()) yield();

            lastCode = req.ResponseCode();
            string body = req.String();

            if (lastCode == 200) {
                // Success - reset failure counter
                FetchInternal::g_ConsecutiveFailures = 0;
                outBody = body;
                return true;
            }

            // Track consecutive failures
            FetchInternal::g_ConsecutiveFailures++;
            FetchInternal::g_LastFailureMs = int64(Time::Stamp) * 1000;

            // Retry rate-limit, transient network and server-side failures.
            bool isRetryable = (lastCode == -1 || lastCode == 0 || lastCode == 429 || lastCode >= 500);

            if (!isRetryable && lastCode >= 400 && lastCode < 500) {
                // Client error - don't retry
                if (S_EnableDebug) trace("[Moon] Non-retryable HTTP " + lastCode);
                break;
            }

            // Network failures get steeper backoff because they often persist longer.
            int backoffMs;
            if (lastCode == -1 || lastCode == 0) {
                // Network error - use longer backoff
                backoffMs = FetchInternal::RETRY_SLEEP_MS * int(Math::Pow(3, consecutiveNetErrors));
                consecutiveNetErrors++;
            } else {
                // Server error or rate limit - standard exponential backoff
                backoffMs = FetchInternal::RETRY_SLEEP_MS * int(Math::Pow(FetchInternal::RETRY_BACKOFF_BASE, attempt));
            }

            // Cap with total retry time
            int64 elapsedMs = (int64(Time::Stamp) * 1000) - retryStartTime;
            if (elapsedMs + backoffMs > FetchInternal::MAX_TOTAL_RETRY_MS) {
                if (S_EnableDebug) trace("[Moon] Max retry time exceeded");
                break;
            }

            if (S_EnableDebug) {
                string status = (lastCode == -1 || lastCode == 0) ? "network error" : "HTTP " + tostring(lastCode);
                trace("[Moon] Retry " + tostring(attempt + 1) + " after " + status + " (backoff: " + tostring(backoffMs) + "ms)");
            }

            sleep(backoffMs);
            attempt++;
        }

        outBody = "";
        return false;
    }

    string FetchResponseWithRetries(const string &in url, int &out outCode) {
        // Raw body cache avoids repeated JSON downloads for identical URLs.
        string cachedBody;
        if (GetCachedResponse(url, cachedBody)) {
            outCode = 200;
            return cachedBody;
        }

        // Perform fetch with automatic retries
        string body;
        if (FetchWithAutoRetry(url, body)) {
            SetCachedResponse(url, body);
            outCode = 200;
            return body;
        }

        outCode = -1; // Indicate failure
        return "";
    }

    // --- Main Coroutine ---

    void FetchCoroutine(ref@ args_ref) {
        dictionary@ args = cast<dictionary>(args_ref);
        string url;
        bool isInitialFetch = false;
        uint requestID = 0;

        if (!UnpackFetchArgs(args, url, isInitialFetch, requestID)) {
            error("[Moon] Invalid args for FetchCoroutine");
            return;
        }

        _ClearPendingStart(url);
        if (!isInitialFetch) g_IsLoading = true;

        // Fast path: if parsed data is already cached, update the UI immediately.
        array<EventItem@>@ cachedParsed = null;
        bool isFreshCache = GetCachedParsedEvents(url, cachedParsed, true);

        if (cachedParsed !is null && cachedParsed.Length > 0) {
            if (S_EnableDebug) {
                string cacheType = isFreshCache ? "fresh" : "stale";
                trace("[Moon] " + cacheType + " cache hit: " + url + " (" + cachedParsed.Length + " events)");
            }

            if (requestID != FetchInternal::g_FetchRequestID) {
                _FinishFetchState(isInitialFetch);
                return;
            }

            UpdateEventsAndCache(cachedParsed, false);
            _FinishFetchState(isInitialFetch);

            if (isInitialFetch) HandleInitialFetchSuccess();
            else HandleCalendarFetchSuccess();

            // If cache is stale, schedule background refresh
            if (!isFreshCache && !g_PendingStarts.Exists(url)) {
                sleep(1000);
                StartFetchCoroutine(url, isInitialFetch);
            }
            return;
        }

        // Coalesce concurrent requests for the same URL so only one network call is ever active.
        if (g_InFlightRequests.Exists(url)) {
            array<uint>@ waitList = cast<array<uint>@>(g_InFlightRequests[url]);
            if (waitList is null) {
                g_InFlightRequests[url] = array<uint>();
            }
            cast<array<uint>@>(g_InFlightRequests[url]).InsertLast(requestID);
            if (S_EnableDebug) trace("[Moon] Joined in-flight: " + url);
            return;
        }

        if (S_EnableDebug) trace("[Moon] Network fetch: " + url);
        g_InFlightRequests[url] = array<uint>();
        cast<array<uint>@>(g_InFlightRequests[url]).InsertLast(requestID);

        int httpCode = -1;
        string body = FetchResponseWithRetries(url, httpCode);

        // Ignore obsolete responses, but always release request state first.
        if (requestID != FetchInternal::g_FetchRequestID) {
            _CleanupRequestState(url);
            _FinishFetchState(isInitialFetch);
            return;
        }
        _FinishFetchState(isInitialFetch);

        // Errors fall back to stale cache so calendar navigation stays usable offline.
        if (httpCode != 200) {
            _HandleFetchFailure(url, httpCode, isInitialFetch);
            return;
        }

        // Parse and cache
        Json::Value@ root;
        try { @root = Json::Parse(body); } catch {
            string preview = body.Length > 200 ? body.SubStr(0, 200) + "..." : body;
            error(Moon::kLogTag + " JSON parse error: " + preview);
            _NotifyWaiters(url);
            _CleanupRequestState(url);
            if (S_EnableNotifications) {
                UI::ShowNotification("Moon Calendar Error", "Invalid server data", vec4(1, 0, 0, 1), 6000);
            }
            return;
        }

        ProcessApiResponse(root, isInitialFetch);
        SetCachedParsedEvents(url, g_Events);
        _NotifyWaiters(url);
        _CleanupRequestState(url);
    }

    // --- Success Handling ---

    void _NotifyWaiters(const string &in url) {
        if (!g_InFlightRequests.Exists(url)) return;

        array<uint>@ waitList = cast<array<uint>@>(g_InFlightRequests[url]);
        if (waitList is null) { g_InFlightRequests.Delete(url); return; }

        for (uint i = 0; i < waitList.Length; i++) {
            uint waiterID = waitList[i];
            string key = tostring(waiterID);
            bool waiterInitial = g_FetchRequestIsInitial.Exists(key) ? bool(g_FetchRequestIsInitial[key]) : false;

            if (g_FetchHandlers.Exists(key)) {
                FetchSuccessHandler@ h = cast<FetchSuccessHandler>(g_FetchHandlers[key]);
                if (h !is null) {
                    try { h(@g_Events, waiterInitial); } catch { warn("[Moon] Waiter handler exception"); }
                }
                g_FetchHandlers.Delete(key);
            }
            g_FetchRequestIsInitial.Delete(key);
        }
        g_InFlightRequests.Delete(url);
    }

    // --- API Response Processing ---  

    // Parses raw JSON response into EventItem objects, skipping invalid entries and deduplicating by ID.
    void ParsePhaseData(Json::Value@ root, array<EventItem@>@ local_events) {
        if (root is null || !root.HasKey("phasedata") || root["phasedata"].GetType() != Json::Type::Array) return;

        Json::Value@ phaseDataArray = root["phasedata"];
        dictionary seenIds;

        for (uint i = 0; i < phaseDataArray.Length; i++) {
            auto@ row = phaseDataArray[i];
            if (!row.HasKey("phase") || !row.HasKey("year") || !row.HasKey("month") || !row.HasKey("day")) continue;

            string phase = string(row["phase"]);
            int Y = int(row["year"]), M = int(row["month"]), D = int(row["day"]);
            string timeStr = row.HasKey("time") ? string(row["time"]) : "00:00:00";
            int h = 0, m = 0, s = 0;
            if (!Helpers::ParseTimeString(timeStr, h, m, s)) {
                warn(Moon::kLogTag + " Unrecognized time: '" + timeStr + "'");
            }

            int64 epochSec = Helpers::StampFromUTC(Y, M, D, h, m, s);
            if (epochSec <= 0) continue;

            EventItem@ e = EventItem();
            e.id = Moon::PhaseAbbrev(phase) + "-" + tostring(epochSec);
            if (seenIds.Exists(e.id)) continue;
            seenIds[e.id] = true;

            e.title = Moon::PhaseDisplayTitle(phase);
            e.startMs = epochSec * 1000;
            local_events.InsertLast(e);
        }
    }

    void ProcessApiResponse(Json::Value@ root, bool isInitialFetch) {
        array<EventItem@> parsedEvents;
        ParsePhaseData(root, parsedEvents);

        if (parsedEvents.Length == 0) {
            warn("[Moon] No valid events in API response");
            if (S_EnableNotifications) {
                UI::ShowNotification("Moon Calendar", "No moon phases found", vec4(1, 1, 0, 1), 5000);
            }
            return;
        }
        UpdateEventsAndCache(parsedEvents);
        if (isInitialFetch) HandleInitialFetchSuccess();
        else HandleCalendarFetchSuccess();
    }

    // Replaces the visible event list, optionally persists it, then rebuilds the per-day lookup cache.
    void UpdateEventsAndCache(const array<EventItem@>@ local_events, bool persistToFile = true) {
        if (local_events is null) g_Events = array<EventItem@>();
        else g_Events = local_events;

        if (S_EnableDebug) {
            trace("[Moon] UpdateEventsAndCache: incoming=" + tostring(local_events is null ? 0 : local_events.Length));
            trace("[Moon] UpdateEventsAndCache: g_Events=" + tostring(g_Events.Length));
        }

        // Debug dump of first few events to verify parsing without needing to set breakpoints or inspect variables.
        if (S_EnableDebug && g_Events.Length > 0) {
            int limit = g_Events.Length < 5 ? int(g_Events.Length) : 5;
            for (int di = 0; di < limit; di++) {
                auto@ ev = g_Events[uint(di)];
                if (ev is null) { trace("[Moon] EventDump idx=" + tostring(di) + " <null>"); continue; }
                int Y, M, D, h, m, s;
                TimeUtils::UtcYMDHMSFromMs(ev.startMs, Y, M, D, h, m, s);
                string dt = tostring(Y) + "-" + TimeUtils::Two(M) + "-" + TimeUtils::Two(D) + " " +
                            TimeUtils::Two(h) + ":" + TimeUtils::Two(m) + ":" + TimeUtils::Two(s);
                trace("[Moon] EventDump idx=" + tostring(di) + " id=" + ev.id + " date=" + dt + " title=\"" + ev.title + "\"");
            }
        }

        // Update last fetched timestamp
        if (g_UIState.CalYear != 0 && g_UIState.CalMonth != 0) {
            g_LastFetchedYear = g_UIState.CalYear;
            g_LastFetchedMonth = g_UIState.CalMonth;
        }

        // Only fresh network results need to hit disk. Cache hits should stay memory-only.
        if (persistToFile && g_UIState.CalYear != 0 && g_UIState.CalMonth != 0 && g_Events.Length > 0) {
            try { SaveToFileCache(g_UIState.CalYear, g_UIState.CalMonth, g_Events); } catch {}
        }

        RebuildMonthEventCache();
    }

    void HandleInitialFetchSuccess() {
        if (S_EnableDebug) trace("[Moon] Initial fetch: " + g_Events.Length + " events");
        if (!g_InitialNotificationsShown) {
            Notifications::ShowStartupNotifications();
            g_InitialNotificationsShown = true;
        }
    }

    void HandleCalendarFetchSuccess() {
        g_LastFetchedYear = g_UIState.CalYear;
        g_LastFetchedMonth = g_UIState.CalMonth;
        if (S_EnableDebug) trace("[Moon] Calendar fetch: " + g_UIState.CalYear + "-" + g_UIState.CalMonth + " (" + g_Events.Length + " events)");
    }
}
