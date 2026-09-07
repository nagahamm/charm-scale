import assert from "node:assert/strict";
import { test } from "node:test";

import { aggregateOverview } from "../functions/analyses.mjs";

// docs/design.md 4.3節: Person をまたいだ全体的なフィードバックの集計ロジック。

test("chat/photo それぞれの件数・推移(created_at昇順)・項目別平均を集計する", () => {
  const analysesRows = [
    { mode: "chat", interest_score: 40, created_at: "2026-08-01T00:00:00Z" },
    { mode: "chat", interest_score: 60, created_at: "2026-08-10T00:00:00Z" },
    { mode: "photo", interest_score: 55, created_at: "2026-08-05T00:00:00Z" },
  ];
  const metricsRows = [
    { key: "reply_speed", label: "返信速度", score: 70, analyses: { mode: "chat" } },
    { key: "reply_speed", label: "返信速度", score: 90, analyses: { mode: "chat" } },
    { key: "first_impression", label: "第一印象", score: 60, analyses: { mode: "photo" } },
  ];

  const overview = aggregateOverview(analysesRows, metricsRows);

  assert.equal(overview.chat.count, 2);
  assert.deepEqual(overview.chat.trend, [40, 60]);
  assert.deepEqual(overview.chat.metrics, [{ key: "reply_speed", label: "返信速度", score: 80, count: 2 }]);

  assert.equal(overview.photo.count, 1);
  assert.deepEqual(overview.photo.trend, [55]);
  assert.deepEqual(overview.photo.metrics, [
    { key: "first_impression", label: "第一印象", score: 60, count: 1 },
  ]);
});

test("interest_score が無い分析は推移から除外する", () => {
  const analysesRows = [
    { mode: "chat", interest_score: null, created_at: "2026-08-01T00:00:00Z" },
    { mode: "chat", interest_score: 50, created_at: "2026-08-02T00:00:00Z" },
  ];

  const overview = aggregateOverview(analysesRows, []);

  assert.equal(overview.chat.count, 2);
  assert.deepEqual(overview.chat.trend, [50]);
});

test("Analysis が1件も無いモードは 0件・空配列を返す", () => {
  const overview = aggregateOverview([], []);

  assert.deepEqual(overview.chat, { count: 0, trend: [], metrics: [] });
  assert.deepEqual(overview.photo, { count: 0, trend: [], metrics: [] });
});
