# KasiClip — Creator Clipping & Brand Campaign Management

**KasiClip** is a creator clipping platform and brand campaign management workspace.

- Product: **KasiClip**
- Brand attribution: **By KasiFakta**
- Supporting organization: **KasiMediaGroup**
- Product direction: public SaaS landing page + separate Creator, Brand/Campaigner, and private Admin workspaces.
- Design direction: clean, editorial SaaS marketplace inspired by Konten.com. This is an original implementation, not a copy of its assets or source code.

## Stack

- Next.js 15 / React 19 / TypeScript
- Supabase Auth, PostgreSQL, Row Level Security, Storage, SQL RPCs
- Vercel deployment
- `@supabase/ssr` cookie-based auth for protected workspace routes

## Workspaces and routes

| Route | Access |
|---|---|
| `/` | Public landing page |
| `/login` | Login |
| `/register` | Signup as Creator/Clipper or Brand/Campaigner |
| `/creator` | Verified Creator workspace |
| `/brand` | Brand/Campaigner workspace |
| `/admin` | Private Admin workspace; no public navigation link |

The middleware redirects unauthenticated users and checks the account role. Database RPCs and RLS enforce authorization again; hiding the Admin link is not treated as security.

## Implemented product flows

### Public landing page

- Product positioning and dual CTA for Creator and Brand.
- How it works, Brand and Creator value propositions, campaign simulator example, FAQ, and attribution footer.
- Responsive desktop/mobile layout.

### Creator / Clipper

- Creator registration and login.
- Creator verification request with a persistent `kc-` code. The same pending request/code is returned on refresh; it is not regenerated on reload. The code is invalidated after approval, rejection, or expiry.
- Manual account ownership review using social profile URL and bio code.
- Campaign marketplace and join flow (verified creators only).
- Content submission with content URL, claimed views, and private Insights screenshot upload.
- Submission history and approved views.
- Reward formula: `approved views × campaign CPM ÷ 1,000`.
- Fractional reward precision retained to 6 decimal places in the database.
- Campaign-based attribution retained in the ledger.
- Cloud Reward accumulates across campaigns. Minimum claim milestone is Rp1,000; claiming moves the accrued amount to the wallet without recalculating or duplicating the reward.
- Wallet balance, withdrawal request, payout method/account, fee preview, and withdrawal history.
- Payout methods: DANA, GoPay, ShopeePay, OVO, and bank transfer.

### Brand / Campaigner

- Brand registration and login.
- Brand verification request: business type/legal identity, brand, authorized representative, contact details, bank/account ownership and optional supporting document.
- Campaign creation with brief, platform, Performance or Algorithmic Reach distribution mode, duration, creator limit, budget, and creator reward CPM.
- Live budget / CPM / potential views simulator: `budget ÷ CPM × 1,000`.
- Manual campaign deposit submission with sender bank, account name/number, reference, and private proof upload.
- Campaign activation requires both confirmed deposit and Admin campaign approval.
- Campaign list, budget monitoring, submission performance, and joined creator management.

### Admin (`/admin`)

- Admin role assigned only through trusted Supabase SQL Editor.
- Deposit review and confirmation/rejection.
- Campaign approval/rejection after confirmed payment.
- Creator verification review.
- Brand verification review.
- Submission review and approved-view entry. Reward is calculated server-side, campaign budget is locked and deducted atomically, and a ledger entry is written exactly once.
- Withdrawal processing, paid marking, rejection and wallet refund.
- User activation/suspension.
- Payment instruction settings shown to Brand/Campaigner.
- Internal KasiClip campaign creation.

## Financial and campaign rules

- Campaign budget is deducted when a submission's reward is approved, not when the creator submits claimed views.
- Each campaign retains its own CPM/reward rate and budget attribution.
- The backend locks the campaign row during approval and rejects reward amounts above remaining campaign budget. Admin can approve a lower valid view count when appropriate.
- A campaign stops accepting new submissions after its end time or when its budget is exhausted.
- Submissions created during the active campaign period can still be reviewed after a time-based campaign end, provided budget remains. A budget-exhausted campaign cannot pay additional rewards.
- Withdrawal minimum: Rp50,000.
- Current withdrawal fee tiers in the SQL function: up to Rp250,000 = Rp2,500; up to Rp500,000 = Rp3,000; up to Rp1,000,000 = Rp5,000; up to Rp2,500,000 = Rp7,500; above Rp2,500,000 = Rp10,000.
- Withdrawal requests reserve the full amount from the wallet. Rejected requests refund the reservation; fee revenue is reversed as well.
- The ledger separates creator reward accrual, reward claim, wallet credit, withdrawal reservation/refund, and platform fee revenue.

