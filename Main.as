void InitializePluginState() {
    Helpers::SetDebugEnabled(S_EnableDebug);

    if (g_UIState.CalYear == 0) {
        Time::Info tm = Time::Parse(Time::Stamp);
        g_UIState.CalYear = tm.Year;
        g_UIState.CalMonth = tm.Month;
        g_UIState.SelectedDay = tm.Day;
    }

    g_UIState.ShowCalendarWindow = S_ShowCalendarOnStart;
}

void Main() {
    InitializePluginState();

    PreloadSounds();
    FetchLatestData();
    startnew(PollingCoroutine);     
    startnew(NotificationMonitorCoroutine); 
}

void PollingCoroutine() {
    trace("[Moon] Polling coroutine started.");
    while (true) {
        int waitSeconds = Math::Max(30, S_PollIntervalSec);
        sleep(waitSeconds * 1000);

        trace("[Moon] Polling for latest data...");
        FetchLatestData();
    }
}

void NotificationMonitorCoroutine() {
    trace("[Moon] Notification monitor coroutine started.");
    while (true) {

        if (!g_InitialNotificationsShown) {
            sleep(5000); 
        }

        ProcessAndShowNotifications();

        sleep(kOneMinuteMs);
    }
}
