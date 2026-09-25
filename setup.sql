-- ONCLICK FINAL ONE-TIME MVP SECURITY + BUSINESS RULES SETUP
-- Run this whole file once in Supabase SQL Editor.
-- NEVER put a Secret/service_role key in GitHub or browser code.

create schema if not exists private;

-- ---------- Core columns ----------
alter table public.profiles add column if not exists account_status text not null default 'active';
alter table public.profiles add column if not exists warning_count integer not null default 0;
alter table public.profiles add column if not exists suspension_until timestamptz;
alter table public.profiles add column if not exists action_reason text;
alter table public.profiles add column if not exists last_action_at timestamptz;

alter table public.shops add column if not exists suspension_until timestamptz;
alter table public.shops add column if not exists suspension_reason text;
alter table public.shops add column if not exists approved_at timestamptz;
alter table public.shops add column if not exists approved_by uuid;

alter table public.orders add column if not exists status text default 'pending';
alter table public.orders add column if not exists payment_status text default 'unpaid';
alter table public.orders add column if not exists cancel_reason text;
alter table public.order_items add column if not exists quantity integer default 1;
alter table public.order_items add column if not exists unit_price numeric;
alter table public.order_items add column if not exists product_name text;

-- Normalize allowed status values for existing rows.
update public.profiles set account_status='active' where account_status is null;
update public.orders set status='pending' where status is null;
update public.orders set payment_status='unpaid' where payment_status is null;

-- ---------- Audit log ----------
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  action text not null,
  target_type text,
  target_id uuid,
  reason text,
  details jsonb,
  created_at timestamptz not null default now()
);
alter table public.audit_logs enable row level security;

-- ---------- Auth profile trigger ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.profiles(id,full_name,phone,role,account_status)
  values(
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    coalesce(new.raw_user_meta_data->>'phone',''),
    case when new.raw_user_meta_data->>'role'='vendor' then 'vendor' else 'customer' end,
    'active'
  )
  on conflict(id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- ---------- Security helpers ----------
create or replace function private.is_admin()
returns boolean language sql security definer stable set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and account_status='active');
$$;

create or replace function private.is_vendor()
returns boolean language sql security definer stable set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='vendor' and account_status='active');
$$;

create or replace function private.is_customer()
returns boolean language sql security definer stable set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='customer' and account_status='active');
$$;

