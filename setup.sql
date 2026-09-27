-- OnClick Phase-1: First/Master Admin + Customer/Vendor approval + Admin Team requests
-- Run this whole file in Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  phone text,
  service_area text,
  role text not null default 'customer' check (role in ('customer','vendor','admin')),
  account_status text not null default 'pending' check (account_status in ('pending','active','suspended','banned')),
  created_at timestamptz not null default now()
);

create table if not exists public.shops (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  category text,
  address text,
  service_area text,
  delivery_fee numeric not null default 0,
  is_approved boolean not null default false,
  is_open boolean not null default false,
  opening_hours text,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null,
  category text,
  description text,
  regular_price numeric not null default 0,
  sale_price numeric,
  available boolean not null default true,
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  shop_id uuid not null references public.shops(id),
  order_source text not null default 'Website',
  customer_name text,
  customer_phone text,
  delivery_address text,
  product_subtotal numeric not null default 0,
  delivery_fee numeric not null default 0,
  commission_rate numeric not null default .05,
  commission_amount numeric not null default 0,
  customer_total numeric not null default 0,
  payment_method text default 'Pay merchant directly',
  status text not null default 'pending',
  cancel_reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text,
  quantity integer not null default 1,
  unit_price numeric not null default 0
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  admin_id uuid references public.profiles(id),
  action text not null,
  target_type text,
  target_id uuid,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  decided_by uuid references public.profiles(id),
  decision_reason text,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

-- Backward-compatible columns for the previous Phase-1 database.
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists service_area text;
alter table public.profiles add column if not exists account_status text not null default 'pending';
alter table public.shops add column if not exists service_area text;
alter table public.products add column if not exists category text;
alter table public.products add column if not exists regular_price numeric not null default 0;
alter table public.products add column if not exists sale_price numeric;
alter table public.order_items add column if not exists product_name text;
alter table public.order_items add column if not exists quantity integer not null default 1;
alter table public.order_items add column if not exists unit_price numeric not null default 0;

-- Preserve old products.price if it exists.
do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='price') then
    execute 'update public.products set regular_price = price where (regular_price is null or regular_price = 0) and price is not null';
  end if;
end $$;

create schema if not exists private;

create or replace function private.is_admin()
returns boolean language sql security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and account_status='active');
$$;

create or replace function private.is_vendor()
returns boolean language sql security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='vendor' and account_status='active');
$$;

-- New users can only become customer/vendor. Admin is never created by ordinary signup.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
declare r text;
begin
  r := coalesce(new.raw_user_meta_data->>'signup_role','customer');
  if r not in ('customer','vendor') then r := 'customer'; end if;
  insert into public.profiles(id,full_name,email,phone,service_area,role,account_status)
  values(new.id,new.raw_user_meta_data->>'full_name',new.email,new.raw_user_meta_data->>'phone',new.raw_user_meta_data->>'service_area',r,'pending')
  on conflict(id) do update set email=excluded.email;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Repairs accounts that were created before the trigger/profile existed.
insert into public.profiles(id,full_name,email,phone,service_area,role,account_status)
select u.id,
       coalesce(u.raw_user_meta_data->>'full_name',''),
       u.email,
       u.raw_user_meta_data->>'phone',
       u.raw_user_meta_data->>'service_area',
       case when u.raw_user_meta_data->>'signup_role'='vendor' then 'vendor' else 'customer' end,
       'pending'
from auth.users u
where not exists(select 1 from public.profiles p where p.id=u.id);

update public.profiles p
set email=u.email
from auth.users u
where p.id=u.id and (p.email is null or p.email='');

alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.audit_logs enable row level security;
alter table public.admin_requests enable row level security;

drop policy if exists profiles_self_select on public.profiles;
drop policy if exists profiles_admin_all on public.profiles;
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_self_select on public.profiles for select to authenticated using(id=auth.uid() or private.is_admin());
create policy profiles_admin_update on public.profiles for update to authenticated using(private.is_admin()) with check(private.is_admin());

-- Shop/product policies.
drop policy if exists shops_public_approved on public.shops;
drop policy if exists shops_vendor_insert on public.shops;
drop policy if exists shops_vendor_update on public.shops;
drop policy if exists shops_vendor_delete on public.shops;
create policy shops_public_approved on public.shops for select using((is_approved=true and is_open=true) or vendor_id=auth.uid() or private.is_admin());
create policy shops_vendor_insert on public.shops for insert to authenticated with check(vendor_id=auth.uid() and private.is_vendor());
create policy shops_vendor_update on public.shops for update to authenticated using(vendor_id=auth.uid() or private.is_admin()) with check(vendor_id=auth.uid() or private.is_admin());
create policy shops_vendor_delete on public.shops for delete to authenticated using(vendor_id=auth.uid() or private.is_admin());

