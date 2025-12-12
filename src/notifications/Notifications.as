namespace Notifications {
    // A dictionary to keep track of notifications that have already been shown.
    // Key: Event ID (string), Value: Timestamp (int64) when it was shown.
    // This prevents duplicate notifications for the same event.
    dictionary@ g_ShownNotificationIDs = dictionary();

    /**
     * Displays a single, formatted UI notification for a given event.
     * Also plays the corresponding sound for the moon phase.
     *
     * @param e The event item to display a notification for.
     * @param nowMs The current time in milliseconds since the epoch, used for calculations.
     */
    void ShowSingleNotification(EventItem@ e, int64 nowMs) {
        if (e is null) return;

        // Calculate the time difference between now and the event.
        int64 deltaMs = e.startMs - nowMs;
        
        // Create human-readable time strings.
        int64 absDeltaMs = deltaMs < 0 ? -deltaMs : deltaMs;
        string friendlyTimeDelta = TimeUtils::FriendlyDeltaLong(absDeltaMs);
        string eventTimeUtc = Time::FormatStringUTC("%Y-%m-%d %H:%M UTC", e.startMs / 1000);

        // Build the status message based on whether the event is in the future or past.
        string status = deltaMs >= 0 
            ? "Starts in " + friendlyTimeDelta 
            : "Started " + friendlyTimeDelta + " ago";

        // Show the actual notification on the UI.
        if (S_EnableNotifications) {
            UI::ShowNotification(
                "[MOON] " + e.title, 
                status + "\n" + eventTimeUtc, 
                Moon::PhaseColorForTitleLower(e.title), 
                S_NotificationDurationSec * 1000
            );
        }

        // Play the sound associated with this moon phase.
        PlayMoonSound(Moon::GetPhaseKind(e.title));
    }

    /**
     * Shows initial notifications when the application starts.
     * This function iterates through the list of events and shows a notification
     * for any event occurring today or in the future, up to a configurable limit.
     */
    void ShowStartupNotifications() {
        if (g_Events.IsEmpty() || !S_EnableNotifications) {
            return;
        }

        if (S_EnableDebug) {
            trace(Moon::kLogTag + " Showing startup notifications for " + g_Events.Length + " events...");
        }
        
        int64 nowMs = int64(Time::Stamp) * 1000;
        int notificationsShown = 0;

        int currentY, currentM, currentD;
        TimeUtils::UtcYMDFromMs(nowMs, currentY, currentM, currentD);

        for (uint i = 0; i < g_Events.Length; i++) {
            auto@ e = g_Events[i];
            if (e is null) {
                continue;
            }

            int eventY, eventM, eventD;
            TimeUtils::UtcYMDFromMs(e.startMs, eventY, eventM, eventD);
            bool isToday = (eventY == currentY && eventM == currentM && eventD == currentD);
            
            // Show notification if the event is today or in the future.
            if (isToday || e.startMs > nowMs) {
                if (notificationsShown < S_MaxImmediateNotifications) {
                    ShowSingleNotification(e, nowMs);
                    g_ShownNotificationIDs[e.id] = nowMs; // Mark as shown
                    notificationsShown++;
                } else {
                    // Stop after reaching the maximum number of startup notifications.
                    break; 
                }
            }
        }
    }

    /**
     * Cleans up old entries from the notification history (g_ShownNotificationIDs).
     * This prevents the dictionary from growing indefinitely and ensures that notifications
     * for recurring events can be shown again after a long period.
     *
     * @param nowMs The current time in milliseconds. Notifications shown more than
     *              an hour before this time will be removed.
     */
    void CleanupShownNotifications(int64 nowMs) {
        array<string> keysToRemove;
        array<string> keys = g_ShownNotificationIDs.GetKeys();
        const int64 ONE_HOUR_MS = 3600 * 1000;

        // First, collect all keys of entries older than one hour.
        for (uint i = 0; i < keys.Length; i++) {
            string eventId = keys[i];
            int64 shownAtMs = int64(g_ShownNotificationIDs[eventId]);
            
            if (shownAtMs < nowMs - ONE_HOUR_MS) {
                keysToRemove.InsertLast(eventId);
            }
        }

        // Then, remove them. This avoids modifying the dictionary while iterating over it.
        for (uint i = 0; i < keysToRemove.Length; i++) {
            g_ShownNotificationIDs.Delete(keysToRemove[i]);
        }
    }

    /**
     * Checks for and displays notifications for events that are about to occur.
     * An event triggers a notification if it's within the user-defined time window
     * (e.g., within 15 minutes of its start time) and hasn't been shown recently.
     *
     * @param nowMs The current time in milliseconds.
     */
    void ShowPendingNotifications(int64 nowMs) {
        const int64 ONE_MINUTE_MS = 60 * 1000;
        int64 notificationWindowMs = int64(S_NotifyMinutesBefore) * ONE_MINUTE_MS;

        for (uint i = 0; i < g_Events.Length; i++) {
            auto@ e = g_Events[i];
            if (e is null) {
                continue;
            }

            // Skip if a notification for this event has already been shown.
            if (g_ShownNotificationIDs.Exists(e.id)) {
                continue;
            }
        
            int64 deltaMs = e.startMs - nowMs;

            // Check if the event is in the future AND within the notification window.
            if (deltaMs >= 0 && deltaMs <= notificationWindowMs) {
                trace("[Moon] Showing timed notification for: " + e.title);
                ShowSingleNotification(e, nowMs);
                g_ShownNotificationIDs[e.id] = nowMs; // Mark as shown
            }
        }
    }

    /**
     * The main notification processing function, intended to be called periodically (e.g., every minute).
     * It orchestrates the cleanup of old notification history and the display of new, pending notifications.
     */
    void ProcessAndShowNotifications() {
        // Exit early if there are no events to check or if notifications are disabled.
        if (g_Events.IsEmpty() || S_NotifyMinutesBefore <= 0 || !S_EnableNotifications) {
            return;
        }

        int64 nowMs = int64(Time::Stamp) * 1000;

        // First, clean up the history of shown notifications.
        CleanupShownNotifications(nowMs);
        
        // Then, check for and show any new notifications that are due.
        ShowPendingNotifications(nowMs);
    }
}