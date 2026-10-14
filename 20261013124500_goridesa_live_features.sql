-- GoRide SA live features follow-up. Additive and safe to re-run; no existing application rows are removed.

alter table public.drivers add column if not exists full_name text not null default '';
update public.drivers d set full_name = p.full_name
from public.profiles p where p.id = d.user_id and d.full_name = '';

alter table public.vehicles add column if not exists approval_status text not null default 'pending';
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.vehicles'::regclass and conname = 'vehicles_approval_status_check'
  ) then
    alter table public.vehicles add constraint vehicles_approval_status_check
      check (approval_status in ('pending', 'approved', 'rejected'));
  end if;
end;
$$;
create index if not exists vehicles_approval_category_idx on public.vehicles(approval_status, category, driver_id);

create table if not exists public.trip_rejections (
  driver_id uuid not null references public.drivers(user_id) on delete cascade,
  trip_id uuid not null references public.trips(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (driver_id, trip_id)
);
create index if not exists trip_rejections_trip_idx on public.trip_rejections(trip_id);
alter table public.trip_rejections enable row level security;
revoke insert, update, delete on public.trip_rejections from anon, authenticated;
grant select on public.trip_rejections to authenticated;
drop policy if exists trip_rejections_select_owner_admin on public.trip_rejections;
create policy trip_rejections_select_owner_admin on public.trip_rejections
  for select to authenticated using (driver_id = auth.uid() or public.is_admin());

-- One current position per active trip; this avoids retaining a long-lived GPS trail.
create unique index if not exists trip_locations_trip_actor_unique
  on public.trip_locations(trip_id, actor_id);

create or replace function public.submit_driver_application()
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Sign in first.'; end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  update public.profiles set role = 'driver' where id = v_user and role = 'passenger';
  if not exists (select 1 from public.profiles where id = v_user and role = 'driver') then raise exception 'This account cannot apply as a driver.'; end if;
  insert into public.drivers(user_id, approval_status, full_name)
  select p.id, 'pending', p.full_name from public.profiles p where p.id = v_user
  on conflict (user_id) do update set full_name = excluded.full_name;
end;
$$;

create or replace function public.admin_review_vehicle(p_vehicle_id uuid, p_approved boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  update public.vehicles
  set approval_status = case when p_approved then 'approved' else 'rejected' end
  where id = p_vehicle_id;
  if not found then raise exception 'Vehicle not found.'; end if;
end;
$$;

create or replace function public.set_driver_online(p_online boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null or public.current_user_role() <> 'driver' then raise exception 'Driver access required.'; end if;
  if p_online is null then raise exception 'Availability choice is required.'; end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  perform 1 from public.drivers where user_id = v_user and approval_status = 'approved' for update;
  if not found then raise exception 'Driver approval is required before changing availability.'; end if;
  if exists (select 1 from public.trips where driver_id = v_user and status in ('accepted', 'arriving', 'in_progress')) then
    raise exception 'Complete your active trip before changing availability.';
  end if;
  if p_online and not exists (
    select 1 from public.vehicles where driver_id = v_user and approval_status = 'approved'
  ) then raise exception 'An admin-approved vehicle is required before going online.'; end if;
  update public.drivers set is_online = p_online where user_id = v_user;
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
  v_a double precision;
  v_direct_km double precision;
begin
  if v_user is null or public.current_user_role() <> 'passenger' then raise exception 'Passenger access required.'; end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  if p_payment_method is distinct from 'cash' then raise exception 'Card checkout is not enabled yet.'; end if;
  if char_length(trim(p_pickup_address)) not between 2 and 180 or char_length(trim(p_destination_address)) not between 2 and 180 then raise exception 'Enter valid pickup and destination addresses.'; end if;
  if p_category not in ('GoRide', 'Comfort', 'XL') then raise exception 'Unknown ride category.'; end if;
  if p_pickup_lat not between -90 and 90 or p_destination_lat not between -90 and 90
    or p_pickup_lng not between -180 and 180 or p_destination_lng not between -180 and 180 then
    raise exception 'Location coordinates are invalid.';
  end if;
  if p_distance_km <= 0 or p_distance_km > 500 or p_duration_min <= 0 or p_duration_min > 720 then raise exception 'Route estimate is invalid.'; end if;
  v_a := power(sin(radians(p_destination_lat - p_pickup_lat) / 2), 2)
    + cos(radians(p_pickup_lat)) * cos(radians(p_destination_lat))
    * power(sin(radians(p_destination_lng - p_pickup_lng) / 2), 2);
  v_direct_km := 6371 * 2 * atan2(sqrt(least(1, v_a)), sqrt(greatest(0, 1 - v_a)));
  if p_distance_km < greatest(0.3, v_direct_km * 0.92)
    or p_distance_km > greatest(4.0, v_direct_km * 5 + 10) then
    raise exception 'Route distance is inconsistent with the selected locations.';
  end if;
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
  select distinct d.user_id, 'ride_request', jsonb_build_object('trip_id', v_trip_id, 'category', p_category)
  from public.drivers d
  join public.profiles p on p.id = d.user_id
  join public.vehicles v on v.driver_id = d.user_id
  where d.is_online and d.approval_status = 'approved' and not p.suspended
    and v.approval_status = 'approved' and (v.category = p_category or v.category = 'XL');
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
  if exists (select 1 from public.trip_rejections where driver_id = v_user and trip_id = p_trip_id) then raise exception 'You passed on this request already.'; end if;
  select id into v_vehicle from public.vehicles
  where driver_id = v_user and approval_status = 'approved' and (category = v_trip.category or category = 'XL')
  order by created_at asc limit 1 for update;
  if v_vehicle is null then raise exception 'An approved matching vehicle is required for this ride category.'; end if;
  update public.trips set driver_id = v_user, vehicle_id = v_vehicle, status = 'accepted', accepted_at = now() where id = p_trip_id;
  insert into public.notifications(user_id, type, payload) values (v_trip.passenger_id, 'driver_matched', jsonb_build_object('trip_id', p_trip_id));
end;
$$;

create or replace function public.reject_trip(p_trip_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or public.current_user_role() <> 'driver' then raise exception 'Driver access required.'; end if;
  if not exists (select 1 from public.drivers where user_id = v_user and approval_status = 'approved' and is_online) then
    raise exception 'An approved online driver account is required.';
  end if;
  if exists (select 1 from public.profiles where id = v_user and suspended) then raise exception 'This account is suspended.'; end if;
  perform 1 from public.trips where id = p_trip_id and status = 'requested' for update;
  if not found then raise exception 'This ride request is no longer available.'; end if;
  insert into public.trip_rejections(driver_id, trip_id) values (v_user, p_trip_id) on conflict do nothing;
end;
$$;

create or replace function public.record_driver_location(p_trip_id uuid, p_lat double precision, p_lng double precision, p_accuracy_m double precision default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or public.current_user_role() <> 'driver' or not exists (
    select 1 from public.trips where id = p_trip_id and driver_id = auth.uid() and status in ('accepted', 'arriving', 'in_progress')
  ) then raise exception 'Active driver trip required.'; end if;
  insert into public.trip_locations(trip_id, actor_id, latitude, longitude, accuracy_m)
  values (p_trip_id, auth.uid(), p_lat, p_lng, p_accuracy_m)
  on conflict (trip_id, actor_id) do update
    set latitude = excluded.latitude, longitude = excluded.longitude,
        accuracy_m = excluded.accuracy_m, recorded_at = now();
end;
$$;

create or replace function public.stop_driver_location(p_trip_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or public.current_user_role() <> 'driver' or not exists (
    select 1 from public.trips where id = p_trip_id and driver_id = auth.uid() and status in ('accepted', 'arriving', 'in_progress')
  ) then raise exception 'Active driver trip required.'; end if;
  delete from public.trip_locations where trip_id = p_trip_id and actor_id = auth.uid();
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
  if v_user = v_trip.passenger_id and public.current_user_role() = 'passenger'
    and p_new_status = 'cancelled' and v_trip.status in ('requested', 'accepted', 'arriving') then
    update public.trips set status = 'cancelled', cancelled_at = now() where id = p_trip_id;
    delete from public.trip_locations where trip_id = p_trip_id;
    if v_trip.driver_id is not null then
      insert into public.notifications(user_id, type, payload) values (v_trip.driver_id, 'trip_cancelled', jsonb_build_object('trip_id', p_trip_id));
    end if;
    return;
  end if;
  if v_user <> v_trip.driver_id or public.current_user_role() <> 'driver' then raise exception 'This trip does not belong to your driver account.'; end if;
  if v_trip.status = 'accepted' and p_new_status = 'arriving' then
    update public.trips set status = 'arriving' where id = p_trip_id;
  elsif v_trip.status = 'arriving' and p_new_status = 'in_progress' then
    update public.trips set status = 'in_progress', started_at = now() where id = p_trip_id;
  elsif v_trip.status = 'in_progress' and p_new_status = 'completed' then
    update public.trips set status = 'completed', completed_at = now(), final_fare = estimated_fare where id = p_trip_id;
    update public.drivers set total_trips = total_trips + 1 where user_id = v_user;
    insert into public.payments(trip_id, provider, amount, currency, status)
      values (p_trip_id, 'cash', v_trip.estimated_fare, 'ZAR', 'pending') on conflict (trip_id) do nothing;
    insert into public.notifications(user_id, type, payload) values (v_trip.passenger_id, 'trip_completed', jsonb_build_object('trip_id', p_trip_id));
    delete from public.trip_locations where trip_id = p_trip_id;
  else
    raise exception 'That trip status transition is not allowed.';
  end if;
end;
$$;

create or replace function public.can_view_vehicle(p_vehicle_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.vehicles v
    where v.id = p_vehicle_id
      and (v.driver_id = auth.uid() or public.is_admin()
        or exists (select 1 from public.trips t where t.vehicle_id = v.id and t.passenger_id = auth.uid()))
  );
$$;
revoke all on function public.can_view_vehicle(uuid) from public;
grant execute on function public.can_view_vehicle(uuid) to authenticated;

drop policy if exists vehicles_select_permitted on public.vehicles;
create policy vehicles_select_permitted on public.vehicles for select to authenticated using (public.can_view_vehicle(id));

drop policy if exists trip_locations_select_participant_admin on public.trip_locations;
create policy trip_locations_select_participant_admin on public.trip_locations for select to authenticated using (
  recorded_at > now() - interval '60 seconds'
  and (public.is_admin() or exists (select 1 from public.trips t where t.id = trip_id and (t.passenger_id = auth.uid() or t.driver_id = auth.uid())))
);

drop policy if exists trips_select_available_driver on public.trips;
create policy trips_select_available_driver on public.trips for select to authenticated using (
  status = 'requested'
  and public.current_user_role() = 'driver'
  and exists (select 1 from public.drivers d where d.user_id = auth.uid() and d.approval_status = 'approved' and d.is_online)
  and exists (select 1 from public.vehicles v where v.driver_id = auth.uid() and v.approval_status = 'approved' and (v.category = trips.category or v.category = 'XL'))
  and not exists (select 1 from public.trip_rejections r where r.driver_id = auth.uid() and r.trip_id = trips.id)
);

revoke all on function public.submit_driver_application() from public;
revoke all on function public.admin_review_vehicle(uuid, boolean) from public;
revoke all on function public.request_ride(text, text, double precision, double precision, double precision, double precision, text, numeric, integer, text) from public;
revoke all on function public.accept_trip(uuid) from public;
revoke all on function public.reject_trip(uuid) from public;
revoke all on function public.record_driver_location(uuid, double precision, double precision, double precision) from public;
revoke all on function public.stop_driver_location(uuid) from public;
grant execute on function public.submit_driver_application() to authenticated;
grant execute on function public.admin_review_vehicle(uuid, boolean) to authenticated;
grant execute on function public.request_ride(text, text, double precision, double precision, double precision, double precision, text, numeric, integer, text) to authenticated;
grant execute on function public.accept_trip(uuid) to authenticated;
grant execute on function public.reject_trip(uuid) to authenticated;
grant execute on function public.record_driver_location(uuid, double precision, double precision, double precision) to authenticated;
grant execute on function public.stop_driver_location(uuid) to authenticated;

-- Keep the realtime publication aligned with the user-visible shared state.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trip_rejections') then
      alter publication supabase_realtime add table public.trip_rejections;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'driver_documents') then
      alter publication supabase_realtime add table public.driver_documents;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'vehicles') then
      alter publication supabase_realtime add table public.vehicles;
    end if;
  end if;
end;
$$;
