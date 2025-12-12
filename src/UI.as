/**
 * Renders the plugin's menu in the main application menu bar.
 * Provides options to toggle UI windows and run tests.
 */
void RenderMenu() {
    // Single top-level menu item that toggles the calendar window.
    if (UI::MenuItem(Icons::CalendarO + " " + "Event Calendar", "", g_UIState.ShowCalendarWindow)) {
        g_UIState.ShowCalendarWindow = !g_UIState.ShowCalendarWindow;
        S_ShowCalendarOnStart = g_UIState.ShowCalendarWindow;
    }
}

/**
 * Main rendering router, called every frame to draw the plugin's UI.
 * It decides which windows to render based on the current UI state.
 */
void RenderInterface() {
    if (g_UIState.ShowCalendarWindow) {
        RenderCalendarWindow();
    }

    // Combined About & Support window controlled via settings
    if (S_ShowAboutSupport) {
        RenderAboutSupportWindow();
    }

    // This acts as a one-shot trigger. When the setting is changed to true,
    // play the sound once and immediately reset the flag to false.
    if (S_MoonTestSound) {
        S_MoonTestSound = false;
        PlayTestSound();
    }

    // One-shot trigger for running helpers tests from settings
    if (S_RunHelpersTests) {
        S_RunHelpersTests = false;
        if (S_EnableDebug) {
            startnew(RunHelpersTests);
        } else {
            if (S_EnableNotifications) UI::ShowNotification("Moon Tests", "Helpers tests are disabled. Enable them in the advanced settings.", vec4(0.9, 0.6, 0.1, 1), 5000);
        }
    }
}

/**
 * Renders the header of the calendar window, including month/year navigation buttons.
 */
void RenderCalendarHeader() {
    bool dateChanged = false;

    auto fp = UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
    auto spacing = UI::GetStyleVarVec2(UI::StyleVar::ItemSpacing);
    float btnH = UI::GetTextLineHeight() + fp.y * 2.0f;
    // Make all nav buttons the same size for consistent look and scaling.
    vec2 btnNav = vec2(btnH * 1.75f, btnH);

    // Year backward
    if (UI::Button("<<", btnNav)) {
        g_UIState.CalYear--;
        dateChanged = true;
    }
    UI::SameLine(0, spacing.x);
    // Month backward
    if (UI::Button("<", btnNav)) {
        g_UIState.CalMonth--;
        if (g_UIState.CalMonth < 1) {
            g_UIState.CalMonth = 12;
            g_UIState.CalYear--;
        }
        dateChanged = true;
    }

    // Display current month and year
    UI::SameLine(0, spacing.x);
    UI::Text(UIHelpers::GetMonthName(g_UIState.CalMonth) + " " + tostring(g_UIState.CalYear));
    UI::SameLine(0, spacing.x);

    // Month forward
    if (UI::Button(">", btnNav)) {
        g_UIState.CalMonth++;
        if (g_UIState.CalMonth > 12) {
            g_UIState.CalMonth = 1;
            g_UIState.CalYear++;
        }
        dateChanged = true;
    }
    UI::SameLine(0, spacing.x);
    // Year forward
    if (UI::Button(">>", btnNav)) {
        g_UIState.CalYear++;
        dateChanged = true;
    }

    // If the date was changed, fetch new event data for the calendar view.
    if (dateChanged) {
        Fetch::FetchForCalendarView();
    }
}

/**
 * Renders the main grid of days for the currently selected month.
 */
