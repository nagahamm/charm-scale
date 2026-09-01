import "package:flutter_test/flutter_test.dart";

import "package:charm_scale/services/signup_api.dart";

void main() {
  group("acceptingFromResponse", () {
    test("上限に達していれば受付停止として扱う", () {
      expect(acceptingFromResponse(200, '{"accepting": false}'), isFalse);
    });

    test("受付中はそのまま受付中", () {
      expect(acceptingFromResponse(200, '{"accepting": true}'), isTrue);
    });

    // fail-open: 締め出しの事故を避けるため、判断できないものはすべて受付中にする。
    test("エラー応答・壊れたJSON・想定外の形はすべて受付中", () {
      expect(acceptingFromResponse(500, '{"error": "boom"}'), isTrue);
      expect(acceptingFromResponse(200, "not json"), isTrue);
      expect(acceptingFromResponse(200, "[]"), isTrue);
      expect(acceptingFromResponse(200, "{}"), isTrue);
    });
  });
}
