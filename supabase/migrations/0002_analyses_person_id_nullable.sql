-- #12: 写真モードの Analysis は Person(相手)を持たない。person_id を nullable にし、
-- chat モードのみ必須になるよう check 制約で担保する。

alter table analyses
  alter column person_id drop not null;

alter table analyses
  add constraint analyses_person_id_required_for_chat
  check (person_id is not null or mode = 'photo');
