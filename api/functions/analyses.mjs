import { AUTH_OK, getServiceClient, verifyUser } from "./persistence.mjs";

// docs/design.md 4.2節: Person(相手)のCRUDと、Personに紐づくAnalysis履歴の読み出し専用API。
// 書き込み(解析結果の保存)は analyse.mjs、Supabaseクライアント初期化は persistence.mjs が担う。

const MAX_NICKNAME_LENGTH = 50;
const MAX_MEMO_LENGTH = 1000;

const METRIC_KEYS_CHAT = [
  "reply_speed",
  "volume_balance",
  "question_return",
  "emotional_expression",
  "initiative",
];

const METRIC_KEYS_PHOTO = ["first_impression", "overall_impression_consistency"];

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const listPersons = async (client, userId) => {
  const { data, error } = await client
    .from("persons")
    .select("id, nickname, memo, created_at, analyses(id, headline, interest_score, phase, created_at)")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .order("created_at", { foreignTable: "analyses", ascending: false })
    .limit(1, { foreignTable: "analyses" });
  if (error) throw error;
  return data.map((p) => ({
    id: p.id,
    nickname: p.nickname,
    memo: p.memo,
    created_at: p.created_at,
    latest: p.analyses?.[0] ?? null,
  }));
};

const createPerson = async (client, userId, nickname) => {
  const { data, error } = await client
    .from("persons")
    .insert({ user_id: userId, nickname })
    .select("id, nickname, memo, created_at")
    .single();
  if (error) throw error;
  return data;
};

const deletePerson = async (client, userId, personId) => {
  const { error } = await client.from("persons").delete().eq("id", personId).eq("user_id", userId);
  if (error) throw error;
};

// docs/design.md 4.2節「利用者自身のメモ」(#21): Person単位の振り返りメモを更新する。
const updatePersonMemo = async (client, userId, personId, memo) => {
  const { data, error } = await client
    .from("persons")
    .update({ memo })
    .eq("id", personId)
    .eq("user_id", userId)
    .select("id, nickname, memo, created_at")
    .single();
  if (error) throw error;
  return data;
};

// entryId が該当ユーザーの Analysis に属する Timeline entry かどうかを確認する
// (Service Role キーは RLS を無視するため、アプリケーション側で必ず絞り込む)。
const ownsTimelineEntry = async (client, userId, entryId) => {
  const { data, error } = await client
    .from("analysis_timeline_entries")
    .select("id, analyses!inner(user_id)")
    .eq("id", entryId)
    .eq("analyses.user_id", userId)
    .maybeSingle();
  if (error) throw error;
  return !!data;
};

