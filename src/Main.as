/*
 * Initializes the plugin's state at startup.
 * This function sets the initial date for the calendar to the current system date,
 * configures the debug mode based on settings, and restores the visibility state
 * of the main calendar window.
 */
void InitializePluginState() {
    // Synchronize the debug flag in the Helpers namespace with the plugin's settings.
    Helpers::SetDebugEnabled(S_EnableDebug);

    // If the calendar date has not been initialized yet (e.g., on first launch),
    // set it to the current system date.
    if (g_UIState.CalYear == 0) {
        Time::Info tm = Time::Parse(Time::Stamp);
        g_UIState.CalYear = tm.Year;
        g_UIState.CalMonth = tm.Month;
        g_UIState.SelectedDay = tm.Day;
        g_UIState.LastDateChangeMs = Time::Now;
    }

    // Restore the calendar window's visibility from the saved user setting.
    g_UIState.ShowCalendarWindow = S_ShowCalendarOnStart;
}

/*
 * The main entry point for the plugin, called once upon loading.
 * It orchestrates the entire startup sequence: initializing state, preloading assets,
 * performing the initial data fetch, and launching background coroutines for
 * periodic polling and notification monitoring.
 */
void Main() {
    InitializePluginState();
    PreloadSounds();
    Fetch::FetchLatestData();
    
    // Start the long-running background tasks.
    startnew(PollingCoroutine);     
    startnew(NotificationMonitorCoroutine); 
    startnew(AutoRefreshCoroutine);
}

/*
 * A long-running coroutine that periodically fetches the latest moon phase data.
 * This ensures that the event data stays up-to-date without requiring a manual refresh
 * or plugin reload. The polling interval is configurable.
 */
void PollingCoroutine() {
    while (true) {
        // Sleep for the configured interval. Enforce a minimum of 30 seconds to prevent API spam.
        int intervalSec = Math::Max(30, S_PollIntervalSec);
        sleep(intervalSec * 1000);
        
        // Fetch the latest data, which will update the global event list.
        if (S_EnableMoon) {
            Fetch::FetchLatestData();
        }
    }
}

/*
 * A long-running coroutine that monitors for pending notifications.
 * It checks periodically (e.g., every minute) if any events are within the
 * user-defined notification window and displays them if they haven't been shown already.
 */
void NotificationMonitorCoroutine() {
    while (true) {
        // On the first run, wait a few seconds to ensure the initial data fetch has completed
        // before trying to show any notifications.
        if (!g_InitialNotificationsShown) {
            sleep(5000); 
        }
        // After the initial notifications have been shown, this check will proceed without a delay.

        Notifications::ProcessAndShowNotifications();
        
        // Wait for one minute before the next check.
        sleep(kOneMinuteMs);
    }
}
/*
 * A coroutine that automatically retries fetching data if it seems stuck or missing.
 * If the user has navigated to a month that has no data and it's been more than 5 seconds
 * since the last navigation, this will trigger a refresh.
 */
void AutoRefreshCoroutine() {
    while (true) {
        // Call auto-retry for failed fetches (handles VPN/restart reconnections)
        Fetch::AutoRetryFailedFetches();

        // Only check if the window is open and we're not already loading.
        if (g_UIState.ShowCalendarWindow && !g_IsLoading && S_EnableMoon) {
            // If data for the currently viewed month is not what we last successfully fetched
            bool needsData = (g_UIState.CalYear != g_LastFetchedYear || g_UIState.CalMonth != g_LastFetchedMonth);
            
            // Check if we have any events - if empty, we may need to refresh
            bool hasEvents = !g_Events.IsEmpty();

            // If we need data or don't have events, and it's been more than 2 seconds since last change
            if ((needsData || !hasEvents) && (uint64(Time::Now) - g_UIState.LastDateChangeMs > 2000)) {
                if (S_EnableDebug) {
                    trace("[Moon] AutoRefreshCoroutine: Refreshing data for " + tostring(g_UIState.CalMonth) + "/" + tostring(g_UIState.CalYear));
                }
                Fetch::FetchForCalendarView();
            }
        }
        sleep(1000); // Check every second
    }
}