drop policy if exists products_public_available on public.products;
drop policy if exists products_vendor_insert on public.products;
drop policy if exists products_vendor_update on public.products;
drop policy if exists products_vendor_delete on public.products;
create policy products_public_available on public.products for select using(available=true or private.is_vendor() or private.is_admin());
create policy products_vendor_insert on public.products for insert to authenticated with check(private.is_vendor() and exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()));
create policy products_vendor_update on public.products for update to authenticated using((private.is_vendor() and exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid())) or private.is_admin()) with check(private.is_vendor() or private.is_admin());
create policy products_vendor_delete on public.products for delete to authenticated using((private.is_vendor() and exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid())) or private.is_admin());

-- Orders.
drop policy if exists orders_select_parties on public.orders;
drop policy if exists orders_customer_insert on public.orders;
drop policy if exists orders_vendor_admin_update on public.orders;
create policy orders_select_parties on public.orders for select to authenticated using(customer_id=auth.uid() or private.is_admin() or exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()));
create policy orders_customer_insert on public.orders for insert to authenticated with check(customer_id=auth.uid());
create policy orders_vendor_admin_update on public.orders for update to authenticated using(private.is_admin() or exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid())) with check(private.is_admin() or exists(select 1 from public.shops s where s.id=shop_id and s.vendor_id=auth.uid()));

drop policy if exists order_items_select_parties on public.order_items;
drop policy if exists order_items_customer_insert on public.order_items;
create policy order_items_select_parties on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and (o.customer_id=auth.uid() or private.is_admin() or exists(select 1 from public.shops s where s.id=o.shop_id and s.vendor_id=auth.uid()))));
create policy order_items_customer_insert on public.order_items for insert to authenticated with check(exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()));

-- Audit/admin request policies.
drop policy if exists audit_admin_select on public.audit_logs;
create policy audit_admin_select on public.audit_logs for select to authenticated using(private.is_admin());

drop policy if exists admin_requests_self_insert on public.admin_requests;
drop policy if exists admin_requests_self_select on public.admin_requests;
drop policy if exists admin_requests_admin_all on public.admin_requests;
create policy admin_requests_self_insert on public.admin_requests for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='customer' and p.account_status='active'));
create policy admin_requests_self_select on public.admin_requests for select to authenticated using(user_id=auth.uid() or private.is_admin());
create policy admin_requests_admin_all on public.admin_requests for update to authenticated using(private.is_admin()) with check(private.is_admin());

-- Create/repair a profile for an already-existing Auth account.
create or replace function public.ensure_my_profile()
returns public.profiles language plpgsql security definer set search_path=public as $$
declare p public.profiles; u auth.users; r text;
begin
  select * into u from auth.users where id=auth.uid();
  if u.id is null then raise exception 'Not signed in'; end if;
  select * into p from public.profiles where id=u.id;
  if p.id is null then
    r:=coalesce(u.raw_user_meta_data->>'signup_role','customer');
    if r not in ('customer','vendor') then r:='customer'; end if;
    insert into public.profiles(id,full_name,email,phone,service_area,role,account_status)
    values(u.id,u.raw_user_meta_data->>'full_name',u.email,u.raw_user_meta_data->>'phone',u.raw_user_meta_data->>'service_area',r,'pending') returning * into p;
  else
    update public.profiles set email=coalesce(public.profiles.email,u.email) where id=u.id returning * into p;
  end if;
  return p;
end; $$;

-- FIRST / MASTER ADMIN bootstrap.
-- Only this exact bootstrap email can claim the first Admin slot.
create or replace function public.bootstrap_first_admin(master_email text, full_name text default null, phone text default null)
returns public.profiles language plpgsql security definer set search_path=public as $$
declare p public.profiles; u auth.users; admins integer;
begin
  select * into u from auth.users where id=auth.uid();
  if u.id is null then raise exception 'Not signed in'; end if;
  if lower(coalesce(u.email,'')) <> lower('sardarmajid786@gmail.com') or lower(coalesce(master_email,'')) <> lower('sardarmajid786@gmail.com') then
    raise exception 'This email is not authorized for first Admin setup';
  end if;
  select count(*) into admins from public.profiles where role='admin';
  if admins > 0 and not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'A Master/Admin account already exists';
  end if;
  insert into public.profiles(id,full_name,email,phone,role,account_status)
  values(u.id,coalesce(full_name,u.raw_user_meta_data->>'full_name','Master Admin'),u.email,coalesce(phone,u.raw_user_meta_data->>'phone'),'admin','active')
  on conflict(id) do update set full_name=excluded.full_name,email=excluded.email,phone=excluded.phone,role='admin',account_status='active'
  returning * into p;
  insert into public.audit_logs(admin_id,action,target_type,target_id,reason) values(u.id,'first_admin_bootstrap','profile',u.id,'Master Admin initial setup');
  return p;
