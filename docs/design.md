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
User (1) ── (N) Person ── (N) Analysis (mode = chat)
User (1) ─────────────────(N) Analysis (mode = photo)
```

- **User**: アプリのアカウント本人。Supabase Auth が発行する `auth.users` をそのまま使う(アプリ独自の users テーブルは持たない)。
- **Person**: User が管理する「相手」。会話モード(chat)は特定の相手とのやり取りなので Person に紐づく。写真モード(photo)は相談者自身のプロフィール写真の評価であり、相手は存在しないため Person を持たない。User 以外の第三者の個人情報を含みうるため、User が削除すれば配下の Analysis も連鎖削除される。
- **Analysis**: 1回の解析結果。`mode`(chat/photo)ごとに、`api/functions/analyse.mjs` の既存レスポンススキーマ(CHAT_SCHEMA / PHOTO_SCHEMA)を正規化テーブル群に分解して保存する(3節)。`person_id` は chat のみ必須、photo は null。分解前の生データは `analysis_raw_logs` に別途残す(1.1節)ので、正規化スキーマを将来変更しても過去の生データは失われない。

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
  person_id      uuid references persons(id) on delete cascade, -- chatのみ必須。photoは相手がいないためnull
  user_id        uuid not null references auth.users(id) on delete cascade, -- RLS判定用に非正規化
  mode           text not null check (mode in ('chat', 'photo')),
  headline       text not null,
  summary        text not null,
  interest_score int,                     -- chat/photo とも interest_score を持つ
  phase          text,                    -- chat のみ
  good_points    text[] not null default '{}',
  bad_points     text[] not null default '{}',
  created_at     timestamptz not null default now(),
  check (person_id is not null or mode = 'photo')
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

-- 当日カウントの加算(0003_increment_usage_counter.sql)。
-- 同一ユーザーの解析が同時に走っても取りこぼさないよう、1文で原子的に加算する。
create function increment_usage_counter(p_user_id uuid, p_day date)
returns integer
language sql
security definer
set search_path = public
as $$
  insert into usage_counters (user_id, day, count)
  values (p_user_id, p_day, 1)
  on conflict (user_id, day) do update set count = usage_counters.count + 1
  returning count;
$$;
revoke execute on function increment_usage_counter(uuid, date) from public, anon, authenticated;

-- 新規登録数の上限(0004_signup_limit.sql)。上限値は運営が update する1行だけのテーブルに置く。
create table signup_policy (
  id         boolean primary key default true check (id),
  max_users  integer not null check (max_users >= 0),
  updated_at timestamptz not null default now()
);

-- 受付可否の判定。auth.users の before insert トリガーと /api/signup-status の双方がこれを使う。
-- signup_policy が空なら null を返し、呼び出し側は登録を許可する(fail-open)。
create function signup_accepting()
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select (select count(*) from auth.users) < (select max_users from signup_policy where id);
$$;
```

## 4. 機能ごとの実装方針

### 4.1 アカウント

- Supabase Auth のメール+パスワードと、標準対応の OAuth プロバイダ(Google, Apple)をそのまま使う。独自の認証基盤は実装しない。
- iOS では、他のソーシャルログインを提供する場合 Apple の審査ガイドラインにより Sign in with Apple が実質必須のため、Google と同時に対応する。LINEログインは扱わない(要件定義 6節)。
- **新規登録数の上限**:
  - 強制はDB側で行う。アプリは Supabase Auth へ直接サインアップする(1節)ため、アプリやAPIでのチェックだけでは anon キーを使って回避できてしまう。`auth.users` への `before insert` トリガーで、既存ユーザー数が上限に達していれば例外を投げて登録を拒否する。
  - 上限値はシングルトンの設定テーブル `signup_policy.max_users` に置く。トリガーはサーバーの環境変数を読めないため、ここだけ環境変数ではなくDBに置き、トリガーとAPIが同じ値を参照する(値の二重管理を避ける)。運営は1行の `update` で変更する。
  - 受付可否の判定は Postgres 関数 `signup_accepting()` に集約し、トリガーとAPIの双方がこれを呼ぶ(判定ロジックを二重に書かない)。
  - 案内のために `GET /api/signup-status` を追加する(`api/functions/signup.mjs`)。アカウントを持たない利用者が呼ぶため認証は不要。返すのは `{ accepting }` のみで、現在のユーザー数や上限値は返さない(外部に晒す必要がない)。
  - ログイン画面は起動時にこれを見て、受付停止中は新規登録の導線を止めて案内を出す。既存アカウントのログイン(メール・OAuth)は止めない。
  - 設定が未投入(`signup_policy` が空)・APIの確認に失敗した場合は登録を許可する(fail-open)。締め出しの事故を避けるため、上限は「増えすぎを止める」目的に限る。

