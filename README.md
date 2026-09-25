# OnClick — live Supabase MVP starter

This version is designed for GitHub Pages + Supabase.

## Included
- Live approved shops from `shops`
- Live available products from `products`
- Customer/vendor email-password signup/login via Supabase Auth
- Vendor role captured at signup
- Cart and checkout
- Rs.500 minimum order
- 5% commission on product subtotal only
- Merchant-direct payment during pilot
- Merchant delivery fee from the shop
- Basic Urdu/English UI toggle

## One-time Supabase step
Run `setup.sql` in Supabase SQL Editor. It creates the Auth -> profiles trigger and tightens order-item/vendor order policies.

## Important
Only the Supabase Publishable key is in `supabase-config.js`. Never put the Secret/service_role key in the browser or GitHub.

## Admin
After creating your own account, get your Auth user UUID from Supabase Authentication and set that profile to admin using the commented SQL in `setup.sql`. Admin dashboard UI can then be added as the next phase.
