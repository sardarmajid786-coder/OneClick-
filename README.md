# OnClick Phase-1 — First Admin + Approval System

## What changed
- Customer and Vendor remain separate on the public landing page.
- Admin has a separate private login.
- Added `admin-signup.html` for the **one-time First/Master Admin setup**.
- The First/Master Admin email is locked to `sardarmajid786@gmail.com` in the bootstrap function.
- Existing Auth account can be promoted to Master Admin; no duplicate Auth account is required.
- Customer and Vendor signups start as `pending` and need Admin approval.
- Added `admin-team-request.html` for future team requests.
- Admin Dashboard can approve/reject Admin Team requests.
- Admin can activate/suspend customer/vendor accounts and approve/suspend shops.
- `ensure_my_profile()` repairs profiles for Auth users created before the trigger existed.

## IMPORTANT — do this once
1. Open Supabase Dashboard → SQL Editor.
2. Run the complete `setup.sql` file.
3. Open:
   `https://sardarmajid786-coder.github.io/OneClick-/admin-signup.html`
4. Enter the password of the existing `sardarmajid786@gmail.com` Auth account.
5. Tap **Activate First Admin**.
6. It should open `admin.html`.
7. Later use:
   `https://sardarmajid786-coder.github.io/OneClick-/admin-login.html`

## If the First Admin setup says the account does not exist
Create the Auth user in Supabase Authentication using the master email, then return to `admin-signup.html` and sign in with that password.

## Security model
- Ordinary signup can create only Customer or Vendor.
- Public users cannot self-promote to Admin.
- Only the first master email can claim the first Admin slot.
- After the first Admin exists, future Admin Team members require an Admin request and approval.
- Admin dashboard and admin RPC functions re-check the Admin role server-side.
- Never put a Supabase secret/service-role key in GitHub or frontend files.
