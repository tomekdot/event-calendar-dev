/*
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

/*
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
            // Tests removed
        } else {
            if (S_EnableNotifications) UI::ShowNotification("Moon Tests", "Helpers tests are disabled. Enable them in the advanced settings.", vec4(0.9, 0.6, 0.1, 1), 5000);
        }
    }
}

/*
 * Renders the header of the calendar window, including month/year navigation buttons.
 */
void RenderCalendarHeader() {
    bool dateChanged = false;

    auto fp = UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
    float btnH = UI::GetTextLineHeight() + fp.y * 2.0f;

    // Use a table with 5 stretchable columns so each button reacts to window shrinking.
    // The center column (date display) is given more weight to prevent month name truncation.
    if (UI::BeginTable("CalendarHeaderTable", 5)) {
        UI::TableSetupColumn("PrevYear", UI::TableColumnFlags::WidthStretch, 0.10f);
        UI::TableSetupColumn("PrevMonth", UI::TableColumnFlags::WidthStretch, 0.10f);
        UI::TableSetupColumn("CenterDate", UI::TableColumnFlags::WidthStretch, 0.60f);
        UI::TableSetupColumn("NextMonth", UI::TableColumnFlags::WidthStretch, 0.10f);
        UI::TableSetupColumn("NextYear", UI::TableColumnFlags::WidthStretch, 0.10f);

        UI::TableNextRow();

        // 1. Year and Month backward
        UI::TableSetColumnIndex(0);
        if (UI::Button("<<", vec2(-1, btnH))) {
            g_UIState.CalYear--;
            dateChanged = true;
        }

        UI::TableSetColumnIndex(1);
        if (UI::Button("<", vec2(-1, btnH))) {
            g_UIState.CalMonth--;
            if (g_UIState.CalMonth < 1) {
                g_UIState.CalMonth = 12;
                g_UIState.CalYear--;
            }
            dateChanged = true;
        }

        // 2. Month Year display
        UI::TableSetColumnIndex(2);
        UI::BeginDisabled();
        UI::Button(UIHelpers::GetMonthName(g_UIState.CalMonth) + " " + tostring(g_UIState.CalYear), vec2(-1, btnH));
        UI::EndDisabled();

        // 3. Month and Year forward
        UI::TableSetColumnIndex(3);
        if (UI::Button(">", vec2(-1, btnH))) {
            g_UIState.CalMonth++;
            if (g_UIState.CalMonth > 12) {
                g_UIState.CalMonth = 1;
                g_UIState.CalYear++;
            }
            dateChanged = true;
        }

        // 4. Year forward
        UI::TableSetColumnIndex(4);
        if (UI::Button(">>", vec2(-1, btnH))) {
            g_UIState.CalYear++;
            dateChanged = true;
        }

        UI::EndTable();
    }

    if (dateChanged) {
        g_UIState.LastDateChangeMs = Time::Now;
        Fetch::FetchForCalendarView();
    }
}

/*
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

/*
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
                // Sort for display
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

/*
 * Renders a small footer at the bottom of the window for status information.
 */
void RenderCalendarFooter() {
    auto spacing = UI::GetStyleVarVec2(UI::StyleVar::ItemSpacing);
    UI::Separator();
    
    // Check if the current view matches actually fetched data
    bool isDataOutdated = (g_UIState.CalYear != g_LastFetchedYear || g_UIState.CalMonth != g_LastFetchedMonth);
    
    if (g_IsLoading) {
        UI::Text(Icons::Refresh + " Updating...");
    } else if (isDataOutdated) {
        UI::TextDisabled(Icons::ClockO + " Pending Sync...");
    } else {
        UI::TextDisabled(Icons::Check + " Up to date");
    }
}

/*
 * Renders the main calendar window, which contains the header, grid, and event list.
 */
