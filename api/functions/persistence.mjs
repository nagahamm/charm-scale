import { createClient } from "@supabase/supabase-js";
import { z } from "zod";

// docs/design.md 1.1節・3節: 解析結果の二重化構成(Rawログ + Zod検証 + 正規化DB)。
// Supabase未設定の環境では常に匿名扱いとし、既存のステートレスな挙動を維持する。

export const AUTH_ANONYMOUS = "anonymous";
export const AUTH_INVALID = "invalid";
export const AUTH_OK = "ok";

let cachedClient;

const getServiceClient = () => {
  const url = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) return null;
  if (!cachedClient) {
    cachedClient = createClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }
  return cachedClient;
};

export const verifyUser = async (authorizationHeader) => {
  if (!authorizationHeader) return { status: AUTH_ANONYMOUS };
  const client = getServiceClient();
  if (!client) return { status: AUTH_ANONYMOUS };

  const match = /^Bearer\s+(.+)$/i.exec(authorizationHeader);
  if (!match) return { status: AUTH_INVALID };

  const { data, error } = await client.auth.getUser(match[1].trim());
  if (error || !data?.user) return { status: AUTH_INVALID };
  return { status: AUTH_OK, userId: data.user.id };
};

export const persistRawLog = async ({ userId, mode, rawResponse }) => {
  const client = getServiceClient();
  if (!client) return;
  try {
    const { error } = await client
      .from("analysis_raw_logs")
      .insert({ user_id: userId, mode, raw_response: rawResponse });
    if (error) console.error("raw log insert failed", error);
  } catch (err) {
    console.error("raw log insert failed", err);
  }
};

// --- Zod スキーマ(analyse.mjs の CHAT_SCHEMA / PHOTO_SCHEMA / DRAFT_CHECK_SCHEMA と同じ形) ---

const score = z.number().int().min(0).max(100);
const metricItem = z.object({ score, comment: z.string() });

const chatMetricsSchema = z.object({
  reply_speed: metricItem,
  volume_balance: metricItem,
  question_return: metricItem,
  emotional_expression: metricItem,
  initiative: metricItem,
});

const photoMetricsSchema = z.object({
  first_impression: metricItem,
  overall_impression_consistency: metricItem,
});

const profileInfoSchema = z
  .object({
    reported_age: z.string().nullable(),
    reported_occupation: z.string().nullable(),
    likes_count: z.string().nullable(),
    bio_summary: z.string(),
    attributes: z.array(z.object({ label: z.string(), value: z.string() })),
    tags: z.array(z.string()),
    talking_points: z.array(z.string()),
    notes: z.string(),
  })
  .nullable();

const rewriteSchema = z
  .object({
    issue: z.string(),
    improved: z.array(z.string()).min(2).max(3),
    reason: z.string(),
  })
  .nullable();

const timelineEntrySchema = z.object({
  speaker: z.enum(["self", "partner"]),
  excerpt: z.string(),
  interest: score,
  note: z.string(),
  rewrite: rewriteSchema,
});

const nextMoveSchema = z.object({ label: z.string(), message: z.string(), aim: z.string() });

export const chatResultSchema = z.object({
  headline: z.string(),
  interest_score: score,
  phase: z.enum(["接続直後", "様子見", "興味あり", "盛り上がり", "デート打診可", "失速", "終了間際"]),
  summary: z.string(),
  profile: profileInfoSchema,
  metrics: chatMetricsSchema,
  timeline: z.array(timelineEntrySchema),
  good_points: z.array(z.string()),
  bad_points: z.array(z.string()),
  next_moves: z.array(nextMoveSchema).min(2).max(3),
});

const photoEvaluationSchema = z.object({
  category: z.enum(["portrait", "lifestyle", "scenery", "food", "pet", "other"]),
  score,
  comment: z.string(),
  retake: z
    .object({ title: z.string(), how: z.string(), reason: z.string() })
    .nullable(),
});

const bioRewriteSchema = z.object({
  original: z.string(),
  issue: z.string(),
  improved: z.string(),
  reason: z.string(),
});

const positioningSchema = z
  .object({
    estimate: z.string(),
    basis: z.string(),
    source_url: z.string(),
    disclaimer: z.string(),
  })
  .nullable();

export const photoResultSchema = z.object({
  headline: z.string(),
  interest_score: score,
  summary: z.string(),
  metrics: photoMetricsSchema,
  photos: z.array(photoEvaluationSchema),
  bio_rewrites: z.array(bioRewriteSchema),
  positioning: positioningSchema,
});

export const draftCheckResultSchema = z.object({
  candidates: z.array(z.string()).min(2).max(3),
  reaction: z.object({ estimate: z.string(), reasoning: z.string() }),
  predicted_reply: z.string(),
});

export const RESULT_SCHEMA_BY_MODE = {
  chat: chatResultSchema,
  photo: photoResultSchema,
  draft_check: draftCheckResultSchema,
};

// --- 正規化テーブルへの保存(3節のテーブル定義に対応) ---

const METRIC_LABELS = {
  chat: {
    reply_speed: "返信速度",
    volume_balance: "文量バランス",
    question_return: "質問返し",
    emotional_expression: "感情表現",
    initiative: "主導権",
  },
  photo: {
    first_impression: "第一印象",
    overall_impression_consistency: "全体印象の一貫性",
  },
};

