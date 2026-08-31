import assert from "node:assert/strict";
import { test } from "node:test";

import {
  DEFAULT_DAILY_ANALYSIS_LIMIT,
  checkDailyLimit,
  dailyAnalysisLimit,
  jstDay,
} from "../functions/persistence.mjs";

// docs/design.md 4.4節: 上限値は環境変数、日付の境界は日本時間。

test("上限値は環境変数から読む", () => {
  assert.equal(dailyAnalysisLimit({ DAILY_ANALYSIS_LIMIT: "5" }), 5);
  assert.equal(dailyAnalysisLimit({ DAILY_ANALYSIS_LIMIT: " 12 " }), 12);
  assert.equal(dailyAnalysisLimit({ DAILY_ANALYSIS_LIMIT: "0" }), 0);
});

test("未設定・不正値はデフォルトに落とす", () => {
  for (const env of [
    {},
    { DAILY_ANALYSIS_LIMIT: "" },
    { DAILY_ANALYSIS_LIMIT: "   " },
    { DAILY_ANALYSIS_LIMIT: "abc" },
    { DAILY_ANALYSIS_LIMIT: "3.5" },
    { DAILY_ANALYSIS_LIMIT: "-1" },
  ]) {
    assert.equal(dailyAnalysisLimit(env), DEFAULT_DAILY_ANALYSIS_LIMIT);
  }
});

test("日付は日本時間の暦日で切り替わる", () => {
  // 日本時間 2026-08-31 00:00 = UTC 2026-08-30 15:00
  assert.equal(jstDay(new Date("2026-08-30T14:59:59Z")), "2026-08-30");
  assert.equal(jstDay(new Date("2026-08-30T15:00:00Z")), "2026-08-31");
  assert.equal(jstDay(new Date("2026-08-31T00:00:00Z")), "2026-08-31");
});

test("Supabase 未設定・匿名リクエストでは制限をかけない", async () => {
  assert.deepEqual(await checkDailyLimit(null), {
    allowed: true,
    limit: DEFAULT_DAILY_ANALYSIS_LIMIT,
    count: 0,
  });
});
