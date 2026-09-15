-- #21: 自分の反省メモをPerson単位・メッセージ単位で残せるようにする(docs/design.md 2節・4.2節)。
-- いずれもAIが生成するデータ(nickname / analysis_timeline_entries.note)とは別管理。

alter table persons add column memo text not null default '';

-- 発言(timeline_entry)ごとの利用者メモ。1:1だが疎なデータなので、
-- 未記入の発言については行自体を作らない(空文字ではなく行の有無で判定する)。
create table timeline_entry_notes (
  timeline_entry_id  uuid primary key references analysis_timeline_entries(id) on delete cascade,
  note                text not null,
  updated_at          timestamptz not null default now()
);

create index timeline_entry_notes_entry_idx on timeline_entry_notes (timeline_entry_id);

alter table timeline_entry_notes enable row level security;

create policy "own timeline_entry_notes" on timeline_entry_notes
  for all using (
    exists (
      select 1 from analysis_timeline_entries e
      join analyses a on a.id = e.analysis_id
      where e.id = timeline_entry_id and a.user_id = auth.uid()
    )
  );
