import assert from "node:assert/strict";
import { test } from "node:test";

import { mergeThreadTimeline } from "../functions/analyses.mjs";

// docs/design.md 4.2節「相手ごとの通し会話」(#20)の連結ロジック。

test("複数Analysisのtimelineをanalysis順→position順で連結する", () => {
  const analysisIds = ["a1", "a2"];
  const timelineRows = [
    { id: "e3", analysis_id: "a2", position: 0, speaker: "self", excerpt: "3通目", interest: 60, note: "" },
    { id: "e1", analysis_id: "a1", position: 0, speaker: "self", excerpt: "1通目", interest: 40, note: "" },
    { id: "e2", analysis_id: "a1", position: 1, speaker: "partner", excerpt: "2通目", interest: 45, note: "" },
  ];

  const timeline = mergeThreadTimeline(analysisIds, timelineRows, [], []);

  assert.deepEqual(
    timeline.map((e) => e.id),
    ["e1", "e2", "e3"],
  );
});

test("rewriteとuser_noteをtimeline_entry_idで結びつける", () => {
  const analysisIds = ["a1"];
  const timelineRows = [
    { id: "e1", analysis_id: "a1", position: 0, speaker: "self", excerpt: "本文", interest: 50, note: "AIの一言" },
  ];
  const rewriteRows = [
    { timeline_entry_id: "e1", issue: "問題点", improved_candidates: ["改善案A"], reason: "理由" },
  ];
  const noteRows = [{ timeline_entry_id: "e1", note: "このメッセージは失敗だった" }];

  const [entry] = mergeThreadTimeline(analysisIds, timelineRows, rewriteRows, noteRows);

  assert.equal(entry.user_note, "このメッセージは失敗だった");
  assert.deepEqual(entry.rewrite, { issue: "問題点", improved: ["改善案A"], reason: "理由" });
});

test("rewrite・メモが無いエントリはnullになる", () => {
  const analysisIds = ["a1"];
  const timelineRows = [
    { id: "e1", analysis_id: "a1", position: 0, speaker: "partner", excerpt: "本文", interest: 50, note: "" },
  ];

  const [entry] = mergeThreadTimeline(analysisIds, timelineRows, [], []);

  assert.equal(entry.user_note, null);
  assert.equal(entry.rewrite, null);
});

test("Analysisが1件も無ければ空配列を返す", () => {
  assert.deepEqual(mergeThreadTimeline([], [], [], []), []);
});
