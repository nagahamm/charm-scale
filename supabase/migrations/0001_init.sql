-- docs/design.md 3節のDB設計をそのままSQL化したもの。
-- Supabaseプロジェクト作成後、SQL Editor またはCLI (`supabase db push`) で適用する。

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

create index analyses_person_created_idx on analyses (person_id, created_at desc);

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
-- usage_counters への insert/update はクライアントからは行わせず、
-- analyse.mjs が Service Role キーで行う(RLSをバイパスする)。
-- そのため insert/update 用のポリシーはここでは作らない。
