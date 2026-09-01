import assert from "node:assert/strict";
import { test } from "node:test";

import { isAccepting } from "../functions/signup.mjs";

// docs/design.md 4.1節: 設定が未投入・確認に失敗した場合は登録を許可する(fail-open)。

test("上限に達していれば受付を止める", () => {
  assert.equal(isAccepting({ data: false, error: null }), false);
});

test("上限に達していなければ受け付ける", () => {
  assert.equal(isAccepting({ data: true, error: null }), true);
});

test("設定が未投入(null)なら受け付ける", () => {
  assert.equal(isAccepting({ data: null, error: null }), true);
});

test("確認に失敗しても受け付ける", () => {
  assert.equal(isAccepting({ data: null, error: { message: "boom" } }), true);
});
