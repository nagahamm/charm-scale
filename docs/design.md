# 詳細設計書

[requirements.md](./requirements.md) の要件に対する設計。ドメインモデルは DDD(ドメイン駆動設計)の考え方を軽量に取り入れ、業務上の関心事(User / Person / Analysis)を中心に据える。過剰な抽象化はしない([CLAUDE.md](../CLAUDE.md) YAGNI)。

## 1. 全体アーキテクチャ

```
app/ (Flutter)
  │
  ├── 認証 ──────────────────► Supabase Auth
  │                             - サインアップ/ログインのみ。DBへは直接書き込まない
  │
  └── AI解析 + 永続化 ───────► api/functions/analyse.mjs (Netlify Function)
                                - Claude API 呼び出し
                                - リクエストの Supabase JWT を検証し、本人確認と
                                  利用回数カウントに使う
                                - 解析結果を Service Role キーで Supabase に永続化
                                  (二重化構成、下記)
                                - 画像はここを通過するだけで保存しない(現状維持)
```

- **認証(サインアップ/ログイン)は Flutter から Supabase Auth に直接行う**。DBへの読み書きは行わないので、クライアントSDK + RLS だけで完結する。
- **解析結果の永続化は `analyse.mjs` が担う**(Flutter から Supabase DB へ直接は書き込まない)。理由:
  - AIの生出力をそのまま保存する「Rawログ」と、検証済みの正規化データを分ける二重化構成(下記)にするため、検証ロジック(Zod)をサーバー側に置く必要がある。Dartクライアントに同じ検証ロジックを重複実装したくない([CLAUDE.md](../CLAUDE.md) DRY)。
  - Rawログの書き込みは失敗を握りつぶしてよい非同期処理であり、正規化データの書き込みはリクエストを認証したサーバーが行う方が事故が起きにくい。
  - これにより `api/functions/analyse.mjs` は「Claude 呼び出し」に加えて「解析結果の永続化」も担う。[CLAUDE.md](../CLAUDE.md) のモジュール責務表・本ドキュメントの記述を更新する必要がある(既存の「Claude呼び出しのみ」という説明は本節の内容に置き換える)。
- 画像(スクリーンショット)はサーバーを通過するだけで、Supabase にも Netlify にも一切保存しない(Rawログにも画像は含めない。プライバシー制約は現状維持)。
- Supabase の Service Role キーはサーバー側(Netlify Functions の環境変数)だけで使う。アプリには渡さない(既存の「APIキーはここだけ」原則を Supabase キーにも適用する)。

### 1.1 解析結果の二重化構成(Rawログ + 正規化DB)

```
Claude のストリーミング応答が完了
        │
        ├─► ① Rawログとして非同期で保存(analysis_raw_logs、検証前の生JSON)
        │     失敗してもクライアントへの応答には影響させない
        │
        └─► ② Zod でスキーマ検証
              ├─ 成功 ─► 正規化テーブル群(analyses / analysis_metrics / … )へ保存
              └─ 失敗 ─► エラーログのみ(①でRawログは既に残っているため データは失われない)
```

