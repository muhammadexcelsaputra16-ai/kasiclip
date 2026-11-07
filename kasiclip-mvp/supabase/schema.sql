-- KasiClip MVP schema. Run in Supabase SQL Editor.
create extension if not exists pgcrypto;
create type public.app_role as enum ('admin','campaigner','clipper');
create type public.campaign_status as enum ('draft','pending_review','active','paused','completed','rejected');
create type public.review_status as enum ('pending_review','approved','rejected');
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text,
 role public.app_role not null default 'clipper',
 verification_status text not null default 'unverified' check (verification_status in ('unverified','pending','verified','rejected','suspended')),
 created_at timestamptz not null default now()
);
create table public.campaigns (
 id uuid primary key default gen_random_uuid(), campaigner_id uuid not null references public.profiles(id),
 title text not null, brand_name text not null, description text, brief text not null,
 platform text not null, distribution_mode text not null check(distribution_mode in ('performance','algorithmic')),
 budget_total numeric(18,2) not null check(budget_total>0), budget_remaining numeric(18,2) not null check(budget_remaining>=0),
 reward_rate numeric(18,6) not null check(reward_rate>0), duration_days integer not null default 14,
 status public.campaign_status not null default 'pending_review', created_at timestamptz not null default now()
);
create table public.verification_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id), platform text not null,
 profile_url text not null, verification_code text not null, status public.review_status not null default 'pending_review',
 reviewer_id uuid references public.profiles(id), reviewed_at timestamptz, created_at timestamptz not null default now()
);
create table public.submissions (
 id uuid primary key default gen_random_uuid(), clipper_id uuid not null references public.profiles(id), campaign_id uuid not null references public.campaigns(id),
 content_url text not null, claimed_views bigint not null default 0 check(claimed_views>=0), approved_views bigint,
 proof_url text not null, status public.review_status not null default 'pending_review', reward_amount numeric(18,2) not null default 0,
 reviewer_id uuid references public.profiles(id), reviewed_at timestamptz, created_at timestamptz not null default now(),
 unique(clipper_id,campaign_id,content_url)
);
create table public.ledger (
 id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id), campaign_id uuid references public.campaigns(id), submission_id uuid references public.submissions(id),
 entry_type text not null check(entry_type in ('creator_reward','platform_distribution_fee','activation_fee','withdrawal_fee','withdrawal_debit','campaign_funding','refund','adjustment')),
 amount numeric(18,2) not null, direction text not null check(direction in ('credit','debit')), description text, idempotency_key text unique, created_at timestamptz not null default now()
);
create table public.withdrawals (
 id uuid primary key default gen_random_uuid(), clipper_id uuid not null references public.profiles(id), amount numeric(18,2) not null check(amount>=50000),
 fee numeric(18,2) not null, net_amount numeric(18,2) not null, status text not null default 'requested' check(status in ('requested','processing','approved','paid','rejected')),
 payout_method text, payout_account text, admin_note text, processed_by uuid references public.profiles(id), created_at timestamptz not null default now(), paid_at timestamptz
);
create table public.campaign_applications (
 id uuid primary key default gen_random_uuid(), campaign_id uuid not null references public.campaigns(id), clipper_id uuid not null references public.profiles(id),
 status text not null default 'joined' check(status in ('joined','left','blocked')), created_at timestamptz not null default now(), unique(campaign_id,clipper_id)
);

create or replace function public.current_role() returns public.app_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid() $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(public.current_role()='admin',false) $$;

alter table public.profiles enable row level security;
alter table public.campaigns enable row level security;
alter table public.verification_requests enable row level security;
alter table public.submissions enable row level security;
alter table public.ledger enable row level security;
alter table public.withdrawals enable row level security;
alter table public.campaign_applications enable row level security;

create policy "profiles read self or admin" on public.profiles for select using (id=auth.uid() or public.is_admin());
create policy "new users create limited profile" on public.profiles for insert with check (id=auth.uid() and role in ('clipper','campaigner'));
-- Profile role and verification status are admin-controlled; users cannot self-promote or self-verify.
create policy "admin updates profiles" on public.profiles for update using (public.is_admin()) with check (public.is_admin());
create policy "campaigns visible active or owner or admin" on public.campaigns for select using (status='active' or campaigner_id=auth.uid() or public.is_admin());
create policy "campaigner create own campaign" on public.campaigns for insert with check (campaigner_id=auth.uid() and public.current_role()='campaigner');
create policy "admin update campaigns" on public.campaigns for update using (public.is_admin()) with check (public.is_admin());
create policy "verification own read" on public.verification_requests for select using (user_id=auth.uid() or public.is_admin());
create policy "verification own create" on public.verification_requests for insert with check (user_id=auth.uid());
create policy "verification admin update" on public.verification_requests for update using (public.is_admin()) with check (public.is_admin());
create policy "submission owner or admin read" on public.submissions for select using (clipper_id=auth.uid() or public.is_admin());
create policy "clipper creates own submission" on public.submissions for insert with check (clipper_id=auth.uid() and public.current_role()='clipper');
create policy "admin reviews submissions" on public.submissions for update using (public.is_admin()) with check (public.is_admin());
create policy "ledger owner or admin read" on public.ledger for select using (user_id=auth.uid() or public.is_admin());
create policy "withdrawal owner or admin read" on public.withdrawals for select using (clipper_id=auth.uid() or public.is_admin());
create policy "clipper requests own withdrawal" on public.withdrawals for insert with check (clipper_id=auth.uid() and public.current_role()='clipper');
create policy "admin processes withdrawal" on public.withdrawals for update using (public.is_admin()) with check (public.is_admin());
create policy "applications own read" on public.campaign_applications for select using (clipper_id=auth.uid() or public.is_admin());
create policy "clipper joins campaign" on public.campaign_applications for insert with check (clipper_id=auth.uid() and public.current_role()='clipper');

-- Admin must be assigned manually from trusted SQL Editor after creating the account:
-- update public.profiles set role='admin' where id='AUTH_USER_UUID';
