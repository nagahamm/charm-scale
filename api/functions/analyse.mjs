import Anthropic from "@anthropic-ai/sdk";

const MODEL = "claude-opus-5";
const MAX_IMAGES = 8;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ALLOWED_MEDIA_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"];
const MODES = ["chat", "photo", "profile"];

const SCORE = { type: "integer", minimum: 0, maximum: 100 };

const metricItem = () => ({
  type: "object",
  properties: {
    score: SCORE,
    comment: { type: "string" },
  },
  required: ["score", "comment"],
  additionalProperties: false,
});

const CHAT_METRICS = {
  type: "object",
  properties: {
    reply_speed: metricItem(),
    volume_balance: metricItem(),
    question_return: metricItem(),
    emotional_expression: metricItem(),
    initiative: metricItem(),
  },
  required: ["reply_speed", "volume_balance", "question_return", "emotional_expression", "initiative"],
  additionalProperties: false,
};

const PHOTO_METRICS = {
  type: "object",
  properties: {
    first_impression: metricItem(),
    expression: metricItem(),
    composition_quality: metricItem(),
    styling_cleanliness: metricItem(),
    background_situation: metricItem(),
  },
  required: [
    "first_impression",
    "expression",
    "composition_quality",
    "styling_cleanliness",
    "background_situation",
  ],
  additionalProperties: false,
};

const CHAT_SCHEMA = {
  type: "object",
  properties: {
    headline: { type: "string" },
    interest_score: SCORE,
    phase: {
      type: "string",
      enum: ["接続直後", "様子見", "興味あり", "盛り上がり", "デート打診可", "失速", "終了間際"],
    },
    summary: { type: "string" },
    metrics: CHAT_METRICS,
    timeline: {
      type: "array",
      items: {
        type: "object",
        properties: {
          speaker: { type: "string", enum: ["self", "partner"] },
          excerpt: { type: "string" },
          interest: SCORE,
          note: { type: "string" },
        },
        required: ["speaker", "excerpt", "interest", "note"],
        additionalProperties: false,
      },
    },
    good_points: { type: "array", items: { type: "string" } },
    bad_points: { type: "array", items: { type: "string" } },
    rewrites: {
      type: "array",
      items: {
        type: "object",
        properties: {
          original: { type: "string" },
          issue: { type: "string" },
          improved: { type: "string" },
          reason: { type: "string" },
        },
        required: ["original", "issue", "improved", "reason"],
        additionalProperties: false,
      },
    },
    next_moves: {
      type: "array",
      minItems: 2,
      maxItems: 3,
      items: {
        type: "object",
        properties: {
          label: { type: "string" },
          message: { type: "string" },
          aim: { type: "string" },
        },
        required: ["label", "message", "aim"],
        additionalProperties: false,
      },
    },
  },
  required: [
    "headline",
    "interest_score",
    "phase",
    "summary",
    "metrics",
    "timeline",
    "good_points",
    "bad_points",
    "rewrites",
    "next_moves",
  ],
  additionalProperties: false,
};

const PHOTO_SCHEMA = {
  type: "object",
  properties: {
    headline: { type: "string" },
    interest_score: SCORE,
    summary: { type: "string" },
    metrics: PHOTO_METRICS,
    good_points: { type: "array", items: { type: "string" } },
    bad_points: { type: "array", items: { type: "string" } },
    retakes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          how: { type: "string" },
          reason: { type: "string" },
        },
        required: ["title", "how", "reason"],
        additionalProperties: false,
      },
    },
  },
  required: [
    "headline",
    "interest_score",
    "summary",
    "metrics",
    "good_points",
    "bad_points",
    "retakes",
  ],
  additionalProperties: false,
};

const PROFILE_SCHEMA = {
  type: "object",
  properties: {
    headline: { type: "string" },
    summary: { type: "string" },
    reported_age: { type: ["string", "null"] },
    reported_occupation: { type: ["string", "null"] },
    bio_summary: { type: "string" },
    talking_points: { type: "array", items: { type: "string" } },
    notes: { type: "string" },
  },
  required: [
    "headline",
    "summary",
    "reported_age",
    "reported_occupation",
    "bio_summary",
    "talking_points",
    "notes",
  ],
  additionalProperties: false,
};

