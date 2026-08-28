# 詳細設計書

[requirements.md](./requirements.md) の要件に対する設計。ドメインモデルは DDD(ドメイン駆動設計)の考え方を軽量に取り入れ、業務上の関心事(User / Person / Analysis)を中心に据える。過剰な抽象化はしない([CLAUDE.md](../CLAUDE.md) YAGNI)。

## 1. 全体アーキテクチャ

```
app/ (Flutter)
  │
  ├── 認証・永続化 ──────────► Supabase (Postgres + Auth)
  │                             - users / persons / analyses
  │                             - Row Level Security で他ユーザーのデータに
  │                               アクセスできないようにする
  │
  └── AI解析 ───────────────► api/functions/analyse.mjs (Netlify Function)
                                - Claude API 呼び出しのみを担当
                                - 画像はここを通過するだけで保存しない(現状維持)
                                - リクエストヘッダーの Supabase JWT を検証し、
                                  本人確認と利用回数カウントに使う
```

- 画像(スクリーンショット)は Netlify Function を通過するだけで、Supabase にも Netlify にも保存しない。永続化するのは Claude が返した構造化結果(JSON)のみ。
- 認証と分析結果の保存は Flutter アプリから Supabase へ直接行う(Supabase の Auth / クライアントSDK + RLS)。Netlify Function を経由させない。これにより `analyse.mjs` の責務は「Claude 呼び出し」のみに保たれる([CLAUDE.md](../CLAUDE.md) のモジュール責務を維持)。
- `analyse.mjs` は解析の都度、Supabase の `usage_counters`(4.4節)を確認・更新するために Supabase の Service Role キーをサーバー側だけで使う(アプリには渡さない。既存の「APIキーはここだけ」原則を Supabase キーにも適用する)。

## 2. ドメインモデル

```
User (1) ── (N) Person ── (N) Analysis
```

- **User**: アプリのアカウント本人。Supabase Auth が発行する `auth.users` をそのまま使う(アプリ独自の users テーブルは持たない)。
- **Person**: User が管理する「相手」。User 以外の第三者の個人情報を含みうるため、User が削除すれば配下の Analysis も連鎖削除される。
- **Analysis**: 1回の解析結果。`mode`(chat/photo)と、`api/functions/analyse.mjs` が返した JSON をそのまま保存する。既存のレスポンススキーマ(CHAT_SCHEMA / PHOTO_SCHEMA)がそのままドメインの形になっているため、リレーショナルに分解しない(1 Analysis = 1 JSONB ドキュメント)。将来スキーマが変わっても、過去の Analysis の JSON 構造は保存時点のまま読み返せる。

集計(全体的なフィードバック)や利用回数は、独立したテーブルを持たず `analyses` / `usage_counters` への都度クエリで導出する。専用の集計テーブルは、実際にパフォーマンス上の問題が出てから検討する(YAGNI)。

## 3. DB設計(Supabase / Postgres)

```sql
-- Person: User が管理する相手
create table persons (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  nickname    text not null,             -- User が自分でつけるニックネーム(相手の本名は保存しない)
  created_at  timestamptz not null default now()
);

-- Analysis: 1回の解析結果
create table analyses (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references persons(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade, -- RLS判定用に非正規化
  mode        text not null check (mode in ('chat', 'photo')),
  result      jsonb not null,            -- analyse.mjs のレスポンスJSONをそのまま保存
  created_at  timestamptz not null default now()
);

-- 利用回数カウント(日次)
create table usage_counters (
  user_id     uuid not null references auth.users(id) on delete cascade,
  day         date not null,
  count       integer not null default 0,
  primary key (user_id, day)
);

-- Row Level Security: 自分の行しか読み書きできない
alter table persons enable row level security;
alter table analyses enable row level security;
alter table usage_counters enable row level security;

create policy "own persons" on persons
  for all using (auth.uid() = user_id);

create policy "own analyses" on analyses
  for all using (auth.uid() = user_id);

create policy "own usage" on usage_counters
  for select using (auth.uid() = user_id);
-- usage_counters への insert/update は Service Role(analyse.mjs)からのみ許可し、
-- クライアントからは書き込ませない。
```

インデックス: `analyses(person_id, created_at)` を作成し、Person 別の履歴を時系列で取得しやすくする。

```sql
create index analyses_person_created_idx on analyses (person_id, created_at desc);
```

## 4. 機能ごとの実装方針

### 4.1 アカウント

- Supabase Auth のメール+パスワード(または OTP)をそのまま使う。独自の認証基盤は実装しない。
- 新規登録数の上限は、サインアップ前に `select count(*) from auth.users` を Edge Function 等で確認するか、Supabase の招待制(invite-only)機能を使う。上限値は環境変数で管理し、コードにハードコードしない。

### 4.2 人別の履歴

- ホーム画面の入口に Person 選択(または新規作成)を追加する。分析実行時に `person_id` を紐づけて `analyses` に insert する。
- 履歴画面は `analyses` を `person_id` で絞り込み、`created_at` 降順で一覧表示する。一覧の各行をタップすると、既存の ResultScreen をそのまま(保存済みの `result` JSON から)再表示する。

### 4.3 全体的なフィードバック

- 特定の Person に紐づかない、User 全体のダッシュボード画面を追加する。
- 表示内容は `analyses.result` から項目別スコアの平均・推移を計算する(クライアント側で集計。専用の集計テーブルは持たない)。
- 個々の会話内容やメッセージ本文は出さず、スコアの傾向のみを見せる(要件定義 5節のプライバシー方針)。

### 4.4 利用制限

- `analyse.mjs` の冒頭で、リクエストの Supabase JWT からユーザーを特定し、`usage_counters` の当日カウントを確認する。上限超過なら 429 相当のエラーを返す(既存の `friendlyError` パターンを踏襲)。
- カウントの加算は解析が実際に完了した(ストリームが `done` で終わった)タイミングで行い、失敗した解析ではカウントしない。

## 5. 移行方針

- 既存のログイン不要な使い方(#1〜#6 で実装済みの範囲)は、アカウント導入後も「ログインせずに1回だけ試す」導線として残すかは要検討(要件定義に未確定事項として残す)。
- 段階的に導入する: まず Supabase Auth 導入 → Person/Analysis の保存 → 履歴画面 → 全体フィードバック → 利用制限、の順に Issue を分けて実装する(1 Issue = 1 コミット粒度の原則を維持)。
