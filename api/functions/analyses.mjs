import { AUTH_OK, getServiceClient, verifyUser } from "./persistence.mjs";

// docs/design.md 4.2節: Person(相手)のCRUDと、Personに紐づくAnalysis履歴の読み出し専用API。
// 書き込み(解析結果の保存)は analyse.mjs、Supabaseクライアント初期化は persistence.mjs が担う。

const MAX_NICKNAME_LENGTH = 50;

const METRIC_KEYS_CHAT = [
  "reply_speed",
  "volume_balance",
  "question_return",
  "emotional_expression",
  "initiative",
];

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const listPersons = async (client, userId) => {
  const { data, error } = await client
    .from("persons")
    .select("id, nickname, created_at, analyses(id, headline, interest_score, phase, created_at)")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .order("created_at", { foreignTable: "analyses", ascending: false })
    .limit(1, { foreignTable: "analyses" });
  if (error) throw error;
  return data.map((p) => ({
    id: p.id,
    nickname: p.nickname,
    created_at: p.created_at,
    latest: p.analyses?.[0] ?? null,
  }));
};

const createPerson = async (client, userId, nickname) => {
  const { data, error } = await client
    .from("persons")
    .insert({ user_id: userId, nickname })
    .select("id, nickname, created_at")
    .single();
  if (error) throw error;
  return data;
};

const deletePerson = async (client, userId, personId) => {
  const { error } = await client.from("persons").delete().eq("id", personId).eq("user_id", userId);
  if (error) throw error;
};

const listAnalyses = async (client, userId, personId) => {
  const { data, error } = await client
    .from("analyses")
    .select("id, headline, interest_score, phase, created_at")
    .eq("user_id", userId)
    .eq("person_id", personId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
};

// 正規化テーブル群から CHAT_SCHEMA(api/functions/analyse.mjs)と同じ形のJSONを組み立てる。
// mode が chat 以外(または見つからない・他人のもの)の場合は null を返す。
const buildChatDetail = async (client, userId, analysisId) => {
  const { data: analysis, error: analysisError } = await client
    .from("analyses")
    .select("mode, headline, summary, interest_score, phase, good_points, bad_points")
    .eq("id", analysisId)
    .eq("user_id", userId)
    .maybeSingle();
  if (analysisError) throw analysisError;
  if (!analysis || analysis.mode !== "chat") return null;

  const [metrics, timeline, rewrites, nextMoves, profile] = await Promise.all([
    client.from("analysis_metrics").select("key, score, comment").eq("analysis_id", analysisId),
    client
      .from("analysis_timeline_entries")
      .select("id, speaker, excerpt, interest, note")
      .eq("analysis_id", analysisId)
      .order("position"),
    client
      .from("analysis_rewrites")
      .select("timeline_entry_id, issue, improved_candidates, reason")
      .eq("analysis_id", analysisId),
    client.from("analysis_next_moves").select("label, message, aim").eq("analysis_id", analysisId),
    client
      .from("analysis_profiles")
      .select("reported_age, reported_occupation, likes_count, bio_summary, notes, attributes, tags, talking_points")
      .eq("analysis_id", analysisId)
      .maybeSingle(),
  ]);
  for (const result of [metrics, timeline, rewrites, nextMoves, profile]) {
    if (result.error) throw result.error;
  }

  const metricsByKey = {};
  for (const key of METRIC_KEYS_CHAT) {
    const row = metrics.data.find((m) => m.key === key);
    metricsByKey[key] = row ? { score: row.score, comment: row.comment } : { score: 0, comment: "" };
  }

  const rewriteByTimelineId = new Map(rewrites.data.map((r) => [r.timeline_entry_id, r]));
  const timelineEntries = timeline.data.map((entry) => {
    const rewrite = rewriteByTimelineId.get(entry.id);
    return {
      speaker: entry.speaker,
      excerpt: entry.excerpt,
      interest: entry.interest,
      note: entry.note,
      rewrite: rewrite
        ? { issue: rewrite.issue, improved: rewrite.improved_candidates, reason: rewrite.reason }
        : null,
    };
  });

  return {
    headline: analysis.headline,
    interest_score: analysis.interest_score,
    phase: analysis.phase,
    summary: analysis.summary,
    profile: profile.data
      ? {
          reported_age: profile.data.reported_age,
          reported_occupation: profile.data.reported_occupation,
          likes_count: profile.data.likes_count,
          bio_summary: profile.data.bio_summary,
          attributes: profile.data.attributes,
          tags: profile.data.tags,
          talking_points: profile.data.talking_points,
          notes: profile.data.notes,
        }
      : null,
    metrics: metricsByKey,
    timeline: timelineEntries,
    good_points: analysis.good_points,
    bad_points: analysis.bad_points,
    next_moves: nextMoves.data,
  };
};

export default async (req) => {
  const auth = await verifyUser(req.headers.get("authorization"));
  if (auth.status !== AUTH_OK) return json(401, { error: "ログインが必要です。" });

  const client = getServiceClient();
  if (!client) return json(500, { error: "Supabase が未設定です。" });

  const url = new URL(req.url);
  const resource = url.searchParams.get("resource");

  try {
    if (req.method === "GET" && resource === "persons") {
      return json(200, { persons: await listPersons(client, auth.userId) });
    }

    if (req.method === "POST" && resource === "persons") {
      let body;
      try {
        body = await req.json();
      } catch {
        return json(400, { error: "リクエストの形式が不正です。" });
      }
      const nickname = typeof body?.nickname === "string" ? body.nickname.trim() : "";
      if (nickname.length === 0) return json(400, { error: "ニックネームを入力してください。" });
      if (nickname.length > MAX_NICKNAME_LENGTH) {
        return json(400, { error: `ニックネームは${MAX_NICKNAME_LENGTH}文字以内にしてください。` });
      }
      return json(200, await createPerson(client, auth.userId, nickname));
    }

    if (req.method === "DELETE" && resource === "persons") {
      const personId = url.searchParams.get("person_id");
      if (!personId) return json(400, { error: "person_id が指定されていません。" });
      await deletePerson(client, auth.userId, personId);
      return json(200, { ok: true });
    }

    if (req.method === "GET" && resource === "list") {
      const personId = url.searchParams.get("person_id");
      if (!personId) return json(400, { error: "person_id が指定されていません。" });
      return json(200, { analyses: await listAnalyses(client, auth.userId, personId) });
    }

    if (req.method === "GET" && resource === "detail") {
      const analysisId = url.searchParams.get("analysis_id");
      if (!analysisId) return json(400, { error: "analysis_id が指定されていません。" });
      const detail = await buildChatDetail(client, auth.userId, analysisId);
      if (!detail) return json(404, { error: "見つかりませんでした。" });
      return json(200, detail);
    }

    return json(400, { error: "不正なリクエストです。" });
  } catch (err) {
    console.error("analyses api failed", err);
    return json(500, { error: "処理に失敗しました。" });
  }
};

export const config = { path: "/api/analyses" };
