import { getServiceClient } from "./persistence.mjs";

// docs/design.md 4.1節: 新規登録の受付可否だけを返す読み出し専用API。
// アカウントを持たない利用者が呼ぶため認証は不要。現在のユーザー数・上限値は返さない。
// 実際の強制は auth.users の before insert トリガー(0004_signup_limit.sql)が行う。

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

// 設定が未投入・確認に失敗した場合は受付中として扱う(fail-open。締め出しの事故を避ける)。
export const isAccepting = ({ data, error }) => {
  if (error) {
    console.error("signup status lookup failed", error);
    return true;
  }
  return data !== false;
};

export default async (req) => {
  if (req.method !== "GET") return json(405, { error: "GET only" });

  const client = getServiceClient();
  if (!client) return json(200, { accepting: true });

  const result = await client.rpc("signup_accepting");
  return json(200, { accepting: isAccepting(result) });
};

export const config = { path: "/api/signup-status" };