const insertMetrics = async (client, analysisId, metrics, labels) => {
  const rows = Object.entries(metrics).map(([key, { score: s, comment }]) => ({
    analysis_id: analysisId,
    key,
    label: labels[key],
    score: s,
    comment,
  }));
  const { error } = await client.from("analysis_metrics").insert(rows);
  if (error) throw error;
};

const persistChatResult = async (client, { userId, personId, result }) => {
  const { data: analysis, error: analysisError } = await client
    .from("analyses")
    .insert({
      person_id: personId,
      user_id: userId,
      mode: "chat",
      headline: result.headline,
      summary: result.summary,
      interest_score: result.interest_score,
      phase: result.phase,
      good_points: result.good_points,
      bad_points: result.bad_points,
    })
    .select("id")
    .single();
  if (analysisError) throw analysisError;
  const analysisId = analysis.id;

  await insertMetrics(client, analysisId, result.metrics, METRIC_LABELS.chat);

  if (result.timeline.length > 0) {
    const timelineRows = result.timeline.map((entry, position) => ({
      analysis_id: analysisId,
      position,
      speaker: entry.speaker,
      excerpt: entry.excerpt,
      interest: entry.interest,
      note: entry.note,
    }));
    const { data: insertedTimeline, error: timelineError } = await client
      .from("analysis_timeline_entries")
      .insert(timelineRows)
      .select("id, position");
    if (timelineError) throw timelineError;

    const rewriteRows = result.timeline
      .map((entry, position) => ({ entry, position }))
      .filter(({ entry }) => entry.rewrite)
      .map(({ entry, position }) => ({
        analysis_id: analysisId,
        timeline_entry_id: insertedTimeline.find((t) => t.position === position)?.id ?? null,
        original: null,
        issue: entry.rewrite.issue,
        improved_candidates: entry.rewrite.improved,
        reason: entry.rewrite.reason,
      }));
    if (rewriteRows.length > 0) {
      const { error: rewriteError } = await client.from("analysis_rewrites").insert(rewriteRows);
      if (rewriteError) throw rewriteError;
    }
  }

  const nextMoveRows = result.next_moves.map((m) => ({
    analysis_id: analysisId,
    label: m.label,
    message: m.message,
    aim: m.aim,
  }));
  const { error: nextMoveError } = await client.from("analysis_next_moves").insert(nextMoveRows);
  if (nextMoveError) throw nextMoveError;

  if (result.profile) {
    const { error: profileError } = await client.from("analysis_profiles").insert({
      analysis_id: analysisId,
      reported_age: result.profile.reported_age,
      reported_occupation: result.profile.reported_occupation,
      likes_count: result.profile.likes_count,
      bio_summary: result.profile.bio_summary,
      notes: result.profile.notes,
      attributes: result.profile.attributes,
      tags: result.profile.tags,
      talking_points: result.profile.talking_points,
    });
    if (profileError) throw profileError;
  }
};

const persistPhotoResult = async (client, { userId, personId, result }) => {
  const { data: analysis, error: analysisError } = await client
    .from("analyses")
    .insert({
      person_id: personId,
      user_id: userId,
      mode: "photo",
      headline: result.headline,
      summary: result.summary,
      interest_score: result.interest_score,
      phase: null,
      good_points: [],
      bad_points: [],
    })
    .select("id")
    .single();
  if (analysisError) throw analysisError;
  const analysisId = analysis.id;

  await insertMetrics(client, analysisId, result.metrics, METRIC_LABELS.photo);

  if (result.photos.length > 0) {
    const photoRows = result.photos.map((photo, position) => ({
      analysis_id: analysisId,
      position,
      category: photo.category,
      score: photo.score,
      comment: photo.comment,
      retake_title: photo.retake?.title ?? null,
      retake_how: photo.retake?.how ?? null,
      retake_reason: photo.retake?.reason ?? null,
    }));
    const { error: photoError } = await client.from("analysis_photos").insert(photoRows);
    if (photoError) throw photoError;
  }

  if (result.bio_rewrites.length > 0) {
    const rewriteRows = result.bio_rewrites.map((r) => ({
      analysis_id: analysisId,
      timeline_entry_id: null,
      original: r.original,
      issue: r.issue,
      improved_candidates: [r.improved],
      reason: r.reason,
    }));
    const { error: rewriteError } = await client.from("analysis_rewrites").insert(rewriteRows);
    if (rewriteError) throw rewriteError;
  }

  if (result.positioning) {
    const { error: positioningError } = await client.from("analysis_positioning").insert({
      analysis_id: analysisId,
      estimate: result.positioning.estimate,
      basis: result.positioning.basis,
      source_url: result.positioning.source_url,
      disclaimer: result.positioning.disclaimer,
    });
    if (positioningError) throw positioningError;
  }
};

// mode は "chat" | "photo" のみ(draft_check は正規化テーブルを持たず、Rawログのみ)。
export const persistAnalysisResult = async ({ mode, userId, personId, result }) => {
  const client = getServiceClient();
  if (!client) return;
  try {
    if (mode === "chat") await persistChatResult(client, { userId, personId, result });
    else if (mode === "photo") await persistPhotoResult(client, { userId, personId, result });
  } catch (err) {
    console.error(`persist ${mode} result failed`, err);
  }
};
