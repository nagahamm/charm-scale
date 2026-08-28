import Anthropic from "@anthropic-ai/sdk";

const MODEL = "claude-opus-5";
const MAX_IMAGES = 8;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ALLOWED_MEDIA_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"];
const MODES = ["chat", "photo"];
const MAX_PROFILE_IMAGES = 8;

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
    overall_impression_consistency: metricItem(),
  },
  required: ["first_impression", "overall_impression_consistency"],
  additionalProperties: false,
};

const PHOTO_CATEGORIES = ["portrait", "lifestyle", "scenery", "food", "pet", "other"];

const PHOTO_EVALUATION = {
  type: "object",
  properties: {
    category: { type: "string", enum: PHOTO_CATEGORIES },
    score: SCORE,
    comment: { type: "string" },
    retake: {
      type: ["object", "null"],
      properties: {
        title: { type: "string" },
        how: { type: "string" },
        reason: { type: "string" },
      },
      required: ["title", "how", "reason"],
      additionalProperties: false,
    },
  },
  required: ["category", "score", "comment", "retake"],
  additionalProperties: false,
};

// 男性会員のいいね数のおおまかな目安。アプリ内部の実データではなく、公開されている調査記事を根拠にした一般的な目安。
const LIKES_POSITIONING_SOURCE_URL = "https://laskoi.jp/blog/post/numberoflikes-datingapp";
const LIKES_POSITIONING_BANDS =
  "男性の目安(20代を想定した一般的な調査データ): 〜5件=改善の余地が大きい / 6〜15件=平均的なレンジ / 16〜30件=平均より多め / 31件以上=上位10%程度の可能性";

const PROFILE_INFO = {
  type: ["object", "null"],
  properties: {
    reported_age: { type: ["string", "null"] },
    reported_occupation: { type: ["string", "null"] },
    likes_count: { type: ["string", "null"] },
    bio_summary: { type: "string" },
    attributes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          label: { type: "string" },
          value: { type: "string" },
        },
        required: ["label", "value"],
        additionalProperties: false,
      },
    },
    tags: { type: "array", items: { type: "string" } },
    talking_points: { type: "array", items: { type: "string" } },
    notes: { type: "string" },
  },
  required: [
    "reported_age",
    "reported_occupation",
    "likes_count",
    "bio_summary",
    "attributes",
    "tags",
    "talking_points",
    "notes",
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
    profile: PROFILE_INFO,
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
          rewrite: {
            type: ["object", "null"],
            properties: {
              issue: { type: "string" },
              improved: { type: "array", items: { type: "string" }, minItems: 2, maxItems: 3 },
              reason: { type: "string" },
            },
            required: ["issue", "improved", "reason"],
            additionalProperties: false,
          },
        },
        required: ["speaker", "excerpt", "interest", "note", "rewrite"],
        additionalProperties: false,
      },
    },
    good_points: { type: "array", items: { type: "string" } },
    bad_points: { type: "array", items: { type: "string" } },
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
    "profile",
    "metrics",
    "timeline",
    "good_points",
    "bad_points",
    "next_moves",
  ],
  additionalProperties: false,
};

const POSITIONING = {
  type: ["object", "null"],
  properties: {
    estimate: { type: "string" },
    basis: { type: "string" },
    source_url: { type: "string" },
    disclaimer: { type: "string" },
  },
  required: ["estimate", "basis", "source_url", "disclaimer"],
  additionalProperties: false,
};