void RenderCalendarGrid() {
    if (!UI::BeginTable("CalendarGrid", 7, UI::TableFlags::BordersInnerV)) return;

    auto fp = UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
    float btnH = UI::GetTextLineHeight() + fp.y * 2.0f;
    float dayBtnH = btnH;

    // Setup table headers with day names
    const string[] days = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
    for (uint i = 0; i < days.Length; i++) {
        UI::TableSetupColumn(days[i]);
    }
    UI::TableHeadersRow();

    int daysInMonth = UIHelpers::GetDaysInMonth(g_UIState.CalYear, g_UIState.CalMonth);
    int firstDayOfWeek = UIHelpers::GetDayOfWeek(g_UIState.CalYear, g_UIState.CalMonth, 1);
    
    int dayCounter = 1;
    for (int row = 0; row < 6; row++) {
        if (dayCounter > daysInMonth) break; // Stop if we've rendered all days
        
        UI::TableNextRow();
        for (int col = 0; col < 7; col++) {
            UI::TableSetColumnIndex(col);

            // Skip rendering for empty cells before the 1st day or after the last day.
            bool isCellEmpty = (row == 0 && col < firstDayOfWeek) || (dayCounter > daysInMonth);
            if (isCellEmpty) {
                continue;
            }

            string dayKey = tostring(dayCounter);
            bool hasEvent = g_MonthEventCache.Exists(dayKey);
            bool isSelected = (dayCounter == g_UIState.SelectedDay);
            
            bool colorWasPushed = false;
            if (isSelected) {
                // Highlight the selected day
                UI::PushStyleColor(UI::Col::Button, vec4(0.26, 0.59, 0.98, 1.0));
                colorWasPushed = true;
            } else if (hasEvent) {
                // Highlight days with events using the event's color
                array<EventItem@>@ dayList = cast<array<EventItem@>@>(g_MonthEventCache[dayKey]);
                if (dayList !is null && dayList.Length > 0) {
                    // Use the color of the first event; future: blend, badges, etc.
                    UI::PushStyleColor(UI::Col::Button, Moon::PhaseColorForTitleLower(dayList[0].title));
                    colorWasPushed = true;
                }
            }
            
            // Render the day button
            if (UI::Button(dayKey, vec2(-1, dayBtnH))) { 
                g_UIState.SelectedDay = dayCounter; 
            }
            
            // Pop the custom color only if it was pushed to maintain style stack integrity.
            if (colorWasPushed) {
                UI::PopStyleColor();
            }
            
            dayCounter++;
        }
    }
    UI::EndTable();
}

/**
 * Renders the list of events for the currently selected day.
 */
void RenderEventList() {
    UI::Text("Events for: " + g_UIState.CalYear + "-" + TimeUtils::Two(g_UIState.CalMonth) + "-" + TimeUtils::Two(g_UIState.SelectedDay));
    
    UI::BeginChild("EventList", vec2(0, -1), true);
    if (g_IsLoading) {
        UI::TextDisabled("Loading...");
    } else if (g_Events.IsEmpty()) {
        UI::TextDisabled("No events loaded.");
    } else {
        bool foundEvent = false;
        // Iterate through all events to find ones matching the selected day.
        string key = tostring(g_UIState.SelectedDay);
        if (g_MonthEventCache.Exists(key)) {
            array<EventItem@>@ dayList = cast<array<EventItem@>@>(g_MonthEventCache[key]);
            if (dayList !is null) {
                // sort for display
                Helpers::SortEventsByStart(dayList);
                for (uint i = 0; i < dayList.Length; i++) {
                    auto@ e = dayList[i];
                    if (e is null) continue;
                    int Y, M, D, h, m, s;
                    TimeUtils::UtcYMDHMSFromMs(e.startMs, Y, M, D, h, m, s);
                    string tag = e.source.Length > 0 ? ("[" + e.source + "] ") : "";
                    string dur = e.durationSec > 0 ? (" (" + tostring(e.durationSec/60) + "m)") : "";
                    UI::Text(Icons::Circle + " " + TimeUtils::Two(h) + ":" + TimeUtils::Two(m) + " - " + tag + e.title + dur);
                }
                foundEvent = dayList.Length > 0;
            }
        }
        
        if (!foundEvent) {
            UI::TextDisabled("No events for this day.");
        }
    }
    UI::EndChild();
}

/**
 * Renders the main calendar window, which contains the header, grid, and event list.
 */
