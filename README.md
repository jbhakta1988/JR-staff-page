HotelHQ — JR Hospitality staff portal

Demo mode is the default. It uses example names and example PINs, never calls Supabase, and cannot see real staff or hotel data.

Live sign-in uses Supabase Auth. The PIN is the password. The publishable key is not stored in git. See `config.js` and `supabase/seed/corporate_account.sql`.

PINs that were shipped in the public website are in git history. Do not reuse them.
