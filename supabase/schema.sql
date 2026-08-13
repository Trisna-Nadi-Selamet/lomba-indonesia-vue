-- Lomba Indonesia 17 Agustus - Supabase schema
-- Jalankan file ini di Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'Umum',
  date date not null,
  start_time time not null,
  location text not null,
  address text not null default '',
  quota integer not null default 20 check (quota > 0),
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- Jika tabel events sudah pernah dibuat sebelum fitur alamat ditambahkan:
alter table public.events add column if not exists address text not null default '';

create table if not exists public.organizers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  role text not null,
  phone text,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  group_name text not null,
  phone text,
  created_at timestamptz not null default now()
);

create table if not exists public.participants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  group_name text not null default '-',
  age integer,
  address text not null default '-',
  event_id uuid not null references public.events(id) on delete cascade,
  registered_at timestamptz not null default now()
);

create index if not exists idx_participants_event_id on public.participants(event_id);
create index if not exists idx_participants_registered_at on public.participants(registered_at desc);
create index if not exists idx_participants_name on public.participants using gin (to_tsvector('simple', name));
create index if not exists idx_events_date_time on public.events(date, start_time);

alter table public.events enable row level security;
alter table public.organizers enable row level security;
alter table public.members enable row level security;
alter table public.participants enable row level security;

-- Public can see the public event/team data.
drop policy if exists "events public read" on public.events;
create policy "events public read" on public.events for select using (true);

drop policy if exists "organizers public read" on public.organizers;
create policy "organizers public read" on public.organizers for select using (true);

drop policy if exists "members public read" on public.members;
create policy "members public read" on public.members for select using (true);

-- Only authenticated admin users can manage master data.
drop policy if exists "events authenticated insert" on public.events;
create policy "events authenticated insert" on public.events for insert to authenticated with check (true);
drop policy if exists "events authenticated update" on public.events;
create policy "events authenticated update" on public.events for update to authenticated using (true) with check (true);
drop policy if exists "events authenticated delete" on public.events;
create policy "events authenticated delete" on public.events for delete to authenticated using (true);

drop policy if exists "organizers authenticated all" on public.organizers;
create policy "organizers authenticated all" on public.organizers for all to authenticated using (true) with check (true);

drop policy if exists "members authenticated all" on public.members;
create policy "members authenticated all" on public.members for all to authenticated using (true) with check (true);

-- Participant rows are private to logged-in admins.
drop policy if exists "participants authenticated select" on public.participants;
create policy "participants authenticated select" on public.participants for select to authenticated using (true);
drop policy if exists "participants authenticated insert" on public.participants;
create policy "participants authenticated insert" on public.participants for insert to authenticated with check (true);
drop policy if exists "participants authenticated delete" on public.participants;
create policy "participants authenticated delete" on public.participants for delete to authenticated using (true);

-- Public registration is done through this atomic function so quota cannot be exceeded
-- by two simultaneous registrations.
create or replace function public.register_participant(
  p_name text,
  p_phone text,
  p_group_name text,
  p_age integer,
  p_address text,
  p_event_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.events%rowtype;
  v_count integer;
  v_id uuid;
begin
  if trim(coalesce(p_name,'')) = '' or trim(coalesce(p_phone,'')) = '' then
    raise exception 'Nama dan nomor HP wajib diisi';
  end if;

  select * into v_event from public.events where id = p_event_id for update;
  if not found then raise exception 'Lomba tidak ditemukan'; end if;
  if v_event.status <> 'open' then raise exception 'Pendaftaran lomba sudah ditutup'; end if;

  select count(*) into v_count from public.participants where event_id = p_event_id;
  if v_count >= v_event.quota then raise exception 'Kuota lomba sudah penuh'; end if;

  insert into public.participants(name, phone, group_name, age, address, event_id)
  values (
    trim(p_name), trim(p_phone), coalesce(nullif(trim(p_group_name),''), '-'),
    p_age, coalesce(nullif(trim(p_address),''), '-'), p_event_id
  ) returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.register_participant(text,text,text,integer,text,uuid) to anon, authenticated;


-- Public-safe count only: exposes how many people registered, not their names/phones.
create or replace function public.get_event_counts()
returns table(event_id uuid, participant_count bigint)
language sql
security definer
set search_path = public
as $$
  select e.id, count(p.id)::bigint
  from public.events e
  left join public.participants p on p.event_id = e.id
  group by e.id;
$$;

grant execute on function public.get_event_counts() to anon, authenticated;

-- Seed data. Aman dijalankan ulang.
insert into public.events (id,name,category,date,start_time,location,address,quota,status)
values
('11111111-1111-1111-1111-111111111111','Balap Karung','Anak-anak','2026-08-15','09:00','Lapangan Utama','Jl. Kemerdekaan No. 17, Kelurahan Setempat',80,'open'),
('22222222-2222-2222-2222-222222222222','Makan Kerupuk','Anak-anak','2026-08-16','10:00','Lapangan Utama','Jl. Kemerdekaan No. 17, Kelurahan Setempat',60,'open'),
('33333333-3333-3333-3333-333333333333','Estafet Keluarga','Keluarga','2026-08-16','14:00','Lapangan Utama','Jl. Kemerdekaan No. 17, Kelurahan Setempat',40,'open'),
('44444444-4444-4444-4444-444444444444','Panjat Pinang','Umum','2026-08-17','15:30','Lapangan Utama','Jl. Kemerdekaan No. 17, Kelurahan Setempat',20,'open')
on conflict (id) do nothing;

insert into public.organizers (id,name,role,phone) values
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ketua Panitia','Ketua','081234567890'),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Admin Lomba','Sekretaris','081234567891')
on conflict (id) do nothing;

insert into public.members (id,name,group_name,phone) values
('cccccccc-cccc-cccc-cccc-cccccccccccc','Budi Santoso','RT 01','081200000001'),
('dddddddd-dddd-dddd-dddd-dddddddddddd','Siti Aminah','RT 01','081200000002'),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','Andi Pratama','RT 02','081200000003')
on conflict (id) do nothing;