const CHAT_SYSTEM = `あなたはマッチングアプリの会話を分析する恋愛コミュニケーションのコーチ。
入力はマッチングアプリのトーク画面のスクリーンショット。時系列順に並んでいる。

読み取り方:
- 吹き出しの左右で話者を判定する。右側(または色付き)が相談者=self、左側が相手=partner。判別できない場合は文体と文脈から推定する。
- 表示されている時刻・日付から返信間隔を読み取る。
- 既読/未読、スタンプ、画像送信の有無も材料にする。

出力方針:
- interest_score は相手の「食いつき度数」。相手の返信文量、質問返しの有無、自己開示の深さ、返信速度、絵文字や感嘆符の熱量、話題を広げる意思から総合判定する。相手が事務的・短文・質問返しなしなら 40 未満、こちらの話題に乗って質問を返してくるなら 60 以上、日程やデートに前向きなら 80 以上。忖度せず辛口に採点する。
- metrics は「返信速度」「文量バランス」「質問返し」「感情表現」「主導権」の5項目固定。それぞれ根拠のあるスコアとコメントを付ける。
- timeline は主要なやりとりを時系列で最大12件。excerpt はスクショから読み取った実際の文言を短く引用する。interest はその時点での相手の食いつき度数。
- rewrites が最重要。self の発言のうち、明確に損をしているものを最大6件選び、「もっとこうすべきだった」を示す。original はスクショ上の実際の文言、issue は何がまずいか、improved はそのまま送れる具体的な日本語の代替文、reason は改善理由。抽象論ではなく、そのままコピペできる文面を書く。
- next_moves は今この状況から送るべき次の一手を2〜3案。トーン違い(軽め/踏み込む/日程打診 など)で出し分ける。

制約:
- 日本語で書く。断定を避けた曖昧な言い回しは使わない。
- スクショから読み取れない情報を捏造しない。読み取れない場合はその旨を summary に書く。
- 相手を貶める表現や、相手を操作・強要する助言はしない。改善対象は常に相談者自身の振る舞い。`;

const PHOTO_SYSTEM = `あなたはマッチングアプリのプロフィール写真を評価するフォトディレクター。
入力はプロフィール写真の画像。複数枚ある場合はプロフィール全体としての構成も評価する。

出力方針:
- interest_score は「その写真で右スワイプされる確率」を表す総合スコア。忖度せず辛口に採点する。
- metrics は「第一印象」「表情」「構図・画質」「服装・清潔感」「背景・シチュエーション」の5項目固定。それぞれ根拠のあるスコアとコメントを付ける。
- bad_points は具体的に指摘する(顔が小さい、逆光で肌が暗い、加工が強い、背景が生活感、集合写真で本人が不明 など)。
- retakes は撮り直し・差し替えの具体的な指示。title は一言、how は撮り方(場所・時間帯・画角・服装・表情)、reason は効果。そのまま実行できるレベルまで具体化する。

制約:
- 日本語で書く。
- 容姿そのものを侮辱しない。変えられる要素(構図・光・服装・表情・選定)に焦点を当てる。
- 人物の年齢・人種・健康状態などの属性を推定して評価材料にしない。`;

const PROFILE_SYSTEM = `あなたはマッチングアプリのプロフィール画面を要約するアシスタント。
入力はプロフィール画面のスクリーンショット。

読み取り方:
- reported_age・reported_occupation は、画面上に文字として表示されている自己申告の年齢・職業のみを読み取る。表示がなければ null にする。
- bio_summary は自己紹介文・趣味・価値観などのテキスト情報を要約する。
- talking_points は bio_summary から見つかる、会話のきっかけになりそうな具体的な話題を3〜6個挙げる。

制約:
- 日本語で書く。
- 顔写真や外見から年齢・人種・体型・健康状態などを推定して reported_age や他のフィールドに書かない。画面に文字で書かれていない属性は一切推定しない。
- 読み取れなかった情報を捏造せず、notes にその旨を書く。
- 相手の外見や属性そのものへの評価・侮辱は書かない。`;