create or replace function private.write_audit(
  p_action text, p_target_type text, p_target_id uuid, p_reason text default null, p_details jsonb default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  insert into public.audit_logs(actor_id,action,target_type,target_id,reason,details)
  values(auth.uid(),p_action,p_target_type,p_target_id,p_reason,p_details);
end;
$$;

-- ---------- Protect vendor-controlled shop fields ----------
create or replace function private.protect_shop_changes()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then
    if new.vendor_id <> old.vendor_id or new.is_approved <> old.is_approved
       or new.approved_at is distinct from old.approved_at
       or new.approved_by is distinct from old.approved_by
       or new.suspension_until is distinct from old.suspension_until
       or new.suspension_reason is distinct from old.suspension_reason then
      raise exception 'Only admin can change shop ownership, approval or suspension controls';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_shop_changes on public.shops;
create trigger protect_shop_changes before update on public.shops
for each row execute function private.protect_shop_changes();

-- ---------- Protect order financial fields ----------
create or replace function private.protect_order_changes()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then
    if new.customer_id <> old.customer_id or new.shop_id <> old.shop_id
       or new.product_subtotal <> old.product_subtotal
       or new.delivery_fee <> old.delivery_fee
       or new.commission_rate <> old.commission_rate
       or new.commission_amount <> old.commission_amount
       or new.customer_total <> old.customer_total
       or new.order_source <> old.order_source then
      raise exception 'Order financial/ownership fields can only be changed by admin';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_order_changes on public.orders;
create trigger protect_order_changes before update on public.orders
for each row execute function private.protect_order_changes();

-- ---------- Rebuild policies ----------
-- Profiles
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_admin_select" on public.profiles;
drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles for select to authenticated
using (id=auth.uid() or private.is_admin());
create policy "profiles_admin_update" on public.profiles for update to authenticated
using (private.is_admin()) with check (private.is_admin());

-- Shops
drop policy if exists "shops_public_select_approved" on public.shops;
drop policy if exists "shops_vendor_select_own" on public.shops;
drop policy if exists "shops_admin_select" on public.shops;
drop policy if exists "shops_vendor_insert" on public.shops;
drop policy if exists "shops_vendor_update" on public.shops;
drop policy if exists "shops_vendor_delete" on public.shops;
drop policy if exists "shops_admin_update" on public.shops;
drop policy if exists "shops_admin_delete" on public.shops;
create policy "shops_public_select_approved" on public.shops for select to anon,authenticated
using (is_approved=true and (suspension_until is null or suspension_until <= now()));
create policy "shops_vendor_select_own" on public.shops for select to authenticated
using (vendor_id=auth.uid() and private.is_vendor());
create policy "shops_vendor_insert" on public.shops for insert to authenticated
with check (vendor_id=auth.uid() and private.is_vendor() and is_approved=false);
create policy "shops_vendor_update" on public.shops for update to authenticated
using (vendor_id=auth.uid() and private.is_vendor())
with check (vendor_id=auth.uid() and private.is_vendor());
create policy "shops_vendor_delete" on public.shops for delete to authenticated
using (vendor_id=auth.uid() and private.is_vendor() and is_approved=false);
create policy "shops_admin_select" on public.shops for select to authenticated using (private.is_admin());
create policy "shops_admin_update" on public.shops for update to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "shops_admin_delete" on public.shops for delete to authenticated using (private.is_admin());

-- Products
drop policy if exists "products_public_select_available" on public.products;
drop policy if exists "products_vendor_select_own" on public.products;
drop policy if exists "products_admin_select" on public.products;
drop policy if exists "products_vendor_insert" on public.products;
drop policy if exists "products_vendor_update" on public.products;
drop policy if exists "products_vendor_delete" on public.products;
drop policy if exists "products_admin_update" on public.products;
drop policy if exists "products_admin_delete" on public.products;
create policy "products_public_select_available" on public.products for select to anon,authenticated
using (available=true and exists(select 1 from public.shops s where s.id=shop_id and s.is_approved=true and (s.suspension_until is null or s.suspension_until <= now())));
create policy "products_vendor_select_own" on public.products for select to authenticated
using (exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()) and private.is_vendor());
create policy "products_vendor_insert" on public.products for insert to authenticated
with check (private.is_vendor() and exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()));
create policy "products_vendor_update" on public.products for update to authenticated
using (private.is_vendor() and exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()))
with check (private.is_vendor() and exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()));
create policy "products_vendor_delete" on public.products for delete to authenticated
using (private.is_vendor() and exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()));
create policy "products_admin_select" on public.products for select to authenticated using (private.is_admin());
create policy "products_admin_update" on public.products for update to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "products_admin_delete" on public.products for delete to authenticated using (private.is_admin());

-- Orders
drop policy if exists "orders_customer_select_own" on public.orders;
drop policy if exists "orders_vendor_select_own_shop" on public.orders;
drop policy if exists "orders_admin_select" on public.orders;
drop policy if exists "orders_customer_insert" on public.orders;
drop policy if exists "orders_vendor_update" on public.orders;
drop policy if exists "orders_admin_update" on public.orders;
create policy "orders_customer_select_own" on public.orders for select to authenticated using (customer_id=auth.uid() and private.is_customer());
create policy "orders_vendor_select_own_shop" on public.orders for select to authenticated using (exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()) and private.is_vendor());
create policy "orders_admin_select" on public.orders for select to authenticated using (private.is_admin());
create policy "orders_customer_insert" on public.orders for insert to authenticated
with check (customer_id=auth.uid() and private.is_customer() and product_subtotal >= 500 and commission_rate=0.05 and commission_amount=round(product_subtotal*0.05,2) and customer_total=product_subtotal+delivery_fee and exists(select 1 from public.shops s where s.id=shop_id and s.is_approved=true and (s.suspension_until is null or s.suspension_until <= now())));
create policy "orders_vendor_update" on public.orders for update to authenticated
using (exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()) and private.is_vendor())
with check (exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()) and private.is_vendor());
create policy "orders_admin_update" on public.orders for update to authenticated using (private.is_admin()) with check (private.is_admin());

-- Order items
drop policy if exists "order_items_customer_select_own" on public.order_items;
drop policy if exists "order_items_vendor_select_own" on public.order_items;
drop policy if exists "order_items_admin_select" on public.order_items;
drop policy if exists "order_items_customer_insert" on public.order_items;
create policy "order_items_customer_select_own" on public.order_items for select to authenticated using (exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()) and private.is_customer());
create policy "order_items_vendor_select_own" on public.order_items for select to authenticated using (exists(select 1 from public.orders o join public.shops s on s.id=o.shop_id where o.id=order_id and s.vendor_id=auth.uid()) and private.is_vendor());
create policy "order_items_admin_select" on public.order_items for select to authenticated using (private.is_admin());
create policy "order_items_customer_insert" on public.order_items for insert to authenticated
with check (private.is_customer() and exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()));

