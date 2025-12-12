/**
 * @namespace TestHelpers
 * A lightweight, self-contained unit testing framework. It provides a simple assertion
 * context and a runner to execute test cases and summarize the results.
 */
namespace TestHelpers {
    /**
     * @class TestResult
     * A simple data class to store the outcome of a single test case.
     */
    class TestResult {
        string name;    // The name of the test case.
        bool passed;    // True if the test passed, false otherwise.
        string message; // An error message if the test failed.

        TestResult(const string &in n, bool p, const string &in m) {
            name = n; passed = p; message = m;
        }
    }

    // A global array to store the results of all executed tests.
    array<TestResult@> g_Results;

    /** Internal helper to log messages with a standard test prefix. */
    void _Trace(const string &in s) { trace("[TEST] " + s); }
    
    /** Internal helper to format a standard "expected vs. actual" error message. */
    string _FmtExpAct(const string &in t, const string &in exp, const string &in act) {
        return t + ": expected='" + exp + "' actual='" + act + "'";
    }

    /**
     * @class TestContext
     * Provides the assertion interface and manages the state of a single running test.
     * An instance of this class is passed to each test function.
     */
    class TestContext {
        string name;
        bool failed = false;
        string failMsg = "";

        TestContext(const string &in n) { name = n; }

        /** Internal method to record a failure. Only the first failure's message is primary. */
        void _Fail(const string &in msg) {
            if (!failed) {
                failed = true;
                failMsg = msg;
                _Trace(name + " FAILED: " + msg);
            } else {
                // Append subsequent failure messages for more context.
                failMsg += " | " + msg;
            }
        }
        
        // --- Assertion Methods ---

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

        /** Finalizes the test, records the result in the global list, and prints the status. */
        void _FinishInternal() {
            g_Results.InsertLast(TestResult(name, !failed, failMsg));
            if (!failed) {
                _Trace(name + " PASSED");
            }
        }
    }

    /** Clears all previous test results, preparing for a new test run. */
    void ClearResults() { g_Results.Resize(0); }