### 4.2 人別の履歴

対象は会話モードのみ(写真モードは Person を持たないため、この節の対象外。1〜2節参照)。

- ホーム画面(会話モード)の入口に Person 選択(または新規作成)を追加する。分析実行時に `person_id` を紐づけて `analyses` に insert する(既存の `analyse.mjs` の永続化ロジックに実装済み)。
- Person の一覧・作成・削除、および Person に紐づく Analysis 一覧・詳細の取得は、`api/functions/analyses.mjs` という新しい Netlify Function(`/api/analyses`)で行う。`analyse.mjs` は「Claude 呼び出し+保存(書き込み専用)」に責務を絞り、履歴の読み出し・Person管理は別ファイルに分ける([CLAUDE.md](../CLAUDE.md) SOLID)。Supabase Service Role キーへのアクセス自体は `persistence.mjs` の `getServiceClient`/`verifyUser` を共通で再利用し、キーを直接読むファイルを増やさない。
- エンドポイント設計(すべて `Authorization: Bearer <JWT>` 必須。無ければ401):
  - `GET /api/analyses?resource=persons` — Person一覧。各 Person に、埋め込みクエリで取得した直近1件の Analysis 概要(headline / interest_score / phase / created_at)を添えて返す(一覧画面でのカード表示用)。
  - `POST /api/analyses?resource=persons` — Person作成。body: `{ nickname }`。
  - `DELETE /api/analyses?resource=persons&person_id=...` — Person削除(`analyses` 以下は外部キーの `on delete cascade` で連鎖削除される)。
  - `GET /api/analyses?resource=list&person_id=...` — その Person の Analysis 一覧(id / headline / interest_score / phase / created_at)を `created_at` 降順で返す。
  - `GET /api/analyses?resource=detail&analysis_id=...` — 正規化テーブル群(analyses / analysis_metrics / analysis_timeline_entries / analysis_rewrites / analysis_next_moves / analysis_profiles)から、既存の CHAT_SCHEMA と同じ形の JSON を組み立てて返す。Flutter はこれをそのまま `ChatResult.fromJson` に渡せる(モデル・パース処理を作り直さない)。
  - すべてのクエリで `user_id = 該当ユーザー` を明示的に条件へ含める(Service Role キーはRLSを無視するため、アプリケーション側で必ず絞り込む)。