void RenderCalendarWindow() {
    UI::SetNextWindowSize(580, 450, UI::Cond::FirstUseEver);

    // The 'if (UI::Begin(...))' pattern ensures that code is only run when the window is visible.
    if (UI::Begin("Moon Phase Calendar", g_UIState.ShowCalendarWindow)) {
        // Minimum window size lock (blokada) for vertical stability.
        // Horizontal shrinking is now handled by stretchable table columns.
        auto fp = UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
        auto spacing = UI::GetStyleVarVec2(UI::StyleVar::ItemSpacing);
        float footerHeight = UI::GetTextLineHeight() + fp.y * 2.0f + spacing.y;
        float minWindowW = 360.0f; 
        float minWindowH = 420.0f; 
        
        vec2 ws = UI::GetWindowSize();
        if (ws.x < minWindowW || ws.y < minWindowH) {
            UI::SetWindowSize(vec2(Math::Max(ws.x, minWindowW), Math::Max(ws.y, minWindowH)));
        }

        RenderCalendarHeader();
        UI::Separator();

        // Errors are handled automatically in background - just show the data
        if (g_IsLoading && g_Events.IsEmpty()) { 
            UI::Text("Loading events...");
        } else {
            RenderCalendarGrid();
            UI::Separator();
            
            // Render list but leave space for footer
            UI::Text("Events for: " + g_UIState.CalYear + "-" + TimeUtils::Two(g_UIState.CalMonth) + "-" + TimeUtils::Two(g_UIState.SelectedDay));
            UI::BeginChild("EventList", vec2(0, -footerHeight), true);
            
            bool foundEvent = false;
            string key = tostring(g_UIState.SelectedDay);
            if (g_MonthEventCache.Exists(key)) {
                array<EventItem@>@ dayList = cast<array<EventItem@>@>(g_MonthEventCache[key]);
                if (dayList !is null) {
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
            if (!foundEvent) UI::TextDisabled("No events for this day.");
            UI::EndChild();
            
            RenderCalendarFooter();
        }
    }
    UI::End();
}

/*
 * Renders the support window, which contains project information and donation/social links.
 */
void RenderAboutSupportWindow() {
    UI::SetNextWindowSize(420, 500, UI::Cond::FirstUseEver);
    if (UI::Begin(Icons::InfoCircle + " About & Support", S_ShowAboutSupport)) {
        auto fp = UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
        auto spacing = UI::GetStyleVarVec2(UI::StyleVar::ItemSpacing);
        auto winPad = UI::GetStyleVarVec2(UI::StyleVar::WindowPadding);
        float btnH = UI::GetTextLineHeight() + fp.y * 2.0f;
        float footerHeight = btnH + spacing.y;

        // --- WINDOW SIZE LOCK ---
        float minWindowW = 380.0f;
        float minWindowH = 450.0f;
        vec2 ws = UI::GetWindowSize();
        if (ws.x < minWindowW || ws.y < minWindowH) {
            UI::SetWindowSize(vec2(Math::Max(ws.x, minWindowW), Math::Max(ws.y, minWindowH)));
        }

        // --- HEADER ---
        UI::Dummy(vec2(1, 4));
        UI::PushFontSize(24.0);
        UI::Text(Icons::CalendarO + " Event Calendar");
        UI::PopFont();
        UI::Separator();

        // --- SCROLLABLE CONTENT ---
        UI::BeginChild("AboutContent", vec2(0, -(footerHeight + 4.0f)), false);
        
        UI::Dummy(vec2(1, 6));
        UI::PushFontSize(14.0);
        UI::TextWrapped("Event Calendar displays moon phases and helps plan in-game events. It can optionally notify you about upcoming phases and supports Pursuit Channel schedule parsing");
        UI::PopFont();

        UI::Dummy(vec2(1, 10));

        // --- INFORMATION SECTION ---
        UI::Text(Icons::User + " Information");
        UI::Separator();
        UI::Text("Author: tomekdot");
        UI::Text("Team: vitalism-creative");

        UI::Dummy(vec2(1, 10));

        // --- SUPPORT SECTION ---
        UI::Text(Icons::Heart + " Support Development");
        UI::Separator();
        UI::Dummy(vec2(1, 4));

        UI::PushStyleColor(UI::Col::Button, vec4(0.0, 0.439, 0.729, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.0, 0.357, 0.608, 1.0));
        if (UI::Button(Icons::Paypal + " Donate via PayPal", vec2(-1, 0))) {
            if (S_SupportDonateUrl.Length > 0) OpenBrowserURL(S_SupportDonateUrl);
            else UI::ShowNotification("Event Calendar", "No donation link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);

        UI::Dummy(vec2(1, 4));

        UI::PushStyleColor(UI::Col::Button, vec4(0.2, 0.2, 0.2, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.3, 0.3, 0.3, 1.0));
        if (UI::Button(Icons::Github + " Github Repository", vec2(-1, 0))) {
            if (S_SupportGithubUrl.Length > 0) OpenBrowserURL(S_SupportGithubUrl);
            else UI::ShowNotification("Event Calendar", "No GitHub link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);

        UI::Dummy(vec2(1, 4));

        UI::PushStyleColor(UI::Col::Button, vec4(0.345, 0.396, 0.949, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.267, 0.318, 0.871, 1.0));
        if (UI::Button(Icons::DiscordAlt + " Join Discord Community", vec2(-1, 0))) {
            if (S_SupportDiscordUrl.Length > 0) OpenBrowserURL(S_SupportDiscordUrl);
            else UI::ShowNotification("Event Calendar", "No Discord link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);
        
        UI::EndChild();

        // --- FOOTER ---
        UI::Separator();
        string version = "v1.1.0-dev";
        float versionW = UI::MeasureString(version).x;
        float availWidth = UI::GetContentRegionAvail().x;
        UI::SetCursorPosX(UI::GetCursorPos().x + availWidth - versionW);
        UI::TextDisabled(version);
    }
    UI::End();
}