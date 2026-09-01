import assert from "node:assert/strict";
import { test } from "node:test";

import { previousSummaryInstruction } from "../functions/analyse.mjs";

// docs/design.md 4.2節: 続きのスクショで分析を更新するときに前回の流れを引き継ぐ指示。

test("要約があれば、続きとして読むよう指示する", () => {
  const instruction = previousSummaryInstruction("前回は日程調整の直前で止まっていた。");

  assert.match(instruction, /前回は日程調整の直前で止まっていた。/);
  assert.match(instruction, /このアプリが以前生成したもの/);
  assert.match(instruction, /この続きのやり取り/);
  // 要約とスクショが食い違う場合はスクショを優先させる。
  assert.match(instruction, /スクショを優先/);
});

test("要約が無ければ何も足さない", () => {
  for (const value of [undefined, null, "", "   ", 123]) {
    assert.equal(previousSummaryInstruction(value), "");
  }
});
