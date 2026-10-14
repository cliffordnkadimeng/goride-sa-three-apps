-- GoRide SA initial schema. Additive and idempotent: no existing application tables are dropped.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  role text not null default 'passenger' check (role in ('passenger', 'driver', 'admin')),
  suspended boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.drivers (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  approval_status text not null default 'pending' check (approval_status in ('pending', 'approved', 'rejected', 'suspended')),
  is_online boolean not null default false,
  average_rating numeric(3,2) not null default 5.00 check (average_rating between 0 and 5),
  total_trips integer not null default 0 check (total_trips >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(user_id) on delete cascade,
  make text not null,
  model text not null,
  color text not null,
  registration_number text not null,
  category text not null default 'GoRide' check (category in ('GoRide', 'Comfort', 'XL')),
  seats integer not null default 4 check (seats between 2 and 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists vehicles_registration_lower_unique on public.vehicles (lower(registration_number));
create index if not exists vehicles_driver_idx on public.vehicles(driver_id);

create table if not exists public.driver_documents (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(user_id) on delete cascade,
  document_type text not null check (document_type in ('identity', 'licence', 'professional_driving_permit', 'vehicle_registration', 'vehicle_insurance')),
  storage_path text not null,
  review_status text not null default 'pending' check (review_status in ('pending', 'approved', 'rejected')),
  reviewer_id uuid references public.profiles(id),
  review_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists driver_documents_driver_idx on public.driver_documents(driver_id, review_status);

create table if not exists public.fare_settings (
  category text primary key check (category in ('GoRide', 'Comfort', 'XL')),
  base_fare numeric(10,2) not null check (base_fare >= 0),
  per_km numeric(10,2) not null check (per_km >= 0),
  per_minute numeric(10,2) not null check (per_minute >= 0),
  minimum_fare numeric(10,2) not null check (minimum_fare >= 0),
  commission_pct numeric(5,2) not null default 18 check (commission_pct between 0 and 50),
  updated_at timestamptz not null default now()
);
insert into public.fare_settings(category, base_fare, per_km, per_minute, minimum_fare, commission_pct)
values ('GoRide', 18, 7.50, 0.80, 35, 18), ('Comfort', 24, 9.50, 1, 48, 18), ('XL', 32, 12, 1.20, 64, 18)
on conflict (category) do nothing;

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.profiles(id),
  driver_id uuid references public.drivers(user_id),
  vehicle_id uuid references public.vehicles(id),
  pickup_address text not null,
  destination_address text not null,
  pickup_lat double precision not null check (pickup_lat between -90 and 90),
  pickup_lng double precision not null check (pickup_lng between -180 and 180),
  destination_lat double precision not null check (destination_lat between -90 and 90),
  destination_lng double precision not null check (destination_lng between -180 and 180),
  category text not null check (category in ('GoRide', 'Comfort', 'XL')),
  distance_km numeric(8,2) not null check (distance_km > 0 and distance_km <= 500),
  duration_min integer not null check (duration_min > 0 and duration_min <= 720),
  estimated_fare numeric(10,2) not null check (estimated_fare >= 0),
  final_fare numeric(10,2),
  payment_method text not null default 'cash' check (payment_method in ('cash', 'card')),
  status text not null default 'requested' check (status in ('requested', 'accepted', 'arriving', 'in_progress', 'completed', 'cancelled')),
  requested_at timestamptz not null default now(),
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists trips_passenger_created_idx on public.trips(passenger_id, created_at desc);
create index if not exists trips_driver_status_idx on public.trips(driver_id, status) where driver_id is not null;
create index if not exists trips_requested_idx on public.trips(created_at) where status = 'requested';
create unique index if not exists trips_one_active_per_driver on public.trips(driver_id)
  where driver_id is not null and status in ('accepted', 'arriving', 'in_progress');

create table if not exists public.trip_locations (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  actor_id uuid not null references public.profiles(id),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision,
  recorded_at timestamptz not null default now()
);
create index if not exists trip_locations_latest_idx on public.trip_locations(trip_id, recorded_at desc);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null unique references public.trips(id) on delete cascade,
  provider text not null default 'cash',
  provider_reference text unique,
  amount numeric(10,2) not null check (amount >= 0),
  currency text not null default 'ZAR' check (currency = 'ZAR'),
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'refunded')),
  last_event_id text unique,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  reviewer_id uuid not null references public.profiles(id),
  reviewee_id uuid not null references public.profiles(id),
  score integer not null check (score between 1 and 5),
  comment text not null default '' check (char_length(comment) <= 1000),
  created_at timestamptz not null default now(),
  unique (trip_id, reviewer_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id),
  trip_id uuid references public.trips(id),
  subject text not null check (char_length(subject) between 1 and 120),
  message text not null check (char_length(message) between 1 and 2000),
  status text not null default 'open' check (status in ('open', 'in_review', 'resolved')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_tickets_status_created_idx on public.support_tickets(status, created_at desc);

create or replace function public.current_user_role()
returns text language sql stable security definer set search_path = '' as $$
  select p.role from public.profiles p where p.id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.current_user_role() = 'admin', false)
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated on public.profiles;
create trigger profiles_touch_updated before update on public.profiles for each row execute function public.touch_updated_at();
drop trigger if exists drivers_touch_updated on public.drivers;
create trigger drivers_touch_updated before update on public.drivers for each row execute function public.touch_updated_at();
drop trigger if exists vehicles_touch_updated on public.vehicles;
create trigger vehicles_touch_updated before update on public.vehicles for each row execute function public.touch_updated_at();
drop trigger if exists trips_touch_updated on public.trips;
create trigger trips_touch_updated before update on public.trips for each row execute function public.touch_updated_at();
drop trigger if exists payments_touch_updated on public.payments;
create trigger payments_touch_updated before update on public.payments for each row execute function public.touch_updated_at();
drop trigger if exists support_tickets_touch_updated on public.support_tickets;
create trigger support_tickets_touch_updated before update on public.support_tickets for each row execute function public.touch_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name, phone, role)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(coalesce(new.email, new.phone, 'GoRide user'), '@', 1)),
    new.phone,
    'passenger'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_goridesa on auth.users;