end; $$;

-- Future team member requests.
create or replace function public.request_admin_role(reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='customer' and account_status='active') then raise exception 'Only an active customer account can request Admin Team access'; end if;
  insert into public.admin_requests(user_id,reason,status) values(auth.uid(),reason,'pending')
  on conflict(user_id) do update set reason=excluded.reason,status='pending',decided_by=null,decision_reason=null,decided_at=null
  returning id into rid;
  return rid;
end; $$;

create or replace function public.admin_set_account_status(target_user_id uuid,new_status text,reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then raise exception 'Admin access required'; end if;
  if new_status not in ('active','suspended','banned') then raise exception 'Invalid status'; end if;
  if target_user_id=auth.uid() then raise exception 'Admin cannot change own status'; end if;
  update public.profiles set account_status=new_status where id=target_user_id;
  insert into public.audit_logs(admin_id,action,target_type,target_id,reason) values(auth.uid(),'account_status','profile',target_user_id,reason);
end; $$;

create or replace function public.admin_decide_admin_request(request_id uuid,approve boolean,reason text)
returns void language plpgsql security definer set search_path=public as $$
declare uid uuid;
begin
  if not private.is_admin() then raise exception 'Admin access required'; end if;
  select user_id into uid from public.admin_requests where id=request_id and status='pending';
  if uid is null then raise exception 'Pending Admin request not found'; end if;
  if approve then
    update public.profiles set role='admin',account_status='active' where id=uid;
    update public.admin_requests set status='approved',decided_by=auth.uid(),decision_reason=reason,decided_at=now() where id=request_id;
    insert into public.audit_logs(admin_id,action,target_type,target_id,reason) values(auth.uid(),'admin_request_approved','profile',uid,reason);
  else
    update public.admin_requests set status='rejected',decided_by=auth.uid(),decision_reason=reason,decided_at=now() where id=request_id;
    insert into public.audit_logs(admin_id,action,target_type,target_id,reason) values(auth.uid(),'admin_request_rejected','profile',uid,reason);
  end if;
end; $$;

create or replace function public.admin_approve_shop(target_shop_id uuid,approve boolean,reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then raise exception 'Admin access required'; end if;
  update public.shops set is_approved=approve where id=target_shop_id;
  insert into public.audit_logs(admin_id,action,target_type,target_id,reason) values(auth.uid(),case when approve then 'shop_approved' else 'shop_rejected' end,'shop',target_shop_id,reason);
end; $$;

create or replace function public.admin_suspend_shop(target_shop_id uuid,reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not private.is_admin() then raise exception 'Admin access required'; end if;
  update public.shops set is_open=false,is_approved=false where id=target_shop_id;
  insert into public.audit_logs(admin_id,action,target_type,target_id,reason) values(auth.uid(),'shop_suspended','shop',target_shop_id,reason);
end; $$;

revoke all on function public.ensure_my_profile() from public;
revoke all on function public.bootstrap_first_admin(text,text,text) from public;
revoke all on function public.request_admin_role(text) from public;
revoke all on function public.admin_set_account_status(uuid,text,text) from public;
revoke all on function public.admin_decide_admin_request(uuid,boolean,text) from public;
revoke all on function public.admin_approve_shop(uuid,boolean,text) from public;
revoke all on function public.admin_suspend_shop(uuid,text) from public;
grant execute on function public.ensure_my_profile() to authenticated;
grant execute on function public.bootstrap_first_admin(text,text,text) to authenticated;
grant execute on function public.request_admin_role(text) to authenticated;
grant execute on function public.admin_set_account_status(uuid,text,text) to authenticated;
grant execute on function public.admin_decide_admin_request(uuid,boolean,text) to authenticated;
grant execute on function public.admin_approve_shop(uuid,boolean,text) to authenticated;
grant execute on function public.admin_suspend_shop(uuid,text) to authenticated;

-- IMPORTANT: run this file before testing the new Admin Setup page.