void RenderCalendarWindow() {
    UI::SetNextWindowSize(580, 450, UI::Cond::FirstUseEver);

    // The 'if (UI::Begin(...))' pattern ensures that code is only run when the window is visible.
    if (UI::Begin("Moon Phase Calendar", g_UIState.ShowCalendarWindow)) {
        // Prevent shrinking the window too narrow for the header controls.
        auto fp = UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
        auto spacing = UI::GetStyleVarVec2(UI::StyleVar::ItemSpacing);
        auto winPad = UI::GetStyleVarVec2(UI::StyleVar::WindowPadding);
        float btnH = UI::GetTextLineHeight() + fp.y * 2.0f;
        vec2 btnNav = vec2(btnH * 1.75f, btnH);
        string monthYear = UIHelpers::GetMonthName(g_UIState.CalMonth) + " " + tostring(g_UIState.CalYear);
        float labelW = Draw::MeasureString(monthYear).x;
        float minContentW = btnNav.x * 4.0f + spacing.x * 4.0f + labelW;
        float minWindowW = minContentW + winPad.x * 2.0f + 8.0f;
        vec2 ws = UI::GetWindowSize();
        if (ws.x < minWindowW) {
            UI::SetWindowSize(vec2(minWindowW, ws.y));
        }

        RenderCalendarHeader();
        UI::Separator();

        if (g_IsLoading) {
            UI::Text("Loading events...");
        } else {
            RenderCalendarGrid();
            UI::Separator();
            RenderEventList();
        }
    }
    UI::End();
}

/**
 * Renders the support window, which contains project information and donation/social links.
 */
void RenderAboutSupportWindow() {
    UI::SetNextWindowSize(420, 300, UI::Cond::FirstUseEver);
    if (UI::Begin(Icons::InfoCircle + " About & Support", S_ShowAboutSupport)) {
        // Header
        UI::Dummy(vec2(1, 6));
        UI::PushFontSize(20.0);
        UI::Text("Event Calendar");
        UI::PopFont();

        UI::PushFontSize(13.0);
        UI::TextWrapped("Event Calendar displays moon phases and helps plan in-game events. It can optionally notify you about upcoming phases and supports Pursuit Channel schedule parsing");
        UI::PopFont();

        UI::Dummy(vec2(1, 8));
        // About section
        UI::Text("About");
        UI::Separator();
        UI::Text("Author: tomekdot");
        UI::Text("Team: vitalism-creative");
        UI::Text("Version: dev");

        UI::Dummy(vec2(1, 8));

        // Support section (stacked buttons)
        UI::Text("Support");
        UI::Separator();

        UI::PushStyleColor(UI::Col::Button, vec4(0.0, 0.439, 0.729, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.0, 0.357, 0.608, 1.0));
        if (UI::Button(Icons::Paypal + " Donate", vec2(-1, 0))) {
            if (S_SupportDonateUrl.Length > 0) OpenBrowserURL(S_SupportDonateUrl);
            else UI::ShowNotification("Event Calendar", "No donation link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);

        UI::Dummy(vec2(1, 6));

        UI::PushStyleColor(UI::Col::Button, vec4(0.2, 0.2, 0.2, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.3, 0.3, 0.3, 1.0));
        if (UI::Button(Icons::Github + " GitHub", vec2(-1, 0))) {
            if (S_SupportGithubUrl.Length > 0) OpenBrowserURL(S_SupportGithubUrl);
            else UI::ShowNotification("Event Calendar", "No GitHub link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);

        UI::Dummy(vec2(1, 6));

        UI::PushStyleColor(UI::Col::Button, vec4(0.345, 0.396, 0.949, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.267, 0.318, 0.871, 1.0));
        if (UI::Button(Icons::DiscordAlt + " Discord", vec2(-1, 0))) {
            if (S_SupportDiscordUrl.Length > 0) OpenBrowserURL(S_SupportDiscordUrl);
            else UI::ShowNotification("Event Calendar", "No Discord link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);
    }
    UI::End();
}