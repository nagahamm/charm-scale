-- #14: 1日あたりの解析回数上限(docs/design.md 4.4節)。
-- 同一ユーザーの解析が同時に走っても取りこぼさないよう、当日カウントの加算を1文で原子的に行う。
-- Service Role(analyse.mjs)からのみ呼ぶ。

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
