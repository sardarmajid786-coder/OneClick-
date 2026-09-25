-- OnClick one-time Supabase setup for Auth/Profile workflow.
-- Run this in Supabase SQL Editor. NEVER put the Secret/service_role key in the website.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    coalesce(new.raw_user_meta_data->>'phone',''),
    case when new.raw_user_meta_data->>'role' = 'vendor' then 'vendor' else 'customer' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Helpful policy for a user to create/read their own profile.
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
for insert to authenticated
with check (id = auth.uid());

-- Customer order items: only allow an item to reference the customer's own order.
drop policy if exists "order_items_insert_own_order" on public.order_items;
create policy "order_items_insert_own_order" on public.order_items
for insert to authenticated
with check (exists (select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid()));

-- Vendor can only update orders belonging to their shop.
drop policy if exists "orders_vendor_update" on public.orders;
create policy "orders_vendor_update" on public.orders
for update to authenticated
using (exists (select 1 from public.shops s where s.id = shop_id and s.vendor_id = auth.uid()) or private.is_admin())
with check (exists (select 1 from public.shops s where s.id = shop_id and s.vendor_id = auth.uid()) or private.is_admin());

-- Optional admin bootstrap: after creating your own account, run ONE statement manually:
-- update public.profiles set role='admin' where id='YOUR_AUTH_USER_UUID';
