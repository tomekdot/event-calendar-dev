void Main() {
 
    Helpers::SetDebugEnabled(S_EnableDebug);
    if (g_UIState.CalYear == 0) {
        Time::Info tm = Time::Parse(Time::Stamp);
        g_UIState.CalYear = tm.Year;
        g_UIState.CalMonth = tm.Month;
        g_UIState.SelectedDay = tm.Day;
    }
    g_UIState.ShowCalendarWindow = S_ShowCalendarOnStart;
    PreloadSounds();
    FetchLatestData();
    startnew(PollingCoroutine);
    startnew(NotificationMonitorCoroutine);
}

void PollingCoroutine() {
    while (true) {
        sleep(Math::Max(30, S_PollIntervalSec) * 1000);
        FetchLatestData();
    }
}

void NotificationMonitorCoroutine() {
    while (true) {
        if (!g_InitialNotificationsShown) sleep(5000);
        ProcessAndShowNotifications();
        sleep(kOneMinuteMs);
    }
}
