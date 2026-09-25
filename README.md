# OnClick — Final MVP package

This package is the consolidated OnClick website + Supabase MVP setup.

## Included
- Customer, Vendor and Admin roles
- Admin-only shop approval/rejection
- Customer/Vendor warning, suspension, ban and reactivation controls
- Audit history for moderation and important record changes
- Backend role/RLS protection (not just hidden buttons)
- Product catalog, cart and checkout
- Rs.500 minimum product subtotal
- 5% OnClick commission on product subtotal only; delivery excluded
- Merchant-direct payment during pilot; no gateway/COD infrastructure
- Merchant-arranged delivery with vendor delivery area/fee/hours
- Website and phone/manual order source support
- Order status flow and cancellation reason
- Pilot zone: Nowshera village + Pindi Gheb city
- English-first UI with Urdu-ready structure

## One-time setup
1. Replace the old website files in the GitHub repository with these package files.
2. Run the complete `setup.sql` once in Supabase SQL Editor.
3. Create/login to your own website account.
4. In Supabase Authentication > Users, copy your UUID.
5. In SQL Editor run:
   `update public.profiles set role='admin' where id='YOUR-AUTH-USER-UUID';`

## Security
Use only the publishable key in `supabase-config.js`.
Never put a Supabase Secret/service_role key in GitHub or browser code.
Because a Secret key was previously exposed during setup, rotate/revoke that old secret in Supabase before final launch.

## Deferred features (not MVP)
Rider network, live rider tracking, riders selling goods, representative-managed sellers without phones, large logistics and local-services marketplace remain future phases.