- ① は「AIが実際に何を返したか」を後から追跡・再処理できるようにするための記録。クライアントへのストリーミング応答とは独立して行い、失敗してもユーザー体験に影響しない(fire-and-forget)。
- ② はアプリが実際に使うデータの整合性を保証するための検証。Claude の Structured Outputs(JSON Schema)による制約に加えて、サーバー側でもう一段 [Zod](https://zod.dev/) で検証してから正規化テーブルへ書く。スキーマは `api/functions/analyse.mjs` の既存の JSON Schema(CHAT_SCHEMA 等)と同じ形を Zod で定義する(二重定義になるが、「サーバーへ実際に送られてくる値を落ち着いて検証する」防御的な層として別物と考える)。
- 検証に失敗した場合、①のRawログは既に保存されているため、データそのものは失われない。正規化テーブルへの反映だけがスキップされる。

## 2. ドメインモデル

```
User (1) ── (N) Person ── (N) Analysis
```

- **User**: アプリのアカウント本人。Supabase Auth が発行する `auth.users` をそのまま使う(アプリ独自の users テーブルは持たない)。
- **Person**: User が管理する「相手」。User 以外の第三者の個人情報を含みうるため、User が削除すれば配下の Analysis も連鎖削除される。
- **Analysis**: 1回の解析結果。`mode`(chat/photo)ごとに、`api/functions/analyse.mjs` の既存レスポンススキーマ(CHAT_SCHEMA / PHOTO_SCHEMA)を正規化テーブル群に分解して保存する(3節)。分解前の生データは `analysis_raw_logs` に別途残す(1.1節)ので、正規化スキーマを将来変更しても過去の生データは失われない。

集計(全体的なフィードバック)や利用回数は、独立した集計テーブルを持たず `analyses` 系テーブル・`usage_counters` への都度クエリで導出する。専用の集計テーブルは、実際にパフォーマンス上の問題が出てから検討する(YAGNI)。

## 3. DB設計(Supabase / Postgres)

正規化の方針: 「全体的なフィードバック」(4.3節)で集計・検索する項目は列として分解する。`profile.attributes`(可変長のラベル・値のペア)のように形が決まっていないものは JSONB のまま持つ。単純な文字列リスト(`good_points` など)は子テーブルを作らず Postgres の配列型(`text[]`)で持つ(1列1テーブルの過剰な分解はしない、YAGNI)。

```sql
-- Person: User が管理する相手
create table persons (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  nickname    text not null,             -- User が自分でつけるニックネーム(相手の本名は保存しない)
  created_at  timestamptz not null default now()
);

-- Analysis: 1回の解析結果(正規化された中心テーブル)
create table analyses (
  id             uuid primary key default gen_random_uuid(),
  person_id      uuid not null references persons(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade, -- RLS判定用に非正規化
  mode           text not null check (mode in ('chat', 'photo')),
  headline       text not null,
  summary        text not null,
  interest_score int,                     -- chat/photo とも interest_score を持つ
  phase          text,                    -- chat のみ
  good_points    text[] not null default '{}',
  bad_points     text[] not null default '{}',
  created_at     timestamptz not null default now()
);

-- 項目別スコア(chatは5項目、photoは2項目。key はスキーマ上の英語キー、label は日本語ラベル)
create table analysis_metrics (
  id           uuid primary key default gen_random_uuid(),
  analysis_id  uuid not null references analyses(id) on delete cascade,
  key          text not null,
  label        text not null,
  score        int not null,
  comment      text not null
);

-- 会話の再現(chatのみ)
create table analysis_timeline_entries (
  id           uuid primary key default gen_random_uuid(),
  analysis_id  uuid not null references analyses(id) on delete cascade,
  position     int not null,
  speaker      text not null check (speaker in ('self', 'partner')),
  excerpt      text not null,
  interest     int not null,
  note         text not null
);

-- 添削(chatはtimeline_entryに、photoのbio_rewritesはanalysisに直接ぶら下がる)
create table analysis_rewrites (
  id                  uuid primary key default gen_random_uuid(),
  analysis_id         uuid not null references analyses(id) on delete cascade,
  timeline_entry_id   uuid references analysis_timeline_entries(id) on delete cascade,
  original            text,               -- photoのbio_rewritesのみ使用(chatはtimeline_entry.excerptと同じなので null)
  issue               text not null,
  improved_candidates text[] not null,
  reason              text not null
);

-- 次に送る返信案(chatのみ)
create table analysis_next_moves (
  id           uuid primary key default gen_random_uuid(),
  analysis_id  uuid not null references analyses(id) on delete cascade,
  label        text not null,
  message      text not null,
  aim          text not null
);

-- 相手のプロフィール(chatのみ、任意)
create table analysis_profiles (
  analysis_id          uuid primary key references analyses(id) on delete cascade,
  reported_age         text,
  reported_occupation  text,
  likes_count          text,
  bio_summary          text not null,
  notes                text not null,
  attributes           jsonb not null default '[]', -- [{label, value}, ...]
  tags                 text[] not null default '{}',
  talking_points       text[] not null default '{}'
);

-- 写真ごとの評価(photoのみ)
create table analysis_photos (
  id             uuid primary key default gen_random_uuid(),
  analysis_id    uuid not null references analyses(id) on delete cascade,
  position       int not null,
  category       text not null,
  score          int not null,
  comment        text not null,
  retake_title   text,
  retake_how     text,
  retake_reason  text
);

-- いいね数の目安(photoのみ、任意)
create table analysis_positioning (
  analysis_id  uuid primary key references analyses(id) on delete cascade,
  estimate     text not null,
  basis        text not null,
  source_url   text not null,
  disclaimer   text not null
);

-- Rawログ: 検証前のAI生出力をそのまま保存(画像は含めない)
create table analysis_raw_logs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  mode          text not null check (mode in ('chat', 'photo', 'draft_check')),
  raw_response  jsonb not null,
  created_at    timestamptz not null default now()
);

-- 利用回数カウント(日次)
create table usage_counters (
  user_id     uuid not null references auth.users(id) on delete cascade,
  day         date not null,
  count       integer not null default 0,
  primary key (user_id, day)
);

create index analyses_person_created_idx on analyses (person_id, created_at desc);
create index analysis_metrics_analysis_idx on analysis_metrics (analysis_id);
create index analysis_timeline_entries_analysis_idx on analysis_timeline_entries (analysis_id, position);
create index analysis_rewrites_analysis_idx on analysis_rewrites (analysis_id);
create index analysis_next_moves_analysis_idx on analysis_next_moves (analysis_id);
create index analysis_photos_analysis_idx on analysis_photos (analysis_id, position);
create index analysis_raw_logs_user_idx on analysis_raw_logs (user_id, created_at desc);
```

Row Level Security: すべてのテーブルで有効化する。`analyses` 以外の子テーブルは `user_id` 列を持たないため、`analyses` への参照を介したポリシーにする。

```sql
alter table persons enable row level security;
alter table analyses enable row level security;
alter table analysis_metrics enable row level security;
alter table analysis_timeline_entries enable row level security;
alter table analysis_rewrites enable row level security;
alter table analysis_next_moves enable row level security;
alter table analysis_profiles enable row level security;
alter table analysis_photos enable row level security;
alter table analysis_positioning enable row level security;
alter table analysis_raw_logs enable row level security;
alter table usage_counters enable row level security;

create policy "own persons" on persons
  for all using (auth.uid() = user_id);

create policy "own analyses" on analyses
  for all using (auth.uid() = user_id);

-- 子テーブル共通: 親の analyses.user_id で判定する
create policy "own analysis_metrics" on analysis_metrics
  for all using (exists (select 1 from analyses a where a.id = analysis_id and a.user_id = auth.uid()));
create policy "own analysis_timeline_entries" on analysis_timeline_entries
  for all using (exists (select 1 from analyses a where a.id = analysis_id and a.user_id = auth.uid()));
create policy "own analysis_rewrites" on analysis_rewrites
  for all using (exists (select 1 from analyses a where a.id = analysis_id and a.user_id = auth.uid()));
create policy "own analysis_next_moves" on analysis_next_moves
  for all using (exists (select 1 from analyses a where a.id = analysis_id and a.user_id = auth.uid()));
create policy "own analysis_profiles" on analysis_profiles
  for all using (exists (select 1 from analyses a where a.id = analysis_id and a.user_id = auth.uid()));
create policy "own analysis_photos" on analysis_photos
  for all using (exists (select 1 from analyses a where a.id = analysis_id and a.user_id = auth.uid()));
create policy "own analysis_positioning" on analysis_positioning
  for all using (exists (select 1 from analyses a where a.id = analysis_id and a.user_id = auth.uid()));

create policy "own raw logs (read only)" on analysis_raw_logs
  for select using (auth.uid() = user_id);
-- analysis_raw_logs・analyses系テーブルへの insert/update は
-- クライアントからは行わせず、analyse.mjs が Service Role キーで行う。
-- (RLSはSELECTのみ許可し、クライアントからの書き込みポリシーは作らない)

create policy "own usage" on usage_counters
  for select using (auth.uid() = user_id);
-- usage_counters への insert/update も Service Role(analyse.mjs)からのみ。
```

## 4. 機能ごとの実装方針

### 4.1 アカウント

- Supabase Auth のメール+パスワードと、標準対応の OAuth プロバイダ(Google, Apple)をそのまま使う。独自の認証基盤は実装しない。
- iOS では、他のソーシャルログインを提供する場合 Apple の審査ガイドラインにより Sign in with Apple が実質必須のため、Google と同時に対応する。
- **LINEログイン**: Supabase Auth に標準搭載されていない([参考](https://github.com/orgs/supabase/discussions/20178))。LINE 自体は OAuth2/OIDC に対応しているため、Supabase の [Custom OAuth/OIDC Providers](https://supabase.com/docs/guides/auth/custom-oauth-providers) 機能で個別に設定すれば対応できる。LINE Developers コンソールでのアプリ登録(本人の手作業)が前提になるため、別Issueで扱う。
- 新規登録数の上限は、サインアップ前に `select count(*) from auth.users` を Edge Function 等で確認するか、Supabase の招待制(invite-only)機能を使う。上限値は環境変数で管理し、コードにハードコードしない。

### 4.2 人別の履歴

- ホーム画面の入口に Person 選択(または新規作成)を追加する。分析実行時に `person_id` を紐づけて `analyses` に insert する。
- 履歴画面は `analyses` を `person_id` で絞り込み、`created_at` 降順で一覧表示する。
- 一覧の各行をタップして詳細(既存の ResultScreen)を表示する際、正規化テーブルに分解済みのデータを、既存の CHAT_SCHEMA / PHOTO_SCHEMA と同じ形の JSON に組み立て直して返す必要がある(Flutter側のモデル・パース処理を作り直さずに済むため)。Postgres の SQL関数(またはビュー)で `analysis_id` から JSON を再構成し、アプリはそれをそのまま `ChatResult.fromJson` / `PhotoResult.fromJson` に渡す。実装は analyse.mjs 側の永続化コードと合わせて次のIssueで詰める。

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