create trigger on_auth_user_created_goridesa after insert on auth.users for each row execute function public.handle_new_auth_user();

create or replace function public.submit_driver_application()
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Sign in first.'; end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  update public.profiles set role = 'driver' where id = v_user and role = 'passenger';
  if not exists (select 1 from public.profiles where id = v_user and role = 'driver') then raise exception 'This account cannot apply as a driver.'; end if;
  insert into public.drivers(user_id, approval_status) values (v_user, 'pending') on conflict (user_id) do nothing;
end;
$$;

create or replace function public.set_driver_online(p_online boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null or public.current_user_role() <> 'driver' then raise exception 'Driver access required.'; end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  update public.drivers set is_online = p_online
  where user_id = v_user and approval_status = 'approved';
  if not found then raise exception 'Driver approval is required before going online.'; end if;
end;
$$;

create or replace function public.admin_set_driver_approval(p_driver_id uuid, p_approved boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  update public.drivers set approval_status = case when p_approved then 'approved' else 'rejected' end,
    is_online = case when p_approved then is_online else false end
  where user_id = p_driver_id;
  if not found then raise exception 'Driver not found.'; end if;
end;
$$;

create or replace function public.admin_suspend_profile(p_user_id uuid, p_suspended boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  update public.profiles set suspended = p_suspended where id = p_user_id;
  if not found then raise exception 'User not found.'; end if;
  if p_suspended then update public.drivers set is_online = false where user_id = p_user_id; end if;
end;
$$;

create or replace function public.admin_review_driver_document(p_document_id uuid, p_approved boolean, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  update public.driver_documents set review_status = case when p_approved then 'approved' else 'rejected' end,
    reviewer_id = auth.uid(), review_note = left(coalesce(p_note, ''), 500), reviewed_at = now()
  where id = p_document_id;
  if not found then raise exception 'Driver document not found.'; end if;
end;
$$;

create or replace function public.request_ride(
  p_pickup_address text, p_destination_address text,
  p_pickup_lat double precision, p_pickup_lng double precision,
  p_destination_lat double precision, p_destination_lng double precision,
  p_category text, p_distance_km numeric, p_duration_min integer,
  p_payment_method text default 'cash'
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_settings public.fare_settings%rowtype;
  v_trip_id uuid;
  v_fare numeric(10,2);
begin
  if v_user is null or public.current_user_role() <> 'passenger' then raise exception 'Passenger access required.'; end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  if p_payment_method <> 'cash' then raise exception 'Card checkout is not enabled yet.'; end if;
  if char_length(trim(p_pickup_address)) not between 2 and 180 or char_length(trim(p_destination_address)) not between 2 and 180 then raise exception 'Enter valid pickup and destination addresses.'; end if;
  if p_category not in ('GoRide', 'Comfort', 'XL') then raise exception 'Unknown ride category.'; end if;
  if p_distance_km <= 0 or p_distance_km > 500 or p_duration_min <= 0 or p_duration_min > 720 then raise exception 'Route estimate is invalid.'; end if;
  select * into v_settings from public.fare_settings where category = p_category;
  if not found then raise exception 'Fare settings are unavailable.'; end if;
  v_fare := round(greatest(v_settings.minimum_fare, v_settings.base_fare + p_distance_km * v_settings.per_km + p_duration_min * v_settings.per_minute), 2);
  insert into public.trips(
    passenger_id, pickup_address, destination_address, pickup_lat, pickup_lng,
    destination_lat, destination_lng, category, distance_km, duration_min, estimated_fare, payment_method, status
  ) values (
    v_user, trim(p_pickup_address), trim(p_destination_address), p_pickup_lat, p_pickup_lng,
    p_destination_lat, p_destination_lng, p_category, p_distance_km, p_duration_min, v_fare, 'cash', 'requested'
  ) returning id into v_trip_id;
  insert into public.notifications(user_id, type, payload)
  select d.user_id, 'ride_request', jsonb_build_object('trip_id', v_trip_id, 'category', p_category)
  from public.drivers d join public.profiles p on p.id = d.user_id
  where d.is_online and d.approval_status = 'approved' and not p.suspended;
  return v_trip_id;
end;
$$;

create or replace function public.accept_trip(p_trip_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_vehicle uuid;
begin
  if v_user is null or public.current_user_role() <> 'driver' then raise exception 'Driver access required.'; end if;
  perform 1 from public.drivers where user_id = v_user and approval_status = 'approved' and is_online for update;
  if not found then raise exception 'An approved online driver account is required.'; end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  if exists (select 1 from public.trips where driver_id = v_user and status in ('accepted', 'arriving', 'in_progress')) then raise exception 'This driver already has an active trip.'; end if;
  select * into v_trip from public.trips where id = p_trip_id and status = 'requested' for update;
  if not found then raise exception 'This ride request is no longer available.'; end if;
  select id into v_vehicle from public.vehicles where driver_id = v_user and (category = v_trip.category or category = 'XL') order by created_at asc limit 1;
  if v_vehicle is null then raise exception 'A matching approved vehicle is required for this ride category.'; end if;
  update public.trips set driver_id = v_user, vehicle_id = v_vehicle, status = 'accepted', accepted_at = now() where id = p_trip_id;
  insert into public.notifications(user_id, type, payload) values (v_trip.passenger_id, 'driver_matched', jsonb_build_object('trip_id', p_trip_id));
end;
$$;

create or replace function public.transition_trip(p_trip_id uuid, p_new_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception 'Sign in first.'; end if;
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found then raise exception 'Trip not found.'; end if;
  if v_user = v_trip.passenger_id and public.current_user_role() = 'passenger' and p_new_status = 'cancelled' and v_trip.status in ('requested', 'accepted', 'arriving') then
    update public.trips set status = 'cancelled', cancelled_at = now() where id = p_trip_id;
    if v_trip.driver_id is not null then insert into public.notifications(user_id, type, payload) values (v_trip.driver_id, 'trip_cancelled', jsonb_build_object('trip_id', p_trip_id)); end if;
    return;
  end if;
  if v_user <> v_trip.driver_id or public.current_user_role() <> 'driver' then raise exception 'This trip does not belong to your driver account.'; end if;
  if (v_trip.status = 'accepted' and p_new_status = 'arriving') then
    update public.trips set status = 'arriving' where id = p_trip_id;
  elsif (v_trip.status = 'arriving' and p_new_status = 'in_progress') then
    update public.trips set status = 'in_progress', started_at = now() where id = p_trip_id;
  elsif (v_trip.status = 'in_progress' and p_new_status = 'completed') then
    update public.trips set status = 'completed', completed_at = now(), final_fare = estimated_fare where id = p_trip_id;
    update public.drivers set total_trips = total_trips + 1 where user_id = v_user;
    insert into public.payments(trip_id, provider, amount, currency, status)
    values (p_trip_id, 'cash', v_trip.estimated_fare, 'ZAR', 'pending') on conflict (trip_id) do nothing;
    insert into public.notifications(user_id, type, payload) values (v_trip.passenger_id, 'trip_completed', jsonb_build_object('trip_id', p_trip_id));
  else
    raise exception 'That trip status transition is not allowed.';
  end if;
end;
$$;

create or replace function public.record_driver_location(p_trip_id uuid, p_lat double precision, p_lng double precision, p_accuracy_m double precision default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.trips where id = p_trip_id and driver_id = auth.uid() and status in ('accepted', 'arriving', 'in_progress')
  ) then raise exception 'Active driver trip required.'; end if;
  insert into public.trip_locations(trip_id, actor_id, latitude, longitude, accuracy_m)
  values (p_trip_id, auth.uid(), p_lat, p_lng, p_accuracy_m);
  insert into public.notifications(user_id, type, payload)
  select passenger_id, 'driver_location', jsonb_build_object('trip_id', p_trip_id)
  from public.trips where id = p_trip_id;
end;
$$;

alter table public.profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.vehicles enable row level security;
alter table public.driver_documents enable row level security;
alter table public.fare_settings enable row level security;
alter table public.trips enable row level security;
alter table public.trip_locations enable row level security;
alter table public.payments enable row level security;
alter table public.ratings enable row level security;
alter table public.notifications enable row level security;
alter table public.support_tickets enable row level security;

drop policy if exists profiles_select_self_admin on public.profiles;
create policy profiles_select_self_admin on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists drivers_select_permitted on public.drivers;
create policy drivers_select_permitted on public.drivers for select to authenticated using (
  user_id = auth.uid() or public.is_admin() or (approval_status = 'approved' and is_online)
  or exists (select 1 from public.trips t where t.driver_id = user_id and t.passenger_id = auth.uid())
);

drop policy if exists vehicles_select_permitted on public.vehicles;
create policy vehicles_select_permitted on public.vehicles for select to authenticated using (
  driver_id = auth.uid() or public.is_admin()
  or exists (select 1 from public.drivers d where d.user_id = driver_id and d.approval_status = 'approved' and d.is_online)
  or exists (select 1 from public.trips t where t.vehicle_id = id and t.passenger_id = auth.uid())
);
drop policy if exists vehicles_insert_self_admin on public.vehicles;
create policy vehicles_insert_self_admin on public.vehicles for insert to authenticated with check (
  (driver_id = auth.uid() and public.current_user_role() = 'driver') or public.is_admin()
);
drop policy if exists vehicles_update_self_admin on public.vehicles;
create policy vehicles_update_self_admin on public.vehicles for update to authenticated using (driver_id = auth.uid() or public.is_admin()) with check (driver_id = auth.uid() or public.is_admin());

drop policy if exists driver_documents_select_owner_admin on public.driver_documents;
create policy driver_documents_select_owner_admin on public.driver_documents for select to authenticated using (driver_id = auth.uid() or public.is_admin());
drop policy if exists driver_documents_insert_owner on public.driver_documents;
create policy driver_documents_insert_owner on public.driver_documents for insert to authenticated with check (driver_id = auth.uid() and public.current_user_role() = 'driver');

drop policy if exists fares_select_authenticated on public.fare_settings;
create policy fares_select_authenticated on public.fare_settings for select to authenticated using (true);
drop policy if exists fares_admin_update on public.fare_settings;
create policy fares_admin_update on public.fare_settings for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists trips_select_participant_admin on public.trips;
create policy trips_select_participant_admin on public.trips for select to authenticated using (passenger_id = auth.uid() or driver_id = auth.uid() or public.is_admin());

drop policy if exists trip_locations_select_participant_admin on public.trip_locations;
create policy trip_locations_select_participant_admin on public.trip_locations for select to authenticated using (
  public.is_admin() or exists (select 1 from public.trips t where t.id = trip_id and (t.passenger_id = auth.uid() or t.driver_id = auth.uid()))
);

drop policy if exists payments_select_participant_admin on public.payments;
create policy payments_select_participant_admin on public.payments for select to authenticated using (
  public.is_admin() or exists (select 1 from public.trips t where t.id = trip_id and (t.passenger_id = auth.uid() or t.driver_id = auth.uid()))
);

drop policy if exists ratings_select_participant_admin on public.ratings;
create policy ratings_select_participant_admin on public.ratings for select to authenticated using (reviewer_id = auth.uid() or reviewee_id = auth.uid() or public.is_admin());
drop policy if exists ratings_insert_participant on public.ratings;
create policy ratings_insert_participant on public.ratings for insert to authenticated with check (
  reviewer_id = auth.uid() and exists (
    select 1 from public.trips t where t.id = trip_id and t.status = 'completed'
      and (t.passenger_id = auth.uid() or t.driver_id = auth.uid())
      and reviewee_id in (t.passenger_id, t.driver_id)
  )
);

drop policy if exists notifications_select_owner_admin on public.notifications;
create policy notifications_select_owner_admin on public.notifications for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists support_select_owner_admin on public.support_tickets;
create policy support_select_owner_admin on public.support_tickets for select to authenticated using (creator_id = auth.uid() or public.is_admin());
drop policy if exists support_insert_owner on public.support_tickets;
create policy support_insert_owner on public.support_tickets for insert to authenticated with check (creator_id = auth.uid());
drop policy if exists support_admin_update on public.support_tickets;
create policy support_admin_update on public.support_tickets for update to authenticated using (public.is_admin()) with check (public.is_admin());

grant usage on schema public to authenticated;
grant select on public.profiles, public.drivers, public.vehicles, public.driver_documents, public.fare_settings, public.trips, public.trip_locations, public.payments, public.ratings, public.notifications, public.support_tickets to authenticated;
grant insert on public.vehicles, public.driver_documents, public.ratings, public.support_tickets to authenticated;
grant update on public.vehicles, public.fare_settings, public.support_tickets to authenticated;
revoke insert, update, delete on public.profiles, public.drivers, public.trips, public.trip_locations, public.payments, public.notifications from anon, authenticated;
revoke update on public.driver_documents from anon, authenticated;

revoke all on function public.current_user_role() from public;
revoke all on function public.is_admin() from public;
revoke all on function public.submit_driver_application() from public;
revoke all on function public.set_driver_online(boolean) from public;
revoke all on function public.admin_set_driver_approval(uuid, boolean) from public;
revoke all on function public.admin_suspend_profile(uuid, boolean) from public;
revoke all on function public.admin_review_driver_document(uuid, boolean, text) from public;
revoke all on function public.request_ride(text, text, double precision, double precision, double precision, double precision, text, numeric, integer, text) from public;
revoke all on function public.accept_trip(uuid) from public;
revoke all on function public.transition_trip(uuid, text) from public;
revoke all on function public.record_driver_location(uuid, double precision, double precision, double precision) from public;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.submit_driver_application() to authenticated;
grant execute on function public.set_driver_online(boolean) to authenticated;
grant execute on function public.admin_set_driver_approval(uuid, boolean) to authenticated;
grant execute on function public.admin_suspend_profile(uuid, boolean) to authenticated;
grant execute on function public.admin_review_driver_document(uuid, boolean, text) to authenticated;
grant execute on function public.request_ride(text, text, double precision, double precision, double precision, double precision, text, numeric, integer, text) to authenticated;
grant execute on function public.accept_trip(uuid) to authenticated;
grant execute on function public.transition_trip(uuid, text) to authenticated;
grant execute on function public.record_driver_location(uuid, double precision, double precision, double precision) to authenticated;

insert into storage.buckets(id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do update set public = false;
drop policy if exists driver_documents_storage_select on storage.objects;
create policy driver_documents_storage_select on storage.objects for select to authenticated using (
  bucket_id = 'driver-documents' and (split_part(name, '/', 1) = auth.uid()::text or public.is_admin())
);
drop policy if exists driver_documents_storage_insert on storage.objects;
create policy driver_documents_storage_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'driver-documents' and split_part(name, '/', 1) = auth.uid()::text and public.current_user_role() = 'driver'
);
drop policy if exists driver_documents_storage_update on storage.objects;
create policy driver_documents_storage_update on storage.objects for update to authenticated using (
  bucket_id = 'driver-documents' and (split_part(name, '/', 1) = auth.uid()::text or public.is_admin())
) with check (bucket_id = 'driver-documents' and (split_part(name, '/', 1) = auth.uid()::text or public.is_admin()));
drop policy if exists driver_documents_storage_delete on storage.objects;
create policy driver_documents_storage_delete on storage.objects for delete to authenticated using (
  bucket_id = 'driver-documents' and (split_part(name, '/', 1) = auth.uid()::text or public.is_admin())
);

-- Enable live trip updates when the standard Supabase realtime publication exists.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trips') then
      alter publication supabase_realtime add table public.trips;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications') then
      alter publication supabase_realtime add table public.notifications;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trip_locations') then
      alter publication supabase_realtime add table public.trip_locations;
    end if;
  end if;
end;
$$;
