void RunHelpersUnitTests() {
    TestHelpers::ClearResults();

    TestHelpers::TestContext@ ctx1 = TestHelpers::Start("StampFromUTC epoch");
    int64 ms = TestHelpers::UtcMsFromYMDHMS(1970,1,1,0,0,0);
    ctx1.AssertEqualInt64(0, ms, "epoch should be zero");
    ctx1.Finish();

    TestHelpers::TestContext@ ctx2 = TestHelpers::Start("StampFromUTC leap year");
    int64 ms2 = TestHelpers::UtcMsFromYMDHMS(2020,2,29,12,34,56);
    int Y; int M; int D; int h; int m; int s;
    TestHelpers::UtcYMDHMSFromMs(ms2, Y, M, D, h, m, s);
    ctx2.AssertEqualInt(2020, Y, "year");
    ctx2.AssertEqualInt(2, M, "month");
    ctx2.AssertEqualInt(29, D, "day");
    ctx2.AssertEqualInt(12, h, "hour");
    ctx2.AssertEqualInt(34, m, "minute");
    ctx2.AssertEqualInt(56, s, "second");
    ctx2.Finish();

    TestHelpers::TestContext@ ctx3 = TestHelpers::Start("ParseTimeString basic");
    int ph; int pm; int ps;
    bool ok = Helpers::ParseTimeString("09:05", ph, pm, ps);
    ctx3.AssertTrue(ok, "parse should succeed");
    ctx3.AssertEqualInt(9, ph, "hour");
    ctx3.AssertEqualInt(5, pm, "minute");
    ctx3.AssertEqualInt(0, ps, "second default");
    ctx3.Finish();

    TestHelpers::TestContext@ ctx4 = TestHelpers::Start("ParseTimeString with UTC suffix");
    ok = Helpers::ParseTimeString("23:59 UTC", ph, pm, ps);
    ctx4.AssertTrue(ok, "parse should handle UTC suffix");
    ctx4.AssertEqualInt(23, ph, "hour");
    ctx4.AssertEqualInt(59, pm, "minute");
    ctx4.Finish();

    TestHelpers::TestContext@ ctx5 = TestHelpers::Start("ParseTimeString no-space-utc");
    ok = Helpers::ParseTimeString("00:00UTC", ph, pm, ps);
    ctx5.AssertTrue(ok, "should parse UTC without space");
    ctx5.AssertEqualInt(0, ph, "hour");
    ctx5.Finish();

    TestHelpers::TestContext@ ctx6 = TestHelpers::Start("ParseTimeString extra spaces");
    ok = Helpers::ParseTimeString(" 7:8  ut ", ph, pm, ps);
    ctx6.AssertTrue(ok, "should parse with extra spaces and ut");
    ctx6.AssertEqualInt(7, ph, "hour");
    ctx6.AssertEqualInt(8, pm, "minute");
    ctx6.Finish();

    TestHelpers::TestContext@ ctx7 = TestHelpers::Start("DaysFromCivil boundary");
    // Check day before epoch
    int64 msBefore = TestHelpers::UtcMsFromYMDHMS(1969,12,31,23,59,59);
    int Yb; int Mb; int Db; int hb; int mb; int sb;
    TestHelpers::UtcYMDHMSFromMs(msBefore, Yb, Mb, Db, hb, mb, sb);
    ctx7.AssertEqualInt(1969, Yb, "year before epoch");
    ctx7.AssertEqualInt(12, Mb, "month before epoch");
    ctx7.AssertEqualInt(31, Db, "day before epoch");
    ctx7.Finish();

    TestHelpers::TestContext@ ctx8 = TestHelpers::Start("ParseTimeString invalid format");
    ok = Helpers::ParseTimeString("not-a-time", ph, pm, ps);
    ctx8.AssertFalse(ok, "invalid format should fail");
    ctx8.Finish();

    TestHelpers::TestContext@ ctx9 = TestHelpers::Start("ParseTimeString out-of-range");
    ok = Helpers::ParseTimeString("24:00", ph, pm, ps);
    ctx9.AssertFalse(ok, "hour 24 should be invalid");
    ctx9.Finish();

    TestHelpers::TestContext@ ctx10 = TestHelpers::Start("ParseTimeString seconds present");
    ok = Helpers::ParseTimeString("12:34:56", ph, pm, ps);
    ctx10.AssertTrue(ok, "should parse hh:mm:ss");
    ctx10.AssertEqualInt(56, ps, "seconds parsed");
    ctx10.Finish();

    TestHelpers::TestContext@ ctx11 = TestHelpers::Start("DaysFromCivil far past");
    int64 msPast = TestHelpers::UtcMsFromYMDHMS(1900,1,1,0,0,0);
    int Yp; int Mp; int Dp; int hp; int mp; int sp;
    TestHelpers::UtcYMDHMSFromMs(msPast, Yp, Mp, Dp, hp, mp, sp);
    ctx11.AssertEqualInt(1900, Yp, "year 1900");
    ctx11.Finish();

    TestHelpers::TestContext@ ctx12 = TestHelpers::Start("ParseTimeString non-ascii digits");
    ok = Helpers::ParseTimeString("１２:３４", ph, pm, ps);
    ctx12.AssertFalse(ok, "non-ascii digits should fail under current implementation");
    ctx12.Finish();

    bool okAll = TestHelpers::Summary();
    trace("[TESTRUN] RunHelpersUnitTests all passed: " + tostring(okAll));
}