## Payment / API limitations (intentional MVP boundary)

This project does **not** claim to have a live payment gateway, automatic Virtual Account issuance, automated e-wallet payout, Instagram/TikTok/YouTube API integration, or automatic social-view verification.

- Brand deposits are currently bank-transfer + private proof upload + Admin manual reconciliation.
- Creator payouts are currently Admin-processed manual transfers. The request, wallet reservation, status, and fee ledger are implemented, but the actual transfer is not automated.
- Social views are manually checked using the submitted content URL and screenshot evidence.
- In-app notifications are recorded in the database. WhatsApp/Discord delivery requires a chosen provider/webhook and server-side credentials; those external channels are not activated in this build.

Never accept real money or promise automated payouts until the payment provider, reconciliation, payout, operational controls, and end-to-end tests are configured.

## Setup

1. Create a Supabase project.
2. Open Supabase SQL Editor and run `supabase/schema.sql`.
   - The script is designed to work with the previous KasiClip starter schema as well as a fresh project. Review it against your current database before running on production.
3. In Supabase Authentication, configure the allowed site URL and redirect URLs for local development and your Vercel domain.
4. For production email delivery, configure a custom SMTP provider and appropriate rate limits. Supabase's default email service is not intended for high-volume production onboarding.
5. Copy `.env.example` to `.env.local` and set the Supabase Project URL and anon/publishable key.
6. Install Node.js 20+ and run:

   ```bash
   npm install
   npm run dev
   ```

7. Open `http://localhost:3000`, register the first account, and confirm its email if email confirmation is enabled.
8. Assign the first Admin from Supabase SQL Editor:

   ```sql
   update public.profiles
   set role = 'admin'
   where id = 'AUTH_USER_UUID';
   ```

9. Sign out and sign in again. Open `/admin` directly. There is no Admin link on the public website.
10. In Admin → Platform settings, configure the bank transfer details that Brand/Campaigner sees before making a deposit.

## Supabase Storage

The SQL creates a private bucket named `kasiclip-private` with a 10 MB file limit. Upload paths begin with the authenticated user's UUID. Admin can create short-lived signed URLs for review. Do not make evidence files public.

## Campaign maintenance / H-3 notifications

The SQL function `public.refresh_campaign_states()` closes campaigns whose time or budget has ended and creates in-app H-3 / low-budget notifications. To automate it, enable the `pg_cron` extension in Supabase (if available on the project), then schedule it from SQL Editor:

```sql
select cron.schedule(
  'kasiclip-campaign-maintenance',
  '*/30 * * * *',
  $$select public.refresh_campaign_states();$$
);
```

If `pg_cron` is unavailable on the selected Supabase plan/project, run the function from a trusted scheduled backend job. Do not expose it as a public client action.

## Environment variables

Only the Supabase public URL and anon/publishable key are required for this MVP. Never put a Supabase service-role key in a `NEXT_PUBLIC_` variable or browser code.

## Validation status

- TypeScript source was checked with the globally available TypeScript compiler and temporary Next.js type stubs.
- A full `next build` could not be completed in the editing environment because the uploaded `node_modules` folder was incomplete and package installation timed out. Run `npm install` and `npm run build` in the target environment before deploying.
- The SQL must be applied to a Supabase project and tested with separate Admin, Brand, and Creator accounts before production use.

## Production hardening still required

- Configure production SMTP, domain, legal pages, data retention, and privacy controls.
- Set up scheduled campaign maintenance and optional WhatsApp/Discord notification delivery.
- Integrate a licensed payment/VA provider and payout provider before automating money movement.
- Add operational reconciliation, refunds, disputes, abuse/fraud review, creator content policy, and finance reporting.
- Run end-to-end tests with separate accounts and real Supabase RLS; review SQL migration output and backups before applying to a live database.