    /**
     * Prints a summary of the test run to the log and returns true if all tests passed.
     * If any tests failed, it lists them with their failure messages.
     */
    bool Summary() {
        uint passed = 0;
        uint total = g_Results.Length;
        for (uint i = 0; i < total; i++) {
            if (g_Results[i].passed) passed++;
        }

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
    
    /**
     * Executes a single test function within a new context.
     * @param testName The descriptive name of the test.
     * @param testFunc A handle to the function that contains the test logic.
     */
    void RunTest(const string &in testName, TestFunc@ testFunc) {
        _Trace("Starting: " + testName);
        TestContext ctx(testName);
        testFunc(ctx); 
        ctx._FinishInternal();
    }
}

/**
 * @funcdef TestFunc
 * Defines the required function signature for all test cases.
 * @param ctx An inout reference to the TestContext for making assertions.
 */
funcdef void TestFunc(TestHelpers::TestContext &inout);

// --- Test Case Implementations ---

/** Tests that the Unix epoch (1970-01-01) correctly evaluates to 0 seconds. */
void Test_StampFromUTC_Epoch(TestHelpers::TestContext &inout ctx) {
    int64 secs = Helpers::StampFromUTC(1970, 1, 1, 0, 0, 0);
    ctx.AssertEqual(int64(0), secs, "epoch seconds should be zero");
}

/** Tests if converting a timestamp to YMDHMS and back results in the original values. */
void Test_StampFromUTC_Roundtrip(TestHelpers::TestContext &inout ctx) {
    int64 secs = Helpers::StampFromUTC(2020, 2, 29, 12, 34, 56); // A leap year date
    int Y, M, D, h, m, s;
    TimeUtils::UtcYMDHMSFromMs(secs * 1000, Y, M, D, h, m, s);
    ctx.AssertEqual(2020, Y, "year");
    ctx.AssertEqual(2, M, "month");
    ctx.AssertEqual(29, D, "day");
    ctx.AssertEqual(12, h, "hour");
    ctx.AssertEqual(34, m, "minute");
    ctx.AssertEqual(56, s, "second");
}

/** Tests basic time string parsing without seconds. */
void Test_ParseTimeString_Basic(TestHelpers::TestContext &inout ctx) {
    int h, m, s;
    bool ok = Helpers::ParseTimeString("09:05", h, m, s);
    ctx.AssertTrue(ok, "parse should succeed");
    ctx.AssertEqual(9, h, "hour");
    ctx.AssertEqual(5, m, "minute");
    ctx.AssertEqual(0, s, "second should default to 0");
}

/** Tests that common suffixes like 'UTC' are handled correctly. */
void Test_ParseTimeString_Suffixes(TestHelpers::TestContext &inout ctx) {
    int h, m, s;
    ctx.AssertTrue(Helpers::ParseTimeString("23:59 UTC", h, m, s), "UTC suffix");
    ctx.AssertEqual(23, h);
    ctx.AssertTrue(Helpers::ParseTimeString("00:00UTC", h, m, s), "no-space-utc");
    ctx.AssertEqual(0, h);
    ctx.AssertTrue(Helpers::ParseTimeString(" 7:8  ut ", h, m, s), "extra spaces and 'ut'");
    ctx.AssertEqual(7, h);
}

/** Tests that invalid and out-of-range time strings fail to parse. */
void Test_ParseTimeString_Invalid(TestHelpers::TestContext &inout ctx) {
    int h, m, s;
    ctx.AssertFalse(Helpers::ParseTimeString("not-a-time", h, m, s), "invalid format");
    ctx.AssertFalse(Helpers::ParseTimeString("24:00", h, m, s), "out-of-range hour");
	ctx.AssertFalse(Helpers::ParseTimeString("12:60", h, m, s), "out-of-range minute");
}

/** Tests the basic functionality of appending query parameters to a URL. */
void Test_AppendQueryParam_Basic(TestHelpers::TestContext &inout ctx) {
    string url1 = "https://example.com/path";
    string res1 = Helpers::AppendQueryParam(url1, "foo", "1");
    ctx.AssertEqual("https://example.com/path?foo=1", res1, "append when no query exists");

    string url2 = "https://example.com/path?bar=2";
    string res2 = Helpers::AppendQueryParam(url2, "foo", "1");
    ctx.AssertEqual("https://example.com/path?bar=2&foo=1", res2, "append to an existing query");

    string url3 = "https://example.com/path?foo=9";
    string res3 = Helpers::AppendQueryParam(url3, "foo", "1");
    ctx.AssertEqual(url3, res3, "no-op when key already exists");
}

/** Tests edge cases for appending query parameters, like handling URL fragments. */
void Test_AppendQueryParam_EdgeCases(TestHelpers::TestContext &inout ctx) {
    string url1 = "https://example.com/path#anchor";
    string res1 = Helpers::AppendQueryParam(url1, "foo", "1");
    ctx.AssertEqual("https://example.com/path?foo=1#anchor", res1, "should preserve fragment");

    string url2 = "https://example.com/path?foo=9#x";
    string res2 = Helpers::AppendQueryParam(url2, "foo", "1");
    ctx.AssertEqual(url2, res2, "should be no-op when key exists (with fragment)");

    string res3 = Helpers::AppendQueryParam(url1, "", "1");
    ctx.AssertEqual(url1, res3, "should be no-op for empty key");
}

/** Tests the friendly formatting of time deltas in milliseconds. */
void Test_FriendlyDeltaLong(TestHelpers::TestContext &inout ctx) {
    ctx.AssertEqual("0s", TimeUtils::FriendlyDeltaLong(0), "zero seconds");
    ctx.AssertEqual("30s", TimeUtils::FriendlyDeltaLong(30 * 1000), "30 seconds");
    ctx.AssertEqual("1m 0s", TimeUtils::FriendlyDeltaLong(60 * 1000), "one minute");
    ctx.AssertEqual("1h 0m", TimeUtils::FriendlyDeltaLong(3600 * 1000), "one hour");
    ctx.AssertEqual("1d 0h", TimeUtils::FriendlyDeltaLong(24 * 3600 * 1000), "one day");
}


// --- Test Runners ---

/**
 * The main test suite runner. It orchestrates the execution of all defined test cases,
 * prints a summary, and shows a UI notification with the overall result.
 */
void RunAllTests() {
    TestHelpers::ClearResults();

    TestHelpers::RunTest("StampFromUTC: Epoch", @Test_StampFromUTC_Epoch);
    TestHelpers::RunTest("StampFromUTC: Roundtrip Leap Year", @Test_StampFromUTC_Roundtrip);
    TestHelpers::RunTest("ParseTimeString: Basic", @Test_ParseTimeString_Basic);
    TestHelpers::RunTest("ParseTimeString: Suffix Handling", @Test_ParseTimeString_Suffixes);
    TestHelpers::RunTest("ParseTimeString: Invalid Inputs", @Test_ParseTimeString_Invalid);
    TestHelpers::RunTest("AppendQueryParam: Basic", @Test_AppendQueryParam_Basic);
    TestHelpers::RunTest("AppendQueryParam: Edge Cases", @Test_AppendQueryParam_EdgeCases);
    TestHelpers::RunTest("FriendlyDeltaLong: Basic Formatting", @Test_FriendlyDeltaLong);

    bool allPassed = TestHelpers::Summary();
    trace("[TESTRUN] All tests completed. Overall status: " + (allPassed ? "PASSED" : "FAILED"));
    
    if (allPassed) {
        if (S_EnableNotifications) UI::ShowNotification("Moon Tests", "All " + tostring(TestHelpers::g_Results.Length) + " tests passed.", vec4(0.2, 0.7, 0.2, 1), 5000);
    } else {
        if (S_EnableNotifications) UI::ShowNotification("Moon Tests", "Some tests failed! See log for details.", vec4(0.9, 0.2, 0.1, 1), 7000);
    }
}

/**
 * A simple wrapper to start the test suite in a new coroutine.
 * This prevents the main UI thread from blocking while the tests are running.
 */
void RunHelpersTests() {
    startnew(RunAllTests);
}