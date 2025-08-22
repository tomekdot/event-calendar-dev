void RenderMenu() {
    if (UI::BeginMenu(Icons::CalendarO + " " + "Event Calendar")) {

        if (UI::MenuItem(Icons::Cog +  " " + "Toggle Calendar", "", g_UIState.ShowCalendarWindow)) {
            g_UIState.ShowCalendarWindow = !g_UIState.ShowCalendarWindow;
            S_ShowCalendarOnStart = g_UIState.ShowCalendarWindow;
        }

        if (UI::MenuItem(Icons::Bug + " " + "Run Helpers Tests")) {
            if (S_EnableDebug) {
                startnew(RunHelpersTests);
            } else {
                UI::ShowNotification("Moon Tests", "Helpers tests are disabled. Enable them in the advanced settings.", vec4(0.9, 0.6, 0.1, 1), 5000);
            }
        }

        UI::Separator();

        if (UI::MenuItem(Icons::Heart + " " + "Support Project", "", g_UIState.ShowSupportWindow)) {
            g_UIState.ShowSupportWindow = !g_UIState.ShowSupportWindow;
        }

        UI::EndMenu();
    }
}

void RenderInterface() {
    if (g_UIState.ShowCalendarWindow) {
        RenderCalendarWindow();
    }

    if (g_UIState.ShowSupportWindow) {
        RenderSupportWindow();
    }

    if (S_MoonTestSound) {
        S_MoonTestSound = false;
        PlayTestSound();
    }
}

void RenderCalendarHeader() {
    bool dateChanged = false;

    if (UI::Button("<<")) { g_UIState.CalYear--; dateChanged = true; }
    UI::SameLine(0, 5);
    if (UI::Button("<")) {
        g_UIState.CalMonth--;
        if (g_UIState.CalMonth < 1) { g_UIState.CalMonth = 12; g_UIState.CalYear--; }
        dateChanged = true;
    }

    UI::SameLine(0, 15);
    UI::Text(UIHelpers::GetMonthName(g_UIState.CalMonth) + " " + tostring(g_UIState.CalYear));
    UI::SameLine(0, 15);

    if (UI::Button(">")) {
        g_UIState.CalMonth++;
        if (g_UIState.CalMonth > 12) { g_UIState.CalMonth = 1; g_UIState.CalYear++; }
        dateChanged = true;
    }
    UI::SameLine(0, 5);
    if (UI::Button(">>")) { g_UIState.CalYear++; dateChanged = true; }

    if (dateChanged) FetchForCalendarView();
}

void RenderCalendarGrid() {
    if (!UI::BeginTable("CalendarGrid", 7, UI::TableFlags::BordersInnerV)) return;

    const string[] days = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
    for(uint i = 0; i < days.Length; i++) { UI::TableSetupColumn(days[i]); }
    UI::TableHeadersRow();

    int daysInMonth = UIHelpers::GetDaysInMonth(g_UIState.CalYear, g_UIState.CalMonth);
    int firstDayOfWeek = UIHelpers::GetDayOfWeek(g_UIState.CalYear, g_UIState.CalMonth, 1);
    
    int dayCounter = 1;
    for (int row = 0; row < 6; row++) {
        if (dayCounter > daysInMonth) break;
        
        UI::TableNextRow();
        for (int col = 0; col < 7; col++) {
            UI::TableSetColumnIndex(col);

            bool isCellEmpty = (row == 0 && col < firstDayOfWeek) || (dayCounter > daysInMonth);
            if (isCellEmpty) {
                continue;
            }

            bool hasEvent = g_MonthEventCache.Exists(tostring(dayCounter));
            bool isSelected = (dayCounter == g_UIState.SelectedDay);
            
            bool pushedColor = false;
            if (isSelected) {
                UI::PushStyleColor(UI::Col::Button, vec4(0.26, 0.59, 0.98, 1.0));
                pushedColor = true;
            } else if (hasEvent) {
                EventItem@ evt = cast<EventItem@>(g_MonthEventCache[tostring(dayCounter)]);
                if (evt !is null) {
                    UI::PushStyleColor(UI::Col::Button, PhaseColorForTitleLower(evt.title));
                    pushedColor = true;
                }
            }
            
            if (UI::Button(tostring(dayCounter), vec2(-1, 25))) { 
                g_UIState.SelectedDay = dayCounter; 
            }
            
            if (pushedColor) {
                UI::PopStyleColor();
            }
            
            dayCounter++;
        }
    }
    UI::EndTable();
}

void RenderEventList() {
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

void RenderCalendarWindow() {
    UI::SetNextWindowSize(580, 450, UI::Cond::FirstUseEver);

    if (UI::Begin("Moon Phase Calendar", g_UIState.ShowCalendarWindow)) {

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

void RenderSupportWindow() {
    UI::SetNextWindowSize(350, 250, UI::Cond::FirstUseEver);
    if (UI::Begin(Icons::Heart + " Support Project", g_UIState.ShowSupportWindow)) {
        UI::Dummy(vec2(1, 6));
        UI::PushFontSize(20.0);
        UI::Text("Event Calendar");
        UI::PopFont();

        UI::PushFontSize(14.0);
        UI::Text("Moon phase tracking for Trackmania");
        UI::PopFont();

        UI::Dummy(vec2(1, 6));

        UI::PushFontSize(14.0);
        UI::TextWrapped("Event Calendar tracks moon phases, shows notifications and helps you plan in-game events. If you like this plugin, your feedback and contributions keep it maintained and improving.");
        UI::PopFont();
        UI::Dummy(vec2(1, 8));

        UI::TextDisabled("Author: " + "tomekdot");
        UI::TextDisabled("Team: " + "vitalism-creative");
        UI::Dummy(vec2(1, 8));

        UI::Text("How you can help:");
        UI::Indent(8);
        UI::Text(Icons::Bug + "  Report bugs & issues on GitHub");
        UI::Text(Icons::LightbulbO + "  Suggest features or improvements");
        UI::Text(Icons::Code + "  Contribute code or PRs");
        UI::Text(Icons::Users + "  Join the community on Discord");
        UI::Unindent(8);
        UI::Dummy(vec2(1, 8));

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
        if (UI::Button(Icons::Github + " View on GitHub", vec2(-1, 0))) {
            if (S_SupportGithubUrl.Length > 0) OpenBrowserURL(S_SupportGithubUrl);
            else UI::ShowNotification("Event Calendar", "No GitHub link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);

        UI::Dummy(vec2(1, 6));

        UI::PushStyleColor(UI::Col::Button, vec4(0.345, 0.396, 0.949, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.267, 0.318, 0.871, 1.0));
        if (UI::Button(Icons::DiscordAlt + " Join Discord", vec2(-1, 0))) {
            if (S_SupportDiscordUrl.Length > 0) OpenBrowserURL(S_SupportDiscordUrl);
            else UI::ShowNotification("Event Calendar", "No Discord link available!", vec4(0.5, 0.5, 0.8, 1.0), 3000);
        }
        UI::PopStyleColor(2);

        UI::Dummy(vec2(1, 10));
        UI::Separator();
        UI::Dummy(vec2(1, 6));
        UI::TextWrapped("Thanks for checking out Event Calendar — your support helps keep the plugin maintained and improved. Report issues or open a PR on GitHub to contribute.");

    }
    UI::End();
}
