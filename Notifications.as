dictionary@ g_ShownNotificationIDs = dictionary(); 

void ShowSingleNotification(EventItem@ e, int64 nowMs) {
    if (e is null) return;

    int64 deltaMs = e.startMs - nowMs;
    string when = FriendlyDeltaLong(deltaMs);
    string whenUtc = Time::FormatStringUTC("%Y-%m-%d %H:%M UTC", e.startMs / 1000);
    
    string title = "[MOON] " + e.title;
    string status;
    if (deltaMs >= 0) {
        status = "Starts in " + when;
    } else {
        status = "Started " + FriendlyDeltaLong(-deltaMs) + " ago";
    }

    UI::ShowNotification(title, status + "\n" + whenUtc, PhaseColorForTitleLower(e.title), S_NotificationDurationSec * 1000);
    trace("[Moon] Showing notification for '" + e.title + "' (deltaMs=" + deltaMs + ")");
    
    PlayMoonSound(GetPhaseKind(e.title));
}

void Event_ShowStartupNotifications() {
    if (g_Events.IsEmpty()) return;

    trace("[Moon] Showing startup notifications... (events=" + g_Events.Length + ")");
    int64 nowMs = int64(Time::Stamp) * 1000;
    int notificationsShown = 0;

    int currentY, currentM, currentD;
    ::UtcYMDFromMs(nowMs, currentY, currentM, currentD);

    for (uint i = 0; i < g_Events.Length; i++) {
        auto@ e = g_Events[i];
        if (e is null) continue;

        int eventY, eventM, eventD;
        ::UtcYMDFromMs(e.startMs, eventY, eventM, eventD);
        bool isToday = (eventY == currentY && eventM == currentM && eventD == currentD);
        
        if (isToday || e.startMs > nowMs) {
            if (notificationsShown < S_MaxImmediateNotifications) {
                ShowSingleNotification(e, nowMs);
                g_ShownNotificationIDs[e.id] = nowMs; 
                notificationsShown++;
            } else {
                break; 
            }
        }
    }
}

void CleanupShownNotifications(int64 nowMs) {
    array<string> keysToRemove;
    array<string> keys = g_ShownNotificationIDs.GetKeys();

    for (uint i = 0; i < keys.Length; i++) {
        string eventId = keys[i];
        int64 shownAtMs = int64(g_ShownNotificationIDs[eventId]);
        
        if (shownAtMs < nowMs - kOneHourMs) {
            keysToRemove.InsertLast(eventId);
        }
    }

    for (uint i = 0; i < keysToRemove.Length; i++) {
        g_ShownNotificationIDs.Delete(keysToRemove[i]);
    }
}

void ShowPendingNotifications(int64 nowMs) {
    int64 notificationWindowMs = int64(S_NotifyMinutesBefore) * kOneMinuteMs;

    for (uint i = 0; i < g_Events.Length; i++) {
        auto@ e = g_Events[i];
        if (e is null) continue;

        if (g_ShownNotificationIDs.Exists(e.id)) {
            continue;
        }

        int64 deltaMs = e.startMs - nowMs;

        if (deltaMs >= 0 && deltaMs <= notificationWindowMs) {
            trace("[Moon] Showing timed notification for: " + e.title);
            ShowSingleNotification(e, nowMs);
            g_ShownNotificationIDs[e.id] = nowMs;
        }
    }
}

void ProcessAndShowNotifications() {
    if (g_Events.IsEmpty() || S_NotifyMinutesBefore <= 0) return;

    int64 nowMs = int64(Time::Stamp) * 1000;

    CleanupShownNotifications(nowMs);
    
    ShowPendingNotifications(nowMs);
}
