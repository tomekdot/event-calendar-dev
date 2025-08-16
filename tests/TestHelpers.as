namespace TestHelpers {
	class TestResult {
		string name;
		bool passed;
		string message; 

		TestResult() {}
		TestResult(const string &in n, bool p, const string &in m) { name = n; passed = p; message = m; }
	}

	array<TestResult@> g_Results;

	void _Trace(const string &in s) {
		trace("[TEST] " + s);
	}

	int64 UtcMsFromYMDHMS(int Y, int M, int D, int h, int m, int s) {
		int64 secs = Helpers::StampFromUTC(Y, M, D, h, m, s);
		return secs * 1000;
	}

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
				_Trace(name + " extra failure: " + msg);
			}
		}

		void AssertTrue(bool v, const string &in msg = "") {
			if (!v) _Fail((msg.Length != 0) ? msg : "expected true");
		}

		void AssertFalse(bool v, const string &in msg = "") {
			if (v) _Fail((msg.Length != 0) ? msg : "expected false");
		}

		void AssertEqualInt(int expected, int actual, const string &in tag = "") {
			if (expected != actual) {
				string m = _FmtExpAct((tag.Length != 0) ? tag : "int", tostring(expected), tostring(actual));
				_Fail(m);
			}
		}

		void AssertEqualInt64(int64 expected, int64 actual, const string &in tag = "") {
			if (expected != actual) {
				string m = _FmtExpAct((tag.Length != 0) ? tag : "int64", tostring(expected), tostring(actual));
				_Fail(m);
			}
		}

		void AssertEqualBool(bool expected, bool actual, const string &in tag = "") {
			if (expected != actual) {
				string m = _FmtExpAct((tag.Length != 0) ? tag : "bool", tostring(expected), tostring(actual));
				_Fail(m);
			}
		}

		void AssertEqualString(const string &in expected, const string &in actual, const string &in tag = "") {
			if (expected != actual) {
				string m = _FmtExpAct((tag.Length != 0) ? tag : "string", expected, actual);
				_Fail(m);
			}
		}

		void AssertAlmostEqualFloat(float expected, float actual, float tol = 1e-5f, const string &in tag = "") {
			float diff = Math::Abs(expected - actual);
			if (diff > tol) {
				string m = _FmtExpAct((tag.Length != 0) ? tag : "float", tostring(expected), tostring(actual)) + " diff=" + tostring(diff) + " tol=" + tostring(tol);
				_Fail(m);
			}
		}

		void AssertArrayEqualString(const array<string> &in expected, const array<string> &in actual, const string &in tag = "") {
			if (expected.Length != actual.Length) {
				_Fail(_FmtExpAct((tag.Length != 0) ? tag : "array<string>.len", tostring(expected.Length), tostring(actual.Length)));
				return; 
			}
			for (uint i = 0; i < expected.Length; i++) {
				if (expected[i] != actual[i]) {
					_Fail(_FmtExpAct((tag.Length != 0) ? tag : "array<string> item", expected[i], actual[i]) + " at=" + tostring(i));
					return; 
				}
			}
		}

		void AssertNotNull(ref obj, const string &in tag = "") {
			if (obj is null) _Fail((tag.Length != 0) ? tag : "expected non-null reference");
		}

		void Finish() {
			if (failed) {
				TestResult@ tr = TestResult(name, false, failMsg);
				g_Results.InsertLast(tr);
			} else {
				TestResult@ tr = TestResult(name, true, "");
				g_Results.InsertLast(tr);
				_Trace(name + " PASSED");
			}
		}
	}

	TestContext@ Start(const string &in name) {
		TestContext@ ctx = TestContext(name);
		_Trace("Starting: " + name);
		return ctx;
	}

	bool Summary() {
		int passed = 0; 
		int total = int(g_Results.Length);
		for (uint i = 0; i < g_Results.Length; i++) {
			TestResult@ _r = g_Results[i];
			if (_r !is null && _r.passed) passed++;
		}
		
		_Trace("Test summary: " + tostring(passed) + "/" + tostring(total) + " passed.");
		
		if (passed != total) {
			for (uint i = 0; i < g_Results.Length; i++) {
				TestResult@ _r = g_Results[i];
				if (_r !is null && !_r.passed) {
					_Trace(" - FAIL: " + _r.name + " -> " + _r.message);
				}
			}
		}
		return passed == total;
	}

	void ClearResults() { g_Results.RemoveRange(0, g_Results.Length); }

	void Run() {
		RunHelpersTests();
	}
	
	string ToStringIntArray(const array<int> &in a) {
		string buf = "[";
		for (uint i = 0; i < a.Length; i++) {
			if (i != 0) buf += ", ";
			buf += tostring(a[i]);
		}
		buf += "]";
		return buf;
	}

	string ToStringStringArray(const array<string> &in a) {
		string buf = "[";
		for (uint i = 0; i < a.Length; i++) {
			if (i != 0) buf += ", ";
			buf += "\"" + a[i] + "\"";
		}
		buf += "]";
		return buf;
	}


	void UtcYMDFromMs(int64 ms, int &out Y, int &out M, int &out D) {
		::UtcYMDFromMs(ms, Y, M, D);
	}
	
	void UtcYMDHMSFromMs(int64 ms, int &out Y, int &out M, int &out D, int &out h, int &out m, int &out s) {
		::UtcYMDHMSFromMs(ms, Y, M, D, h, m, s);
	}
}

void RunHelpersTests() {
	TestHelpers::ClearResults();
	TestHelpers::TestContext@ ctx = TestHelpers::Start("helpers smoke");

	ctx.AssertTrue(true, "sanity");
	ctx.AssertEqualInt(1, 1, "one equals one");
	ctx.Finish();
	
	bool ok = TestHelpers::Summary();
	trace("[TESTRUN] RunHelpersTests completed - all passed: " + tostring(ok));
	
	if (ok) {
		UI::ShowNotification("Moon Tests", "All helper tests passed.", vec4(0.15, 0.7, 0.25, 1), 4000);
	} else {
		UI::ShowNotification("Moon Tests", "Some helper tests failed. See log.", vec4(0.9, 0.45, 0.1, 1), 6000);
	}
}
