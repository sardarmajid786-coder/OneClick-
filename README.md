# OnClick Phase-1 — Clean Trial Website

This package replaces the mixed login flow with separate Customer, Vendor and Admin pages.

## Pages
- `index.html` — public landing page only; no shops/products shown.
- `customer-login.html` / `customer-signup.html`
- `vendor-login.html` / `vendor-signup.html`
- `admin-login.html` — separate private admin login.
- `customer.html` — local approved shops, product search/comparison and ordering.
- `vendor.html` — create shop and add products.
- `admin.html` — customer/vendor moderation, shop approval/suspension, orders and audit history.

## Supabase
1. Run `setup.sql` in the Supabase SQL Editor.
2. Create the Admin account in Supabase Authentication > Users.
3. Copy the Admin user's UUID and run the update statement at the bottom of `setup.sql`.
4. Never put a Supabase secret/service-role key in this website or GitHub.

## Trial rules included
- Vendor accounts are pending until Admin action.
- Shops are pending until Admin approval.
- Only approved + open shops appear to customers.
- Customer area and shop service area are matched by text for the first trial.
- Minimum order: Rs. 500.
- OnClick commission: 5% of product subtotal, excluding delivery.
- Customer pays merchant directly during the pilot.
- Merchant handles delivery.
- Product fields: name, category, description, regular price, sale price, available/out of stock, optional image URL.

## Important
This is the clean Phase-1 code package. It is not automatically deployed to GitHub Pages. Upload/replace the files in the GitHub repository before testing the live website.