-- Audit logs: only admin can read. Trigger/security-definer functions can write.
drop policy if exists "audit_admin_select" on public.audit_logs;
create policy "audit_admin_select" on public.audit_logs for select to authenticated using (private.is_admin());

-- ---------- Generic audit triggers ----------
create or replace function private.audit_row_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.audit_logs(actor_id,action,target_type,target_id,details)
    values(auth.uid(),tg_table_name||'_insert',tg_table_name,coalesce(new.id, null),to_jsonb(new));
    return new;
  elsif tg_op='UPDATE' then
    insert into public.audit_logs(actor_id,action,target_type,target_id,details)
    values(auth.uid(),tg_table_name||'_update',tg_table_name,coalesce(new.id, null),jsonb_build_object('old',to_jsonb(old),'new',to_jsonb(new)));
    return new;
  elsif tg_op='DELETE' then
    insert into public.audit_logs(actor_id,action,target_type,target_id,details)
    values(auth.uid(),tg_table_name||'_delete',tg_table_name,coalesce(old.id, null),to_jsonb(old));
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists audit_profiles on public.profiles;
drop trigger if exists audit_shops on public.shops;
drop trigger if exists audit_orders on public.orders;
create trigger audit_profiles after insert or update or delete on public.profiles for each row execute function private.audit_row_change();
create trigger audit_shops after insert or update or delete on public.shops for each row execute function private.audit_row_change();
create trigger audit_orders after insert or update or delete on public.orders for each row execute function private.audit_row_change();

-- ---------- Admin action helpers ----------
create or replace function public.admin_set_account_status(p_user_id uuid, p_status text, p_reason text default null, p_until timestamptz default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then raise exception 'Admin only'; end if;
  if p_status not in ('active','warned','suspended','banned') then raise exception 'Invalid account status'; end if;
  update public.profiles
  set account_status=p_status, suspension_until=case when p_status='suspended' then p_until else null end,
      action_reason=p_reason, last_action_at=now(), warning_count=case when p_status='warned' then warning_count+1 else warning_count end
  where id=p_user_id;
  perform private.write_audit('account_'||p_status,'profile',p_user_id,p_reason,jsonb_build_object('until',p_until));
end;
$$;

create or replace function public.admin_approve_shop(p_shop_id uuid, p_approved boolean, p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then raise exception 'Admin only'; end if;
  update public.shops set is_approved=p_approved, approved_at=case when p_approved then now() else null end, approved_by=case when p_approved then auth.uid() else null end, suspension_until=null, suspension_reason=null where id=p_shop_id;
  perform private.write_audit(case when p_approved then 'shop_approved' else 'shop_rejected' end,'shop',p_shop_id,p_reason,null);
end;
$$;

create or replace function public.admin_suspend_shop(p_shop_id uuid, p_until timestamptz, p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then raise exception 'Admin only'; end if;
  update public.shops set suspension_until=p_until, suspension_reason=p_reason where id=p_shop_id;
  perform private.write_audit('shop_suspended','shop',p_shop_id,p_reason,jsonb_build_object('until',p_until));
end;
$$;

-- ---------- Business rules summary ----------
-- 1. Pilot: Nowshera village + Pindi Gheb city.
-- 2. Customer CNIC not required. Vendor CNIC optional (if added later).
-- 3. Vendor sets delivery area, delivery fee and opening hours.
-- 4. Only admin-approved shops appear publicly and can receive website orders.
-- 5. Minimum product subtotal Rs.500.
-- 6. OnClick commission = 5% of product subtotal only; delivery is excluded.
-- 7. Pilot payment is directly to merchant; no online gateway and no COD system.
-- 8. Merchant arranges its own delivery.
-- 9. Phone/manual orders are allowed for approved vendors and must be marked by source.
-- 10. Vendor cannot approve its own shop or change approval/suspension controls.
-- 11. Customer/vendor permissions are blocked while suspended/banned.
-- 12. Admin can warn, suspend, ban, unban, approve/reject/suspend shops and review audit history.
-- 13. Reasons and timestamps are retained for moderation actions.
-- 14. No rider network, rider marketplace, informal-stall selling, representative sellers, live tracking or large logistics in this MVP.
-- 15. Future rider/informal-vendor features remain deferred.
--
-- ADMIN BOOTSTRAP:
-- 1) Create/login your own account on the website.
-- 2) Supabase > Authentication > Users > copy your user's UUID.
-- 3) Run:
-- update public.profiles set role='admin' where id='YOUR-AUTH-USER-UUID';
