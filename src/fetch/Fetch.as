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
    dictionary@ g_LastStartTs = dictionary();           // url -> timestamp

    // --- File Cache State ---
    string g_LastFileCacheMonth = "";          // Track which month is in file cache

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

    // Save events to file cache
    void SaveToFileCache(int year, int month, const array<EventItem@>@ events) {
        string filepath = GetCacheFilePath(year, month);
        
        // Build JSON array
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
        
        // Add metadata
        Json::Value meta = Json::Object();
        meta["year"] = year;
        meta["month"] = month;
        meta["cachedAt"] = int64(Time::Stamp) * 1000;
        // Also save as string to ensure precision in all parsers
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
        
        g_LastFileCacheMonth = tostring(year) + "-" + tostring(month);
        if (S_EnableDebug) trace("[Moon] Saved " + tostring(events.Length) + " events to file cache: " + filepath);
    }

    // Load events from file cache, returns true if loaded successfully
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
        
        // Read and parse JSON
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
        
        // Check file age from cachedAt metadata
        int64 cachedAtMs = 0;
        if (root.HasKey("cachedAtStr")) {
             // Prefer string version if available (new format)
             cachedAtMs = Text::ParseInt64(string(root["cachedAtStr"]));
        } else if (root.HasKey("cachedAt")) {
             auto@ val = root["cachedAt"];
             if (val.GetType() == Json::Type::String) {
                 cachedAtMs = Text::ParseInt64(string(val));
             } else {
                 // Handle numbers (int/double) - convert via double to preserve 64-bit precision
                 // avoiding 32-bit truncation from direct int casts in some environments
                 cachedAtMs = int64(double(val));
             }
        }
        
        // If cachedAt is 0 or very old (before 2020), treat as expired
        // Also handle case where timestamp is in the future (up to 1 week ahead)
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
        
        g_LastFileCacheMonth = tostring(year) + "-" + tostring(month);
        if (S_EnableDebug) trace("[Moon] Loaded " + tostring(events.Length) + " events from file cache");
        return events.Length > 0;
    }

    // Try to get events from any available cache (memory first, then file)
    bool GetEventsFromAnyCache(int year, int month, array<EventItem@>@ &out events, bool &out isFresh) {
        isFresh = false;
        string url = BuildApiUrl(year, month, 1);
        
        // Try memory cache first
        array<EventItem@>@ memCache = null;
        if (GetCachedParsedEvents(url, memCache, true)) {
            if (memCache !is null && memCache.Length > 0) {
                events = memCache;
                isFresh = true;
                return true;
            }
        }
        
        // Try stale memory cache
        if (GetCachedParsedEvents(url, memCache, true)) {
            if (memCache !is null && memCache.Length > 0) {
                events = memCache;
                return true;
            }
        }
        
        // Try file cache
        if (LoadFromFileCache(year, month, events)) {
            return true;
        }
        
        return false;
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

    // Gets parsed events from cache. Returns true if fresh cache found.
    // If useStale is true, also returns expired cache as fallback.
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

        // Create a copy of the cached events (fix null pointer access)
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

    // --- Debounce Helper ---

    // Returns true if the fetch should be skipped due to debouncing.
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
        g_LastStartTs[url] = nowMs;
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
        string url = BuildApiUrl(g_UIState.CalYear, g_UIState.CalMonth, 1);

        // Try cache first - use stale cache as fallback
        array<EventItem@>@ cached = null;
        bool isFreshCache = GetCachedParsedEvents(url, cached, true);

        if (cached !is null && cached.Length > 0) {
            if (S_EnableDebug) {
                string cacheType = isFreshCache ? "fresh" : "stale";
                trace("[Moon] Using " + cacheType + " memory cache for: " + url);
            }
            UpdateEventsAndCache(cached);
            HandleCalendarFetchSuccess();

            // If cache is stale, refresh in background
            if (!isFreshCache) {
                StartFetchCoroutine(url, false);
            }
            return;
        }

        // Try file cache as fallback (only if UI state is initialized)
        bool fileCacheLoaded = false;
        if (g_UIState.CalYear != 0 && g_UIState.CalMonth != 0) {
            try {
                array<EventItem@> fileCacheEvents;
                if (LoadFromFileCache(g_UIState.CalYear, g_UIState.CalMonth, fileCacheEvents)) {
                    fileCacheLoaded = true;
                    if (S_EnableDebug) trace("[Moon] Using file cache for: " + tostring(g_UIState.CalMonth) + "/" + tostring(g_UIState.CalYear));
                    UpdateEventsAndCache(fileCacheEvents);
                    
                    // Do NOT poison the memory cache with file cache data if we suspect it might be partial/outdated
                    // especially since the file cache doesn't store the URL used to fetch it.
                    // But we DO want to use it for immediate display.
                    // SetCachedParsedEvents(url, fileCacheEvents); 
                    
                    HandleCalendarFetchSuccess();

                    // Try to refresh in background
                    StartFetchCoroutine(url, false);
                    return;
                }
            } catch {
                warn("[Moon] Error loading from file cache");
            }
        }

        // No valid cache - clear calendar and fetch from network
        g_Events.Resize(0);
        RebuildMonthEventCache();
        
        if (S_EnableMoon) {
            StartFetchCoroutine(url, false);
        } else {
            g_ApiError = "Network disabled.";
        }
    }

    // Forces a fetch even if cache exists (for manual refresh)
    void RefreshCalendarData() {
        // Clear consecutive failures to allow fresh retry
        FetchInternal::g_ConsecutiveFailures = 0;
        FetchInternal::g_LastFailureMs = 0;
        FetchForCalendarView();
    }

    // Background auto-retry for failed fetches (call periodically)
    void AutoRetryFailedFetches() {
        if (!FetchInternal::g_AutoRetryEnabled) return;
        if (!S_EnableMoon) return;

        int64 nowMs = int64(Time::Stamp) * 1000;
        if (nowMs - FetchInternal::g_LastAutoRetryMs < FetchInternal::AUTO_RETRY_INTERVAL_MS) return;
        FetchInternal::g_LastAutoRetryMs = nowMs;

        // Only retry if we have some failures but not too many
        if (FetchInternal::g_ConsecutiveFailures > 0 && FetchInternal::g_ConsecutiveFailures < FetchInternal::MAX_CONSECUTIVE_FAILURES) {
            if (g_UIState.CalYear != 0 && g_UIState.CalMonth != 0) {
                string url = BuildApiUrl(g_UIState.CalYear, g_UIState.CalMonth, 1);
                if (!g_PendingStarts.Exists(url) && !g_InFlightRequests.Exists(url)) {
                    if (S_EnableDebug) trace("[Moon] Auto-retry fetch for: " + url);
                    StartFetchCoroutine(url, false);
                }
            }
        }
    }

    // --- Fetch Network Layer ---

    // Performs HTTP request with automatic retries for connection issues.
    // Returns true on success, false on permanent failure.
    bool FetchWithAutoRetry(const string &in url, string &out outBody) {
        int lastCode = -1;
        int64 retryStartTime = int64(Time::Stamp) * 1000;
        int attempt = 0;
        int consecutiveNetErrors = 0;

        while (attempt <= FetchInternal::MAX_RETRY_ATTEMPTS) {
            // Check for consecutive failure cooldown
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

            // Determine if this is retryable
            bool isRetryable = (lastCode == -1 || lastCode == 0 || lastCode == 429 || lastCode >= 500);

            if (!isRetryable && lastCode >= 400 && lastCode < 500) {
                // Client error - don't retry
                if (S_EnableDebug) trace("[Moon] Non-retryable HTTP " + lastCode);
                break;
            }

            // Calculate backoff - more aggressive for network errors
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
        // Try cache first
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

        if (g_PendingStarts.Exists(url)) g_PendingStarts.Delete(url);
        if (!isInitialFetch) g_IsLoading = true;

        // L2 cache check - use stale cache as fallback
        array<EventItem@>@ cachedParsed = null;
        bool isFreshCache = GetCachedParsedEvents(url, cachedParsed, true);

        if (cachedParsed !is null && cachedParsed.Length > 0) {
            if (S_EnableDebug) {
                string cacheType = isFreshCache ? "fresh" : "stale";
                trace("[Moon] " + cacheType + " cache hit: " + url + " (" + cachedParsed.Length + " events)");
            }

            if (requestID != FetchInternal::g_FetchRequestID) return;

            UpdateEventsAndCache(cachedParsed);
            if (!isInitialFetch) g_IsLoading = false;

            if (isInitialFetch) HandleInitialFetchSuccess();
            else HandleCalendarFetchSuccess();

            // If cache is stale, schedule background refresh
            if (!isFreshCache && !g_PendingStarts.Exists(url)) {
                sleep(1000);
                StartFetchCoroutine(url, isInitialFetch);
            }
            return;
        }

        // Coalesce with in-flight requests
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

        // Staleness check
        if (requestID != FetchInternal::g_FetchRequestID) return;
        if (!isInitialFetch) g_IsLoading = false;

        // Handle errors - schedule automatic retry
        if (httpCode != 200) {
            if (S_EnableDebug) trace("[Moon] Fetch failed after retries: HTTP " + tostring(httpCode));

            // Set error message
            if (httpCode == -1) {
                g_ApiError = "Connection lost.";
            } else if (httpCode == 0) {
                g_ApiError = "Network unavailable.";
            } else {
                g_ApiError = "Server error (HTTP " + tostring(httpCode) + ").";
            }

            // Show less intrusive notification
            if (S_EnableNotifications) {
                UI::ShowNotification("Moon Calendar", g_ApiError, vec4(1, 0.5, 0, 1), 3000);
            }

            // Check if we have stale cache to use
            array<EventItem@>@ staleCache = null;
            bool isFresh = false;
            if (GetCachedParsedEvents(url, staleCache, true) && staleCache !is null && staleCache.Length > 0) {
                if (S_EnableDebug) trace("[Moon] Using stale memory cache after fetch failure");
                UpdateEventsAndCache(staleCache);
                if (!isInitialFetch) g_IsLoading = false;
                HandleCalendarFetchSuccess();
            } else {
                // Try file cache (only if UI state is initialized)
                if (g_UIState.CalYear != 0 && g_UIState.CalMonth != 0) {
                    try {
                        array<EventItem@> fileCacheEvents;
                        if (LoadFromFileCache(g_UIState.CalYear, g_UIState.CalMonth, fileCacheEvents, true)) {
                            if (S_EnableDebug) trace("[Moon] Using file cache after fetch failure");
                            UpdateEventsAndCache(fileCacheEvents);
                            if (!isInitialFetch) g_IsLoading = false;
                            HandleCalendarFetchSuccess();
                        }
                    } catch {
                        warn("[Moon] Error loading from file cache in FetchCoroutine");
                    }
                }
            }

            // Schedule automatic retry if not already pending
            if (!g_PendingStarts.Exists(url) && !g_InFlightRequests.Exists(url)) {
                if (S_EnableDebug) trace("[Moon] Scheduling automatic retry for: " + url);
                sleep(2000);
                StartFetchCoroutine(url, isInitialFetch);
            }
            return;
        }

        // Parse and cache
        Json::Value@ root;
        try { @root = Json::Parse(body); } catch {
            string preview = body.Length > 200 ? body.SubStr(0, 200) + "..." : body;
            error(Moon::kLogTag + " JSON parse error: " + preview);
            if (S_EnableNotifications) {
                UI::ShowNotification("Moon Calendar Error", "Invalid server data", vec4(1, 0, 0, 1), 6000);
            }
            return;
        }

        ProcessApiResponse(root, isInitialFetch);
        SetCachedParsedEvents(url, g_Events);
        _NotifyWaiters(url);
    }

    // --- Success Handling ---

    void _HandleFetchSuccess(const array<EventItem@>@ events, bool isInitial, uint requestID) {
        UpdateEventsAndCache(events);
        if (!isInitial) g_IsLoading = false;

        if (isInitial) HandleInitialFetchSuccess();
        else HandleCalendarFetchSuccess();

        string key = tostring(requestID);
        if (g_FetchHandlers.Exists(key)) {
            FetchSuccessHandler@ handler = cast<FetchSuccessHandler>(g_FetchHandlers[key]);
            if (handler !is null) {
                try { handler(@g_Events, isInitial); } catch { warn("[Moon] Handler exception"); }
            }
            g_FetchHandlers.Delete(key);
        }
    }

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

    // Updates calendar events and rebuilds month cache
    void UpdateEventsAndCache(const array<EventItem@>@ local_events) {
        if (local_events is null) g_Events = array<EventItem@>();
        else g_Events = local_events;

        if (S_EnableDebug) {
            trace("[Moon] UpdateEventsAndCache: incoming=" + tostring(local_events is null ? 0 : local_events.Length));
            trace("[Moon] UpdateEventsAndCache: g_Events=" + tostring(g_Events.Length));
        }

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

        // Save to file cache for persistence across restarts
        if (g_UIState.CalYear != 0 && g_UIState.CalMonth != 0 && g_Events.Length > 0) {
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