- **食いつき度数の推移グラフ**: `GET …?resource=list` が既に返している `interest_score` / `created_at` をそのまま使い、API は変更しない。`PersonHistoryScreen` が `created_at` の昇順に整列して `TrendChart` に渡す(レスポンスの並び順に依存しない)。`TrendChart` は1回の分析内の `timeline` の推移にも、分析をまたいだ推移にも使うため、`List<int>` を受け取る汎用の折れ線部品とする(部品はロジックを持たない、という責務に合わせる)。
- **続きのスクショで分析を更新する**: 導線は履歴画面に置き、分析画面は `HomeScreen` を「相手固定・会話モード固定」で再利用する(画像選択UIを二重に作らない、DRY)。直前の分析の要約は既存の `resource=detail` から取得し、`POST /api/analyse` の `previous_summary`(chat モードのみ、2000文字で切り詰め)として渡す。利用者申告の `context` とは別フィールドにして、プロンプトでも「このアプリが以前生成した要約」と位置づけを明示する(出所を混ぜない)。スクショに写っていない過去のやり取りは要約で補うが、スクショから読み取れる事実を優先させる。解析結果は既存の永続化経路でその相手の新しい Analysis として保存されるため、保存側の変更は不要。
- JSON の組み立ては Postgres の関数/ビューではなく、`analyses.mjs` 内の Node.js コードで行う(複数テーブルへの問い合わせ結果をJSにそのまま組み立てるだけなので、PL/pgSQLを新たに書く必要性が薄い。KISS)。

### 4.3 全体的なフィードバック

- 特定の Person に紐づかない、User 全体のダッシュボード画面を追加する。
- 表示内容は `analyses.result` から項目別スコアの平均・推移を計算する(クライアント側で集計。専用の集計テーブルは持たない)。
- 個々の会話内容やメッセージ本文は出さず、スコアの傾向のみを見せる(要件定義 5節のプライバシー方針)。

### 4.4 利用制限

- **上限値**: 環境変数 `DAILY_ANALYSIS_LIMIT`(未設定・不正値のときのデフォルトは20)。コードにハードコードしない(4.1節の新規登録上限と同じ方針)。`0` を指定すると認証済みリクエストの解析を全面的に止められる。
- **日付の境界**: 日本時間(UTC+9)の暦日。利用者が日本在住である前提で、UTC の日付境界(日本時間の午前9時)でリセットされる不自然さを避ける。`usage_counters.day` にはこの JST 基準の日付を入れる。
- **カウント対象**: chat / photo / draft_check の全モード。いずれも Claude 呼び出しが発生し、コストは同じように積み上がるため、モードごとに枠を分けない(YAGNI)。
- **判定と加算の位置**:
  - 判定は `analyse.mjs` の入力バリデーション後・Claude 呼び出し前。`usage_counters` の当日カウントを読み、上限以上なら HTTP 429 と `{ error }` を返す。アプリ側は既存の非200レスポンス処理(`AnalysisApiService._extractErrorMessage`)でそのままメッセージを表示できるため、アプリの変更は不要。
  - 加算はストリームが `done` で終わったタイミング(永続化と同じ位置)。Claude 呼び出しに失敗した解析は消費しない。加算に失敗しても、既にクライアントへ結果を返した後なので握りつぶしてログのみ残す(1.1節の Rawログと同じ fire-and-forget)。
  - 判定から加算までの間に別リクエストが走ると上限を1回分超えうるが、上限はコスト制御の目安であり厳密なトランザクション整合性は求めない(KISS)。加算自体は取りこぼさないよう Postgres 側の関数で原子的に行う(3節 `increment_usage_counter`)。
- **実装の置き場所**: `usage_counters` への読み書きは `persistence.mjs`(Supabase アクセスの集約先)に置き、`analyse.mjs` はその判定結果を使うだけにする。Service Role キーを直接読むファイルを増やさない。
- **匿名リクエスト**: Supabase 未設定・Authorization ヘッダー無しの場合はユーザーを特定できないため制限をかけない(従来のステートレスな挙動を維持)。アプリは `AuthGate` でログイン必須のため、実運用のリクエストは必ず JWT を伴う。

## 5. 移行方針

- 既存のログイン不要な使い方(#1〜#6 で実装済みの範囲)は、アカウント導入後も「ログインせずに1回だけ試す」導線として残すかは要検討(要件定義に未確定事項として残す)。
- 段階的に導入する: まず Supabase Auth 導入 → Person/Analysis の保存 → 履歴画面 → 全体フィードバック → 利用制限、の順に Issue を分けて実装する(1 Issue = 1 コミット粒度の原則を維持)。