const PHOTO_SCHEMA = {
  type: "object",
  properties: {
    headline: { type: "string" },
    interest_score: SCORE,
    summary: { type: "string" },
    metrics: PHOTO_METRICS,
    photos: { type: "array", items: PHOTO_EVALUATION },
    bio_rewrites: {
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
    positioning: POSITIONING,
  },
  required: [
    "headline",
    "interest_score",
    "summary",
    "metrics",
    "photos",
    "bio_rewrites",
    "positioning",
  ],
  additionalProperties: false,
};

const CHAT_SYSTEM = `あなたはマッチングアプリの会話を分析する恋愛コミュニケーションのコーチ。
入力はマッチングアプリのトーク画面のスクリーンショット。加えて、相手のプロフィール画面のスクリーンショットが補足として渡されることがある。

読み取り方(会話):
- 吹き出しの左右で話者を判定する。右側(または色付き)が相談者=self、左側が相手=partner。判別できない場合は文体と文脈から推定する。
- スクショが複数枚ある場合、アップロードされた順序をそのまま時系列とは信用しない。日付の区切り表示(例: 「8/21(金)」「昨日」「今日」)・時刻・会話の受け答えの整合性(質問とその返答が対応しているか)から実際の時系列を判断し、正しい順序に並べ替えてから分析する。
- 表示されている時刻・日付から返信間隔を読み取る。
- 既読/未読、スタンプ、画像送信の有無も材料にする。
- 相手からの返信が1件もない(自分の発言だけが続いている)場合も、その旨を summary に明記した上で分析する。存在しないやりとりを作らない。

読み取り方(プロフィール、渡されている場合のみ):
- マッチングアプリのプロフィール画面は、名前・年齢・エリア・いいね数などのヘッダー情報、自己紹介文、「基本情報」「学歴・職種・外見」「恋愛・結婚について」「性格・趣味・生活」のようなラベル付きの項目一覧(例: 血液型・居住地・出身地・身長・体型・学歴・結婚歴・子供の有無・結婚に対する意思・出会うまでの希望・16タイプ診断・同居人・休日 など)、興味関心タグの一覧、といった構成で表示されることが多い。存在する項目はできる限りすべて読み取る。
- reported_age・reported_occupation・likes_count は、画面上に文字として表示されている自己申告の年齢・職業・いいね数のみを読み取る。表示がなければ null にする。
- attributes には、ラベル付きの項目一覧を見つけた順に { label, value } でそのまま列挙する(例: {label: "血液型", value: "A型"})。reported_age など専用フィールドに転記した項目も、attributes には省略せず含める。未設定・空欄の項目は含めない。
- tags には、興味関心タグ一覧(タグ名のみ、カテゴリ名は不要)を列挙する。
- bio_summary は自己紹介文を要約する。
- talking_points は自己紹介文・attributes・tags から見つかる、会話のきっかけになりそうな具体的な話題を3〜6個挙げる。
- プロフィール写真の部分がグレーアウトして写っていないことがある(アプリ側のスクリーンショット検知による)。これは想定内の見え方であり、画像が壊れているわけではないので気にせず、写真以外のテキスト情報から読み取れることに集中する。
- プロフィール画像が渡されていない場合、profile は null にする。

出力方針:
- interest_score は相手の「食いつき度数」。相手の返信文量、質問返しの有無、自己開示の深さ、返信速度、絵文字や感嘆符の熱量、話題を広げる意思から総合判定する。相手が事務的・短文・質問返しなしなら 40 未満、こちらの話題に乗って質問を返してくるなら 60 以上、日程やデートに前向きなら 80 以上。忖度せず辛口に採点する。
- metrics は「返信速度」「文量バランス」「質問返し」「感情表現」「主導権」の5項目固定。それぞれ根拠のあるスコアとコメントを付ける。各項目は次の観点を踏まえて採点する(コメント中で理論名を引用する必要はないが、判断の軸として使う):
  - 返信速度: 知覚された応答性(Perceived Partner Responsiveness)。相手が自分の発言に対してどれだけ迅速・的確に反応しているかは、関心の強さと相関する。
  - 文量バランス: 社会的浸透理論(Social Penetration Theory)における自己開示の返報性。自己開示の深さ・量が双方で釣り合っているかを見る。
  - 質問返し: 会話における質問の効果に関する知見(相手への質問は好意度を高めるという研究)。質問を返しているかどうかは関与度の指標になる。
  - 感情表現: ゴットマンの「つながりの申し出(bids for connection)」理論。相槌・絵文字・感嘆符などの情緒的反応は、相手からの申し出にどれだけ応えているかを表す。
  - 主導権: 同理論における「相手に向き合う(turning toward)」応答パターン。話題の提案・誘いなど、関係を前に進める行動を自ら取っているかを見る。
- timeline は主要なやりとりを時系列で最大12件。excerpt はスクショから読み取った実際の文言を短く引用する。interest はその時点での相手の食いつき度数。アプリ上で実際にやりとりされた吹き出しをそのまま再現できるようにするデータなので、順序と話者の左右を正確にする。
- rewrite が最重要。timeline のうち self の発言で、明確に損をしているものを最大6件選び、その entry の rewrite に「もっとこうすべきだった」を入れる。issue は何がまずいか、improved はそのまま送れる具体的な日本語の代替文を2〜3件(トーンや切り口を変える。似た言い回しの言い換えに留めない)、reason は改善理由。抽象論ではなく、そのままコピペできる文面を書く。それ以外の entry(partner の発言、問題のない self の発言)は rewrite を null にする。
- next_moves は今この状況から送るべき次の一手を2〜3案。トーン違い(軽め/踏み込む/日程打診 など)で出し分ける。プロフィールの talking_points に自然に絡められる話題があれば積極的に使う(無理にこじつけない)。

制約:
- 日本語で書く。断定を避けた曖昧な言い回しは使わない。
- スクショから読み取れない情報を捏造しない。読み取れない場合はその旨を summary(プロフィールについては profile.notes)に書く。
- attributes のラベル・値は画面表示のまま書き写す。意訳・言い換え・単位の変換をしない。
- 顔写真や外見から年齢・人種・体型・健康状態などを推定して reported_age や他のフィールドに書かない。画面に文字で書かれていない属性は一切推定しない。
- 相手を貶める表現や、相手を操作・強要する助言はしない。改善対象は常に相談者自身の振る舞い。`;

const PHOTO_SYSTEM = `あなたはマッチングアプリのプロフィール写真とプロフィール文を評価するフォトディレクター兼コーチ。
入力は評価対象の写真の画像。1枚目が「メイン写真」(プロフィールの一覧やマッチング画面で最初に表示される写真)、2枚目以降が「サブ写真」。加えて、相談者自身のプロフィール画面のスクリーンショットが補足として渡されることがある。

読み取り方(プロフィール、渡されている場合のみ):
- 自己紹介文をできるだけそのまま読み取る(添削の元データになるため要約しない)。
- 画面に文字として表示されているいいね数(または「マッチ数」)があれば読み取る。表示がなければ利用しない。
- プロフィール写真部分がスクリーンショット検知でグレーアウトしていることがあるが、想定内の見え方なので気にしない。

出力方針:
- interest_score は写真全体で「右スワイプされる確率」を表す総合スコア。忖度せず辛口に採点する。
- metrics は「第一印象」「全体印象の一貫性」の2項目固定。「第一印象」は写真セット全体を見た瞬間の印象。「全体印象の一貫性」は、複数の写真同士、また写真とプロフィール文(渡されている場合)が矛盾なく一貫した好印象を作れているかを見る。ちぐはぐさ(写真の雰囲気とプロフィール文のトーンが合っていない、写真ごとに別人のように見える など)は信頼感を下げるため低く採点する。
- photos は渡された写真と同じ枚数・同じ順序で1件ずつ返す(順序を入れ替えない)。写真ごとに:
  - category は写真に写っているものから判定する。人物がメインに写る一般的なプロフィール写真は "portrait"、人物+行動や場所が写るものは "lifestyle"、人物が写らない風景は "scenery"、食事は "food"、ペットは "pet"、それ以外は "other"。
  - score と comment は category に応じた基準で評価する。portrait/lifestyle は表情・構図・光・服装・清潔感など。scenery/food/pet/other は、構図やセンスの良さ、プロフィール写真としての適切さ(メニュー表や書類のスクショのような不適切なものでないか)、その人の興味関心が伝わるかを見る。1枚目(メイン写真)は特に、顔がはっきり見えるか・第一印象の良さを重視して厳しめに採点する。
  - retake は撮り直し・差し替えが必要な場合のみ具体的な指示を入れる(title は一言、how は撮り方や差し替え案、reason は効果)。十分に良ければ null にする。
- bio_rewrites はプロフィール文が渡されている場合のみ。自己紹介文のうち、もったいない・伝わりにくい箇所を最大4件選び、原文(original)→問題点(issue)→改善文(improved)→理由(reason)の形で添削する。improved はそのままプロフィールに貼り付けられる具体的な日本語にする。プロフィール文が渡されていなければ空配列にする。
- positioning はいいね数が読み取れた場合のみ。アプリ内部の実データは持っていないため、以下の一般的な調査データに基づく大まかな目安として estimate・basis を書き、disclaimer に「実際のアプリ内順位ではなく、公開データに基づくAIによるおおよその目安」である旨を明記し、source_url に参照元をそのまま入れる。いいね数が読み取れない場合は null にする。
  - 参照元URL: ${LIKES_POSITIONING_SOURCE_URL}
  - 目安: ${LIKES_POSITIONING_BANDS}

制約:
- 日本語で書く。
- 容姿そのものを侮辱しない。変えられる要素(構図・光・服装・表情・選定・文章)に焦点を当てる。
- 人物の年齢・人種・健康状態などの属性を推定して評価材料にしない。
- positioning は断定しない。あくまで目安であることが伝わる書き方にする。`;

const friendlyError = (err) => {
  const status = err?.status;
  if (status === 401 || status === 403) return "APIキーの設定を確認してください。";
  if (status === 413) return "画像の合計サイズが大きすぎます。枚数を減らしてください。";
  if (status === 429) return "混み合っています。少し待ってから再試行してください。";
  if (status >= 500) return "解析サービスが一時的に応答しません。再試行してください。";
  return "解析に失敗しました。画像を減らすか、時間をおいて再試行してください。";
};

const SYSTEM_BY_MODE = { chat: CHAT_SYSTEM, photo: PHOTO_SYSTEM };
const SCHEMA_BY_MODE = { chat: CHAT_SCHEMA, photo: PHOTO_SCHEMA };

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
  const profileImages = Array.isArray(payload?.profile_images) ? payload.profile_images : [];
  const context = typeof payload?.context === "string" ? payload.context.slice(0, 2000) : "";

  const buildImageBlocks = (imgs, { max, label, required }) => {
    if (imgs.length === 0 && required) return { error: `${label}の画像が1枚もありません。` };
    if (imgs.length > max) return { error: `${label}は最大${max}枚までです。` };
    const blocks = [];
    for (const [i, image] of imgs.entries()) {
      const mediaType = image?.media_type;
      const data = image?.data;
      if (!ALLOWED_MEDIA_TYPES.includes(mediaType) || typeof data !== "string") {
        return { error: `${label}${i + 1}枚目の画像形式に対応していません。` };
      }
      if (data.length * 0.75 > MAX_IMAGE_BYTES) {
        return { error: `${label}${i + 1}枚目の画像が大きすぎます。` };
      }
      blocks.push({ type: "text", text: label ? `--- ${label} ${i + 1}枚目 ---` : `--- ${i + 1}枚目 ---` });
      blocks.push({ type: "image", source: { type: "base64", media_type: mediaType, data } });
    }
    return { blocks };
  };

  const blocks = [];
  let instruction;

  if (mode === "chat") {
    const chatResult = buildImageBlocks(images, { max: MAX_IMAGES, label: "会話スクリーンショット", required: true });
    if (chatResult.error) return json(400, { error: chatResult.error });
    const profileResult = buildImageBlocks(profileImages, {
      max: MAX_PROFILE_IMAGES,
      label: "プロフィールスクリーンショット",
      required: false,
    });
    if (profileResult.error) return json(400, { error: profileResult.error });

    blocks.push(...chatResult.blocks, ...profileResult.blocks);
    instruction =
      `上記${images.length}枚の会話スクリーンショットを時系列順の会話として読み、` +
      (profileImages.length > 0 ? `プロフィール${profileImages.length}枚も参考にしつつ、` : "") +
      `スキーマに従って分析結果を返して。`;
  } else {
    const photoResult = buildImageBlocks(images, { max: MAX_IMAGES, label: "", required: true });
    if (photoResult.error) return json(400, { error: photoResult.error });
    const profileResult = buildImageBlocks(profileImages, {
      max: MAX_PROFILE_IMAGES,
      label: "プロフィール画面",
      required: false,
    });
    if (profileResult.error) return json(400, { error: profileResult.error });

    blocks.push(...photoResult.blocks, ...profileResult.blocks);
    instruction =
      `上記${images.length}枚のプロフィール写真を評価し、` +
      (profileImages.length > 0 ? `プロフィール画面${profileImages.length}枚も参考にしつつ、` : "") +
      `スキーマに従って結果を返して。`;
  }

  blocks.push({
    type: "text",
    text: instruction + (context ? `\n\n補足情報(相談者による申告):\n${context}` : ""),
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
