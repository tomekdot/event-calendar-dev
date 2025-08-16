void RenderMenu() {
    
    if (UI::BeginMenu(Icons::CalendarO + " " + "Moon Calendar")) {
        if (UI::MenuItem(Icons::Cog + "Toggle Calendar", "", g_UIState.ShowCalendarWindow)) {
            g_UIState.ShowCalendarWindow = !g_UIState.ShowCalendarWindow;
            S_ShowCalendarOnStart = g_UIState.ShowCalendarWindow;
        }
        if (UI::MenuItem(Icons::Bug + "Run Helpers Tests")) {
            if (S_EnableDebug) {
                startnew(RunHelpersTests);
            } else {
                UI::ShowNotification("Moon Tests", "Helpers tests are disabled. Set S_EnableDebug = true to run them.", vec4(0.9, 0.6, 0.1, 1), 5000);
            }
        }
        UI::EndMenu();
    }
}

void RenderInterface() {
    if(g_UIState.ShowCalendarWindow) RenderCalendarWindow();

    if (S_MoonTestSound) {
        S_MoonTestSound = false;
        PlayTestSound();
    }
}

void RenderCalendarWindow() {
    UI::SetNextWindowSize(580, 450, UI::Cond::FirstUseEver);
    if (UI::Begin("Moon Phase Calendar", g_UIState.ShowCalendarWindow)) {
        bool dateChanged = false;
        if (UI::Button("<<")) { g_UIState.CalYear--; dateChanged = true; } UI::SameLine(0, 5);
        if (UI::Button("<")) { g_UIState.CalMonth--; if (g_UIState.CalMonth < 1) { g_UIState.CalMonth = 12; g_UIState.CalYear--; } dateChanged = true; }
        UI::SameLine(0, 15);
        UI::Text(UIHelpers::GetMonthName(g_UIState.CalMonth) + " " + tostring(g_UIState.CalYear));
        UI::SameLine(0, 15);
        if (UI::Button(">")) { g_UIState.CalMonth++; if (g_UIState.CalMonth > 12) { g_UIState.CalMonth = 1; g_UIState.CalYear++; } dateChanged = true; }
        UI::SameLine(0, 5);
        if (UI::Button(">>")) { g_UIState.CalYear++; dateChanged = true; }
        UI::Separator();
        
        if (dateChanged) {
            FetchForCalendarView();
        }

        if (g_IsLoading) {
            UI::Text("Loading events...");
        } else {
            if (UI::BeginTable("CalendarGrid", 7, UI::TableFlags::BordersInnerV)) {
                const string[] days = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
                for(uint i = 0; i < days.Length; i++) { UI::TableSetupColumn(days[i]); }
                UI::TableHeadersRow();

                int daysInMonth = UIHelpers::GetDaysInMonth(g_UIState.CalYear, g_UIState.CalMonth);
                int firstDayOfWeek = UIHelpers::GetDayOfWeek(g_UIState.CalYear, g_UIState.CalMonth, 1);
                int dayCounter = 1;

                for (int i = 0; i < 6; i++) {
                    if (dayCounter > daysInMonth) break;
                    UI::TableNextRow();
                    for (int j = 0; j < 7; j++) {
                        UI::TableSetColumnIndex(j);
                        if (!((i == 0 && j < firstDayOfWeek) || dayCounter > daysInMonth)) {
                            bool hasEvent = UIHelpers::DayHasEvent(dayCounter);
                            bool isSelected = (dayCounter == g_UIState.SelectedDay);
                            bool pushedColor = false;
                            if (isSelected) {
                                UI::PushStyleColor(UI::Col::Button, vec4(0.26, 0.59, 0.98, 1.0));
                                pushedColor = true;
                            } else if (hasEvent) {
                                vec4 evtColor = vec4(0.3, 0.6, 0.3, 1.0);
                                for (uint ei = 0; ei < g_Events.Length; ei++) {
                                    auto@ ge = g_Events[ei];
                                    if (ge is null) continue;
                                    int Y, M, D;
                                    UtcYMDFromMs(ge.startMs, Y, M, D);
                                    if (Y == g_UIState.CalYear && M == g_UIState.CalMonth && D == dayCounter) {
                                        evtColor = PhaseColorForTitleLower(ge.title.ToLower());
                                        break;
                                    }
                                }
                                UI::PushStyleColor(UI::Col::Button, evtColor);
                                pushedColor = true;
                            }
                            if (UI::Button(tostring(dayCounter), vec2(-1, 25))) { g_UIState.SelectedDay = dayCounter; }
                            if (pushedColor) UI::PopStyleColor();
                            dayCounter++;
                        }
                    }
                }
                UI::EndTable();
            }
        }
        UI::Separator();

        UI::Text("Events for: " + g_UIState.CalYear + "-" + Two(g_UIState.CalMonth) + "-" + Two(g_UIState.SelectedDay));
        UI::BeginChild("EventList", vec2(0, -1), true);
        if (g_IsLoading) {
            UI::TextDisabled("Loading...");
        } else {
            bool foundEvent = false;
            for (uint i = 0; i < g_Events.Length; i++) {
                auto@ e = g_Events[i];
                if (e is null) continue;
                int Y, M, D, h, m, s;
                UtcYMDHMSFromMs(e.startMs, Y, M, D, h, m, s);
                if (Y == g_UIState.CalYear && M == g_UIState.CalMonth && D == g_UIState.SelectedDay) {
                    foundEvent = true;
                    UI::Text(Icons::Circle + " " + Two(h) + ":" + Two(m) + " - " + e.title);
                }
            }
            if (!foundEvent) {
                UI::TextDisabled("No events for this day.");
            }
        }
        UI::EndChild();
    }
    UI::End();
}
