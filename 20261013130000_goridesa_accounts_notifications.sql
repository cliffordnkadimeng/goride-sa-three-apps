-- Safe account settings and in-app notification helpers.
-- Apply after 20261013123000_goridesa_initial.sql and 20261013124500_goridesa_live_features.sql.

create or replace function public.update_own_profile(p_full_name text, p_phone text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_name text := btrim(coalesce(p_full_name, ''));
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
begin
  if v_user is null then raise exception 'Sign in first.'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Enter a name between 2 and 80 characters.';
  end if;
  if v_phone is not null and (char_length(v_phone) > 24 or v_phone !~ '^\+?[0-9][0-9 ()-]{5,23}$') then
    raise exception 'Enter a valid contact phone number.';
  end if;

  update public.profiles set full_name = v_name, phone = v_phone where id = v_user;
  if not found then raise exception 'GoRide profile not found.'; end if;
  update public.drivers set full_name = v_name where user_id = v_user;
end;
$$;
revoke all on function public.update_own_profile(text, text) from public;
grant execute on function public.update_own_profile(text, text) to authenticated;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  update public.notifications set read_at = coalesce(read_at, now())
    where id = p_notification_id and user_id = auth.uid();
  if not found then raise exception 'Notification not found.'; end if;
end;
$$;
revoke all on function public.mark_notification_read(uuid) from public;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.refresh_driver_rating()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_reviewee uuid;
begin
  if tg_op = 'DELETE' then v_reviewee := old.reviewee_id; else v_reviewee := new.reviewee_id; end if;
  if exists (select 1 from public.drivers where user_id = v_reviewee) then
    update public.drivers d
      set average_rating = coalesce((
        select round(avg(r.score)::numeric, 2)
        from public.ratings r
        join public.trips t on t.id = r.trip_id
        where r.reviewee_id = v_reviewee and t.driver_id = v_reviewee
      ), 5.00)
      where d.user_id = v_reviewee;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
drop trigger if exists ratings_refresh_driver_rating on public.ratings;
create trigger ratings_refresh_driver_rating after insert or update or delete on public.ratings
  for each row execute function public.refresh_driver_rating();

create or replace function public.notify_admin_support_ticket()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications(user_id, type, payload)
  select p.id, 'support_ticket', jsonb_build_object('ticket_id', new.id, 'subject', new.subject)
  from public.profiles p where p.role = 'admin';
  return new;
end;
$$;
drop trigger if exists support_ticket_notify_admin on public.support_tickets;
create trigger support_ticket_notify_admin after insert on public.support_tickets
  for each row execute function public.notify_admin_support_ticket();

create or replace function public.notify_admin_driver_application()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications(user_id, type, payload)
  select p.id, 'driver_application', jsonb_build_object('driver_id', new.user_id)
  from public.profiles p where p.role = 'admin';
  return new;
end;
$$;
drop trigger if exists driver_application_notify_admin on public.drivers;
create trigger driver_application_notify_admin after insert on public.drivers
  for each row execute function public.notify_admin_driver_application();

create or replace function public.notify_driver_document_review()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.review_status is distinct from new.review_status then
    insert into public.notifications(user_id, type, payload)
    values (new.driver_id, 'document_review', jsonb_build_object('document_id', new.id, 'review_status', new.review_status));
  end if;
  return new;
end;
$$;
drop trigger if exists driver_document_notify_review on public.driver_documents;
create trigger driver_document_notify_review after update of review_status on public.driver_documents
  for each row execute function public.notify_driver_document_review();

create or replace function public.notify_driver_vehicle_review()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.approval_status is distinct from new.approval_status then
    insert into public.notifications(user_id, type, payload)
    values (new.driver_id, 'vehicle_review', jsonb_build_object('vehicle_id', new.id, 'approval_status', new.approval_status));
  end if;
  return new;
end;
$$;
drop trigger if exists vehicle_notify_review on public.vehicles;
create trigger vehicle_notify_review after update of approval_status on public.vehicles
  for each row execute function public.notify_driver_vehicle_review();

revoke all on function public.refresh_driver_rating() from public;
revoke all on function public.notify_admin_support_ticket() from public;
revoke all on function public.notify_admin_driver_application() from public;
revoke all on function public.notify_driver_document_review() from public;
revoke all on function public.notify_driver_vehicle_review() from public;
