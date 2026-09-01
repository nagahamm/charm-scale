-- #17: 新規登録数の上限(docs/design.md 4.1節)。
-- アプリは Supabase Auth に直接サインアップするため、強制はDB側で行う。

-- 上限値。運営が update で変更する1行だけのテーブル。
create table signup_policy (
  id         boolean primary key default true check (id),
  max_users  integer not null check (max_users >= 0),
  updated_at timestamptz not null default now()
);

insert into signup_policy (max_users) values (100);

alter table signup_policy enable row level security;
-- 読み書きは Service Role(signup.mjs)と security definer 関数からのみ。クライアント向けポリシーは作らない。

-- 受付可否の判定。トリガーと API の双方がこれを使う(判定を二重に書かない)。
-- signup_policy が空のときは null を返し、呼び出し側は登録を許可する(fail-open)。
create function signup_accepting()
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select (select count(*) from auth.users) < (select max_users from signup_policy where id);
$$;

revoke execute on function signup_accepting() from public, anon, authenticated;

create function enforce_signup_limit()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- signup_accepting() が null(設定が未投入)のときは条件が偽になり、登録を通す。
  if signup_accepting() is false then
    raise exception 'signup limit reached' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger enforce_signup_limit_before_insert
  before insert on auth.users
  for each row execute function enforce_signup_limit();
