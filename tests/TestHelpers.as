namespace TestHelpers {

    class TestResult {
        string name;
        bool passed;
        string message; 

        TestResult(const string &in n, bool p, const string &in m) {
            name = n; passed = p; message = m;
        }
    }

    array<TestResult@> g_Results;

    void _Trace(const string &in s) { trace("[TEST] " + s); }
    
    string _FmtExpAct(const string &in t, const string &in exp, const string &in act) {
        return t + ": expected='" + exp + "' actual='" + act + "'";
    }

    class TestContext {
        string name;
        bool failed = false;
        string failMsg = "";

        TestContext(const string &in n) { name = n; }

        void _Fail(const string &in msg) {
            if (!failed) {
                failed = true;
                failMsg = msg;
                _Trace(name + " FAILED: " + msg);
            } else {
                failMsg += " | " + msg;
            }
        }
        
        void AssertTrue(bool v, const string &in msg = "") {
			 if (!v) _Fail(msg.Length > 0 ? msg : "expected true");
		}

        void AssertFalse(bool v, const string &in msg = "") { 
			if (v) _Fail(msg.Length > 0 ? msg : "expected false");
		}

        void AssertNotNull(ref@ obj, const string &in msg = "") { 
			if (obj is null) _Fail(msg.Length > 0 ? msg : "expected non-null"); 
		}

        void AssertEqual(int expected, int actual, const string &in tag = "") {
            if (expected != actual) _Fail(_FmtExpAct(tag.Length > 0 ? tag : "int", tostring(expected), tostring(actual)));
        }

        void AssertEqual(int64 expected, int64 actual, const string &in tag = "") {
            if (expected != actual) _Fail(_FmtExpAct(tag.Length > 0 ? tag : "int64", tostring(expected), tostring(actual)));
        }

        void AssertEqual(bool expected, bool actual, const string &in tag = "") {
            if (expected != actual) _Fail(_FmtExpAct(tag.Length > 0 ? tag : "bool", tostring(expected), tostring(actual)));
        }

        void AssertEqual(const string &in expected, const string &in actual, const string &in tag = "") {
            if (expected != actual) _Fail(_FmtExpAct(tag.Length > 0 ? tag : "string", expected, actual));
        }

        void _FinishInternal() {
            g_Results.InsertLast(TestResult(name, !failed, failMsg));
            if (!failed) _Trace(name + " PASSED");
        }
    }

    void ClearResults() { g_Results.Resize(0); }

    bool Summary() {
        uint passed = 0;
        uint total = g_Results.Length;
        for (uint i = 0; i < total; i++) if (g_Results[i].passed) passed++;

        _Trace("Test summary: " + tostring(passed) + "/" + tostring(total) + " passed.");

        if (passed != total) {
            _Trace("--- FAILED TESTS ---");
            for (uint i = 0; i < total; i++) {
                auto@ r = g_Results[i];
                if (!r.passed) _Trace(" - " + r.name + ": " + r.message);
            }
            _Trace("--------------------");
        }
        return passed == total;
    }
    
    void RunTest(const string &in testName, TestFunc@ testFunc) {
        _Trace("Starting: " + testName);
        TestContext ctx(testName);
        testFunc(ctx); 
        ctx._FinishInternal();
    }
}

funcdef void TestFunc(TestHelpers::TestContext &inout);

void Test_StampFromUTC_Epoch(TestHelpers::TestContext &inout ctx) {
    int64 secs = Helpers::StampFromUTC(1970, 1, 1, 0, 0, 0);
    ctx.AssertEqual(int64(0), secs, "epoch seconds should be zero");
}

void Test_StampFromUTC_Roundtrip(TestHelpers::TestContext &inout ctx) {
    int64 secs = Helpers::StampFromUTC(2020, 2, 29, 12, 34, 56);
    int Y, M, D, h, m, s;
    UtcYMDHMSFromMs(secs * 1000, Y, M, D, h, m, s);
    ctx.AssertEqual(2020, Y, "year");
    ctx.AssertEqual(2, M, "month");
    ctx.AssertEqual(29, D, "day");
    ctx.AssertEqual(12, h, "hour");
    ctx.AssertEqual(34, m, "minute");
    ctx.AssertEqual(56, s, "second");
}

void Test_ParseTimeString_Basic(TestHelpers::TestContext &inout ctx) {
    int h, m, s;
    bool ok = Helpers::ParseTimeString("09:05", h, m, s);
    ctx.AssertTrue(ok, "parse should succeed");
    ctx.AssertEqual(9, h, "hour");
    ctx.AssertEqual(5, m, "minute");
    ctx.AssertEqual(0, s, "second default");
}

void Test_ParseTimeString_Suffixes(TestHelpers::TestContext &inout ctx) {
    int h, m, s;
    ctx.AssertTrue(Helpers::ParseTimeString("23:59 UTC", h, m, s), "UTC suffix");
    ctx.AssertEqual(23, h);
    ctx.AssertTrue(Helpers::ParseTimeString("00:00UTC", h, m, s), "no-space-utc");
    ctx.AssertEqual(0, h);
    ctx.AssertTrue(Helpers::ParseTimeString(" 7:8  ut ", h, m, s), "extra spaces and ut");
    ctx.AssertEqual(7, h);
}

void Test_ParseTimeString_Invalid(TestHelpers::TestContext &inout ctx) {
    int h, m, s;
    ctx.AssertFalse(Helpers::ParseTimeString("not-a-time", h, m, s), "invalid format");
    ctx.AssertFalse(Helpers::ParseTimeString("24:00", h, m, s), "out-of-range");
	ctx.AssertFalse(Helpers::ParseTimeString("12:60", h, m, s), "invalid minute");
}

void RunAllTests() {
    TestHelpers::ClearResults();

    TestHelpers::RunTest("StampFromUTC: Epoch", @Test_StampFromUTC_Epoch);
    TestHelpers::RunTest("StampFromUTC: Roundtrip Leap Year", @Test_StampFromUTC_Roundtrip);
    TestHelpers::RunTest("ParseTimeString: Basic", @Test_ParseTimeString_Basic);
    TestHelpers::RunTest("ParseTimeString: Suffix Handling", @Test_ParseTimeString_Suffixes);
    TestHelpers::RunTest("ParseTimeString: Invalid Inputs", @Test_ParseTimeString_Invalid);

    bool allPassed = TestHelpers::Summary();
    trace("[TESTRUN] All tests completed. Overall status: " + (allPassed ? "PASSED" : "FAILED"));
    
    if (allPassed) {
        UI::ShowNotification("Moon Tests", "All " + tostring(TestHelpers::g_Results.Length) + " tests passed.", vec4(0.2, 0.7, 0.2, 1), 5000);
    } else {
        UI::ShowNotification("Moon Tests", "Some tests failed! See log for details.", vec4(0.9, 0.2, 0.1, 1), 7000);
    }
}

void RunHelpersTests() {
    startnew(RunAllTests);
}