// メッセージ(timeline_entry)単位の利用者メモを upsert する。空文字は未記入に戻す(行を削除する)。
const setMessageNote = async (client, userId, entryId, note) => {
  if (!(await ownsTimelineEntry(client, userId, entryId))) return false;
  if (note === "") {
    const { error } = await client.from("timeline_entry_notes").delete().eq("timeline_entry_id", entryId);
    if (error) throw error;
    return true;
  }
  const { error } = await client
    .from("timeline_entry_notes")
    .upsert({ timeline_entry_id: entryId, note, updated_at: new Date().toISOString() });
  if (error) throw error;
  return true;
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

const toRewrite = (r) => (r ? { issue: r.issue, improved: r.improved_candidates, reason: r.reason } : null);

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

  const [metrics, timeline, rewrites, nextMoves, profile, notes] = await Promise.all([
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
    client
      .from("timeline_entry_notes")
      .select("timeline_entry_id, note, analysis_timeline_entries!inner(analysis_id)")
      .eq("analysis_timeline_entries.analysis_id", analysisId),
  ]);
  for (const result of [metrics, timeline, rewrites, nextMoves, profile, notes]) {
    if (result.error) throw result.error;
  }

  const metricsByKey = {};
  for (const key of METRIC_KEYS_CHAT) {
    const row = metrics.data.find((m) => m.key === key);
    metricsByKey[key] = row ? { score: row.score, comment: row.comment } : { score: 0, comment: "" };
  }

  const rewriteByTimelineId = new Map(rewrites.data.map((r) => [r.timeline_entry_id, r]));
  const userNoteByTimelineId = new Map(notes.data.map((n) => [n.timeline_entry_id, n.note]));
  const timelineEntries = timeline.data.map((entry) => ({
    id: entry.id,
    speaker: entry.speaker,
    excerpt: entry.excerpt,
    interest: entry.interest,
    note: entry.note,
    user_note: userNoteByTimelineId.get(entry.id) ?? null,
    rewrite: toRewrite(rewriteByTimelineId.get(entry.id)),
  }));

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

// docs/design.md 4.2節「相手ごとの通し会話」(#20): analyses.created_at 昇順で並んだ analysisIds に
// 沿って、各 Analysis の timeline を position 昇順で連結する。行データだけを受け取る純粋関数として
// 切り出し、Supabaseクライアント無しでテストできるようにする(aggregateOverviewと同じ方針)。
export const mergeThreadTimeline = (analysisIds, timelineRows, rewriteRows, noteRows) => {
  const rewriteByTimelineId = new Map(rewriteRows.map((r) => [r.timeline_entry_id, r]));
  const userNoteByTimelineId = new Map(noteRows.map((n) => [n.timeline_entry_id, n.note]));
  const entriesByAnalysis = new Map();
  for (const entry of timelineRows) {
    const list = entriesByAnalysis.get(entry.analysis_id) ?? [];
    list.push(entry);
    entriesByAnalysis.set(entry.analysis_id, list);
  }

  return analysisIds.flatMap((analysisId) =>
    (entriesByAnalysis.get(analysisId) ?? [])
      .sort((a, b) => a.position - b.position)
      .map((entry) => ({
        id: entry.id,
        speaker: entry.speaker,
        excerpt: entry.excerpt,
        interest: entry.interest,
        note: entry.note,
        user_note: userNoteByTimelineId.get(entry.id) ?? null,
        rewrite: toRewrite(rewriteByTimelineId.get(entry.id)),
      }))
  );
};

const buildThread = async (client, userId, personId) => {
  const { data: analyses, error: analysesError } = await client
    .from("analyses")
    .select("id")
    .eq("user_id", userId)
    .eq("person_id", personId)
    .eq("mode", "chat")
    .order("created_at", { ascending: true });
  if (analysesError) throw analysesError;
  if (analyses.length === 0) return { timeline: [] };

  const analysisIds = analyses.map((a) => a.id);
  const [timelineRes, rewritesRes, notesRes] = await Promise.all([
    client
      .from("analysis_timeline_entries")
      .select("id, analysis_id, position, speaker, excerpt, interest, note")
      .in("analysis_id", analysisIds),
    client
      .from("analysis_rewrites")
      .select("timeline_entry_id, issue, improved_candidates, reason")
      .in("analysis_id", analysisIds),
    client
      .from("timeline_entry_notes")
      .select("timeline_entry_id, note, analysis_timeline_entries!inner(analysis_id)")
      .in("analysis_timeline_entries.analysis_id", analysisIds),
  ]);
  if (timelineRes.error) throw timelineRes.error;
  if (rewritesRes.error) throw rewritesRes.error;
  if (notesRes.error) throw notesRes.error;

  const timeline = mergeThreadTimeline(analysisIds, timelineRes.data, rewritesRes.data, notesRes.data);
  return { timeline };
};

// docs/design.md 4.3節: Person をまたいだ全体的なフィードバック。専用の集計テーブルは持たず都度集計する。
// 取得済みの行から集計するだけの純粋関数として切り出し、Supabaseクライアント無しでテストできるようにする。
export const aggregateOverview = (analysesRows, metricsRows) => {
  const forMode = (mode, metricKeys) => {
    const analyses = analysesRows.filter((a) => a.mode === mode);
    const trend = analyses.filter((a) => a.interest_score != null).map((a) => a.interest_score);

    const totals = new Map();
    for (const row of metricsRows) {
      if (row.analyses.mode !== mode) continue;
      const entry = totals.get(row.key) ?? { label: row.label, sum: 0, count: 0 };
      entry.sum += row.score;
      entry.count += 1;
      totals.set(row.key, entry);
    }
    const metrics = metricKeys
      .filter((key) => totals.has(key))
      .map((key) => {
        const entry = totals.get(key);
        return { key, label: entry.label, score: Math.round(entry.sum / entry.count), count: entry.count };
      });

    return { count: analyses.length, trend, metrics };
  };

  return {
    chat: forMode("chat", METRIC_KEYS_CHAT),
    photo: forMode("photo", METRIC_KEYS_PHOTO),
  };
};

const buildOverview = async (client, userId) => {
  const [analysesRes, metricsRes] = await Promise.all([
    client
      .from("analyses")
      .select("mode, interest_score, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: true }),
    client
      .from("analysis_metrics")
      .select("key, label, score, analyses!inner(mode, user_id)")
      .eq("analyses.user_id", userId),
  ]);
  if (analysesRes.error) throw analysesRes.error;
  if (metricsRes.error) throw metricsRes.error;

  return aggregateOverview(analysesRes.data, metricsRes.data);
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

    if (req.method === "PATCH" && resource === "persons") {
      const personId = url.searchParams.get("person_id");
      if (!personId) return json(400, { error: "person_id が指定されていません。" });
      let body;
      try {
        body = await req.json();
      } catch {
        return json(400, { error: "リクエストの形式が不正です。" });
      }
      const memo = typeof body?.memo === "string" ? body.memo : null;
      if (memo === null) return json(400, { error: "memo を指定してください。" });
      if (memo.length > MAX_MEMO_LENGTH) {
        return json(400, { error: `メモは${MAX_MEMO_LENGTH}文字以内にしてください。` });
      }
      return json(200, await updatePersonMemo(client, auth.userId, personId, memo));
    }

    if (req.method === "PATCH" && resource === "message_note") {
      const entryId = url.searchParams.get("entry_id");
      if (!entryId) return json(400, { error: "entry_id が指定されていません。" });
      let body;
      try {
        body = await req.json();
      } catch {
        return json(400, { error: "リクエストの形式が不正です。" });
      }
      const note = typeof body?.note === "string" ? body.note.trim() : null;
      if (note === null) return json(400, { error: "note を指定してください。" });
      if (note.length > MAX_MEMO_LENGTH) {
        return json(400, { error: `メモは${MAX_MEMO_LENGTH}文字以内にしてください。` });
      }
      const ok = await setMessageNote(client, auth.userId, entryId, note);
      if (!ok) return json(404, { error: "見つかりませんでした。" });
      return json(200, { ok: true, note: note === "" ? null : note });
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

    if (req.method === "GET" && resource === "thread") {
      const personId = url.searchParams.get("person_id");
      if (!personId) return json(400, { error: "person_id が指定されていません。" });
      return json(200, await buildThread(client, auth.userId, personId));
    }

    if (req.method === "GET" && resource === "overview") {
      return json(200, await buildOverview(client, auth.userId));
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
