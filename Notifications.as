void Event_ShowStartupNotifications() {
    if (g_Events.IsEmpty()) return;
    trace("[Moon] Showing startup notifications... events=" + g_Events.Length);
    int64 nowMs = int64(Time::Stamp) * 1000;
    int notificationsShown = 0;

    int Y, M, D;
    ::UtcYMDFromMs(nowMs, Y, M, D);

    for (uint i = 0; i < g_Events.Length; i++) {
        auto@ e = g_Events[i];
        if (e is null) continue;
        
        int eY, eM, eD;
        ::UtcYMDFromMs(e.startMs, eY, eM, eD);
        bool isToday = (eY == Y && eM == M && eD == D);

        if (isToday || e.startMs > nowMs) {
            if (notificationsShown < S_MaxImmediateNotifications) {
                ShowSingleNotification(e);
                g_ShownNotificationIDs.InsertLast(e.id);
                notificationsShown++;
            } else {
                break;
            }
        }
    }
}

void ShowSingleNotification(EventItem@ e) {
    if (e is null) return;
    int64 nowMs = int64(Time::Stamp) * 1000;
    int64 deltaMs = e.startMs - nowMs;

    string when = FriendlyDeltaLong(deltaMs);
    string title = "[MOON] " + e.title;
    string whenUtc = Time::FormatStringUTC("%Y-%m-%d %H:%M UTC", e.startMs / 1000);
    string status = deltaMs >= 0 ? ("Starts in " + when) : ("Started " + FriendlyDeltaLong(-deltaMs) + " ago");

    UI::ShowNotification(title, status + "\n" + whenUtc, PhaseColorForTitleLower(e.title.ToLower()), S_NotificationDurationSec * 1000);
    trace("[Moon] Showing notification for " + e.title + " (deltaMs=" + deltaMs + ")");
    trace("[Moon] Sample states: generic=" + (g_moonSample is null ? "null" : "loaded") + ", phaseSounds=" + (S_MoonPhaseSounds ? "enabled" : "disabled"));
    PlayMoonSound(GetPhaseKind(e.title.ToLower()));
}

void ProcessAndShowNotifications() {
    if (g_Events.IsEmpty() || S_NotifyMinutesBefore <= 0) return;

    int64 nowMs = int64(Time::Stamp) * 1000;
    int64 notificationWindowMs = int64(S_NotifyMinutesBefore) * kOneMinuteMs;

    for (int i = g_ShownNotificationIDs.Length - 1; i >= 0; i--) {
        bool found = false;
        for (uint j = 0; j < g_Events.Length; j++) {
            if (g_Events[j].id == g_ShownNotificationIDs[i]) {
                found = true;
                if (g_Events[j].startMs < nowMs - kOneHourMs) {
                    g_ShownNotificationIDs.RemoveAt(i);
                }
                break;
            }
        }
        if (!found) { g_ShownNotificationIDs.RemoveAt(i); }
    }

    for (uint i = 0; i < g_Events.Length; i++) {
        auto@ e = g_Events[i];
        bool alreadyShown = false;
        for (uint j = 0; j < g_ShownNotificationIDs.Length; j++) {
            if (g_ShownNotificationIDs[j] == e.id) { alreadyShown = true; break; }
        }
        if (alreadyShown) continue;

        int64 deltaMs = e.startMs - nowMs;
        if (deltaMs >= 0 && deltaMs <= notificationWindowMs) {
            trace("[Moon] Showing timed notification for: " + e.title);
            ShowSingleNotification(e);
            g_ShownNotificationIDs.InsertLast(e.id);
        }
    }
}
