-- docs/design.md 3節のDB設計をそのままSQL化したもの。
-- Supabaseプロジェクト作成後、SQL Editor またはCLI (`supabase db push`) で適用する。

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

-- Row Level Security: 自分の行しか読み書きできない
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
