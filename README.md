# OnClick — Supabase-connected starter

This package uses the Supabase Project URL and browser-safe Publishable key supplied by the project owner.

It can:
- load approved shops from `shops` when data exists;
- load available products when a live shop is opened;
- fall back to sample pilot shops when tables are empty;
- keep the existing responsive OnClick design.

Security:
- Only the Supabase Publishable key is included in browser code.
- Never put a Supabase Secret/service_role key in HTML, JavaScript, or GitHub.

Current backend policies still need the final customer/vendor Auth and order workflow before this is a production ordering site.
