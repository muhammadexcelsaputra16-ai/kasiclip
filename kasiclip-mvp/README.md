# KasiClip MVP (starter)

Next.js + Supabase starter for KasiClip's three-role workflow: Admin, Campaigner, Clipper.

## Included in this first build
- Email/password sign-up and login.
- Role-based account profile (clipper/campaigner at signup; admin assigned only by trusted SQL).
- Campaign submission form with Performance / Algorithmic Reach modes.
- Manual bio verification request with unique verification code.
- Manual content/view submission with evidence URL.
- Withdrawal fee preview and withdrawal request form.
- Supabase PostgreSQL schema and initial RLS policies.
- Responsive dark dashboard UI.

## Setup
1. Create a Supabase project.
2. Open SQL Editor and run `supabase/schema.sql`.
3. Copy `.env.example` to `.env.local` and fill the Supabase project URL and anon key.
4. Install Node.js 20+.
5. Run `npm install`, then `npm run dev`.
6. Create your first account. To assign admin, find the user's UUID in Supabase Auth and run the admin SQL comment at the bottom of `schema.sql`.

## Important implementation status
This is a functional MVP scaffold, not a production-ready payment system. Before real money is accepted or paid, implement and test:
- Atomic server-side approval of submissions that calculates reward, checks remaining campaign budget, writes ledger entries, and applies distribution fee exactly once.
- Wallet balance aggregation and withdrawal reservation/settlement to prevent double spending.
- Campaigner funding and payment gateway reconciliation.
- Admin-only review UI and audit log for every state transition.
- Private evidence storage (Supabase Storage with signed URLs), not public arbitrary proof URLs.
- Server-side validation, rate limiting, email verification, password policy, abuse prevention, and privacy/terms pages.
- App-side authorization: never rely only on hidden UI controls.

## Current fee assumptions (configurable later)
- Campaign activation fee: Rp50,000 (proposal)
- Distribution fee: 10% of approved creator reward distribution (proposal)
- Withdrawal fee: <= Rp250,000: Rp2,500; <= Rp500,000: Rp3,000; <= Rp1,000,000: Rp5,000; <= Rp2,500,000: Rp7,500; above: Rp10,000.
- Minimum withdrawal: Rp50,000 (proposal)

## Important product rule
Reward is calculated per campaign using that campaign's own rate and eligible approved views. The clipper dashboard can aggregate reward across campaigns, but the backend must retain campaign attribution. Fractional views-based calculations should be retained to cents (or more precise) in the ledger; display rounding is separate.
