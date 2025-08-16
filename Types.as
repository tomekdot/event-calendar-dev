enum PhaseKind { PK_NM, PK_FQ, PK_FM, PK_LQ, PK_INT, PK_UNKNOWN }

class EventItem {
    string id;
    string title;
    int64 startMs;
}

class UIState {
    int CalYear = 0;
    int CalMonth = 0;
    int SelectedDay = 0;
    bool ShowCalendarWindow = true;
}