const friendlyError = (err) => {
  const status = err?.status;
  if (status === 401 || status === 403) return "APIキーの設定を確認してください。";
  if (status === 413) return "画像の合計サイズが大きすぎます。枚数を減らしてください。";
  if (status === 429) return "混み合っています。少し待ってから再試行してください。";
  if (status >= 500) return "解析サービスが一時的に応答しません。再試行してください。";
  return "解析に失敗しました。画像を減らすか、時間をおいて再試行してください。";
};

const SYSTEM_BY_MODE = { chat: CHAT_SYSTEM, photo: PHOTO_SYSTEM, profile: PROFILE_SYSTEM };
const SCHEMA_BY_MODE = { chat: CHAT_SCHEMA, photo: PHOTO_SCHEMA, profile: PROFILE_SCHEMA };
const INSTRUCTION_BY_MODE = {
  chat: (n) => `上記${n}枚のスクリーンショットを時系列順の会話として読み、スキーマに従って分析結果を返して。`,
  photo: (n) => `上記${n}枚のプロフィール写真を評価し、スキーマに従って結果を返して。`,
  profile: (n) => `上記${n}枚のプロフィール画面を読み取り、スキーマに従って結果を返して。`,
};

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

export default async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!process.env.ANTHROPIC_API_KEY) {
    return json(500, { error: "ANTHROPIC_API_KEY が未設定です。" });
  }

  let payload;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "リクエストの形式が不正です。" });
  }

  const mode = MODES.includes(payload?.mode) ? payload.mode : "chat";
  const images = Array.isArray(payload?.images) ? payload.images : [];
  const context = typeof payload?.context === "string" ? payload.context.slice(0, 2000) : "";

  if (images.length === 0) return json(400, { error: "画像が1枚もありません。" });
  if (images.length > MAX_IMAGES) return json(400, { error: `画像は最大${MAX_IMAGES}枚までです。` });

  const blocks = [];
  for (const [i, image] of images.entries()) {
    const mediaType = image?.media_type;
    const data = image?.data;
    if (!ALLOWED_MEDIA_TYPES.includes(mediaType) || typeof data !== "string") {
      return json(400, { error: `${i + 1}枚目の画像形式に対応していません。` });
    }
    if (data.length * 0.75 > MAX_IMAGE_BYTES) {
      return json(400, { error: `${i + 1}枚目の画像が大きすぎます。` });
    }
    blocks.push({ type: "text", text: `--- ${i + 1}枚目 ---` });
    blocks.push({ type: "image", source: { type: "base64", media_type: mediaType, data } });
  }

  blocks.push({
    type: "text",
    text:
      INSTRUCTION_BY_MODE[mode](images.length) +
      (context ? `\n\n補足情報(相談者による申告):\n${context}` : ""),
  });

  const client = new Anthropic();
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      const send = (event) => controller.enqueue(encoder.encode(JSON.stringify(event) + "\n"));
      send({ type: "status", text: "画像を読み込み中…" });

      try {
        const run = client.messages.stream({
          model: MODEL,
          max_tokens: 32000,
          system: SYSTEM_BY_MODE[mode],
          thinking: { type: "adaptive" },
          output_config: {
            effort: "medium",
            format: { type: "json_schema", schema: SCHEMA_BY_MODE[mode] },
          },
          messages: [{ role: "user", content: blocks }],
        });

        let thinkingAnnounced = false;
        for await (const event of run) {
          if (event.type === "content_block_start" && event.content_block?.type === "thinking") {
            if (!thinkingAnnounced) {
              thinkingAnnounced = true;
              send({ type: "status", text: "会話の流れを読み解いています…" });
            }
          }
          if (event.type === "content_block_delta" && event.delta?.type === "text_delta") {
            send({ type: "delta", text: event.delta.text });
          }
        }

        const final = await run.finalMessage();
        if (final.stop_reason === "refusal") {
          send({ type: "error", message: "この内容は解析できませんでした。" });
        } else {
          send({ type: "done" });
        }
      } catch (err) {
        console.error("analyse failed", err);
        send({ type: "error", message: friendlyError(err) });
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      "content-type": "application/x-ndjson; charset=utf-8",
      "cache-control": "no-store",
    },
  });
};

export const config = { path: "/api/analyse" };
