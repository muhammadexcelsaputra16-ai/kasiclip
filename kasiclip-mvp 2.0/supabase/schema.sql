-- KasiClip full MVP schema. Safe to re-run on a fresh/current project where possible.
-- Run in Supabase SQL Editor. Review existing objects before applying to production.
create extension if not exists pgcrypto;

do $$ begin create type public.app_role as enum ('admin','campaigner','clipper'); exception when duplicate_object then null; end $$;
do $$ begin create type public.campaign_status as enum ('draft','pending_review','active','paused','completed','rejected'); exception when duplicate_object then null; end $$;
do $$ begin create type public.review_status as enum ('pending_review','approved','rejected'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text,
 role public.app_role not null default 'clipper',
 verification_status text not null default 'unverified' check (verification_status in ('unverified','pending','verified','rejected','suspended')),
 avatar_url text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.profiles add column if not exists account_status text not null default 'active' check(account_status in ('active','suspended'));
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

create table if not exists public.brand_verifications (
 id uuid primary key default gen_random_uuid(), campaigner_id uuid not null references public.profiles(id) on delete cascade,
 business_type text not null, legal_name text not null, brand_name text not null, registration_number text,
 representative_name text not null, representative_role text not null, email text, phone text,
 bank_name text not null, bank_account_name text not null, bank_account_number text not null,
 document_path text, status text not null default 'pending' check(status in ('pending','verified','rejected','suspended')),
 admin_note text, reviewer_id uuid references public.profiles(id), reviewed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.campaigns (
 id uuid primary key default gen_random_uuid(), campaigner_id uuid not null references public.profiles(id),
 title text not null, brand_name text not null, category text, description text, brief text not null,
 platform text not null, distribution_mode text not null check(distribution_mode in ('performance','algorithmic')),
 budget_total numeric(18,2) not null check(budget_total>0), budget_remaining numeric(18,6) not null check(budget_remaining>=0),
 reward_rate numeric(18,6) not null check(reward_rate>0), duration_days integer not null default 14 check(duration_days between 1 and 180),
 start_at timestamptz, end_at timestamptz, status public.campaign_status not null default 'draft',
 payment_status text not null default 'unpaid' check(payment_status in ('unpaid','pending','confirmed','rejected','refunded')),
 creator_limit integer, rules text, is_internal boolean not null default false, completion_reason text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.campaigns alter column budget_remaining type numeric(18,6) using budget_remaining::numeric(18,6);
alter table public.campaigns add column if not exists category text;
alter table public.campaigns add column if not exists start_at timestamptz;
alter table public.campaigns add column if not exists end_at timestamptz;
alter table public.campaigns add column if not exists payment_status text not null default 'unpaid';
alter table public.campaigns add column if not exists creator_limit integer;
alter table public.campaigns add column if not exists rules text;
alter table public.campaigns add column if not exists is_internal boolean not null default false;
alter table public.campaigns add column if not exists completion_reason text;
alter table public.campaigns add column if not exists updated_at timestamptz not null default now();

create table if not exists public.campaign_deposits (
 id uuid primary key default gen_random_uuid(), campaign_id uuid not null references public.campaigns(id) on delete cascade,
 campaigner_id uuid not null references public.profiles(id), amount numeric(18,2) not null check(amount>0),
 payment_method text not null default 'bank_transfer', selected_bank text, payer_account_name text not null,
 payer_account_number text not null, payment_reference text, proof_path text,
 status text not null default 'pending' check(status in ('pending','confirmed','rejected','refunded')),
 admin_note text, reviewed_by uuid references public.profiles(id), reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.verification_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 platform text not null, profile_url text not null, verification_code text unique,
 status public.review_status not null default 'pending_review', expires_at timestamptz,
 reviewer_id uuid references public.profiles(id), admin_note text, reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
alter table public.verification_requests alter column verification_code drop not null;
alter table public.verification_requests add column if not exists expires_at timestamptz;
alter table public.verification_requests add column if not exists admin_note text;
with ranked_pending as (select id,row_number() over(partition by user_id order by created_at desc) as rn from public.verification_requests where status='pending_review') update public.verification_requests v set status='rejected',verification_code=null,admin_note='Superseded by latest pending request' from ranked_pending r where v.id=r.id and r.rn>1;
create unique index if not exists verification_one_pending_per_user on public.verification_requests(user_id) where status='pending_review';
create table if not exists public.campaign_applications (
 id uuid primary key default gen_random_uuid(), campaign_id uuid not null references public.campaigns(id) on delete cascade,
 clipper_id uuid not null references public.profiles(id) on delete cascade,
 status text not null default 'joined' check(status in ('joined','left','blocked')),
 created_at timestamptz not null default now(), unique(campaign_id,clipper_id)
);
create table if not exists public.submissions (
 id uuid primary key default gen_random_uuid(), clipper_id uuid not null references public.profiles(id), campaign_id uuid not null references public.campaigns(id),
 content_url text not null, claimed_views bigint not null default 0 check(claimed_views>=0), approved_views bigint,
 proof_path text not null, status public.review_status not null default 'pending_review', reward_amount numeric(18,6) not null default 0,
 reviewer_id uuid references public.profiles(id), admin_note text, reviewed_at timestamptz,
 created_at timestamptz not null default now(), unique(clipper_id,campaign_id,content_url)
);
alter table public.submissions alter column reward_amount type numeric(18,6) using reward_amount::numeric(18,6);
alter table public.submissions add column if not exists proof_path text;
alter table public.submissions add column if not exists admin_note text;
do $$ begin if exists(select 1 from information_schema.columns where table_schema='public' and table_name='submissions' and column_name='proof_url') then execute 'alter table public.submissions alter column proof_url drop not null'; end if; end $$;
do $$ begin if exists(select 1 from information_schema.columns where table_schema='public' and table_name='submissions' and column_name='proof_url') then execute 'update public.submissions set proof_path=proof_url where proof_path is null'; end if; end $$;
alter table public.submissions alter column proof_path set not null;

create table if not exists public.ledger (
 id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id), campaign_id uuid references public.campaigns(id),
 submission_id uuid references public.submissions(id), withdrawal_id uuid,
 entry_type text not null check(entry_type in ('creator_reward','reward_claim','wallet_credit','withdrawal_reservation','withdrawal_refund','withdrawal_fee','withdrawal_debit','platform_distribution_fee','activation_fee','campaign_funding','refund','adjustment','platform_revenue')),
 amount numeric(18,6) not null check(amount>=0), direction text not null check(direction in ('credit','debit')),
 description text, idempotency_key text unique, created_at timestamptz not null default now()
);
alter table public.ledger add column if not exists withdrawal_id uuid;

create table if not exists public.withdrawals (
 id uuid primary key default gen_random_uuid(), clipper_id uuid not null references public.profiles(id),
 amount numeric(18,6) not null check(amount>=50000), fee numeric(18,2) not null, net_amount numeric(18,6) not null,
 status text not null default 'requested' check(status in ('requested','processing','approved','paid','rejected')),
 payout_method text not null, payout_account_name text not null, payout_account_number text not null,
 admin_note text, processed_by uuid references public.profiles(id), created_at timestamptz not null default now(), paid_at timestamptz
);
alter table public.withdrawals alter column amount type numeric(18,6) using amount::numeric(18,6);
alter table public.withdrawals alter column net_amount type numeric(18,6) using net_amount::numeric(18,6);
alter table public.withdrawals add column if not exists payout_account_name text not null default '';
alter table public.withdrawals add column if not exists payout_account_number text not null default '';

do $$ begin alter table public.ledger add constraint ledger_withdrawal_fk foreign key(withdrawal_id) references public.withdrawals(id) on delete set null; exception when duplicate_object then null; end $$;
alter table public.ledger drop constraint if exists ledger_entry_type_check;
alter table public.ledger add constraint ledger_entry_type_check check(entry_type in ('creator_reward','reward_claim','wallet_credit','withdrawal_reservation','withdrawal_refund','withdrawal_fee','withdrawal_debit','platform_distribution_fee','activation_fee','campaign_funding','refund','adjustment','platform_revenue'));
alter table public.ledger alter column amount type numeric(18,6) using amount::numeric(18,6);

create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, body text not null, kind text not null default 'info', read_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.platform_settings (
 key text primary key, value jsonb not null, updated_by uuid references public.profiles(id), updated_at timestamptz not null default now()
);
insert into public.platform_settings(key,value) values
 ('payment_instructions','{"bank_name":"Diatur Admin","account_name":"KasiClip","account_number":"Hubungi Admin","note":"Instruksi pembayaran akan dikonfigurasi admin."}'::jsonb),
 ('withdrawal_fees','{"tiers":[{"max":250000,"fee":2500},{"max":500000,"fee":3000},{"max":1000000,"fee":5000},{"max":2500000,"fee":7500},{"max":null,"fee":10000}]}'::jsonb)
on conflict(key) do nothing;

-- Create a profile automatically; public signup can only choose clipper/campaigner.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare v_role public.app_role;
begin
 v_role := case when new.raw_user_meta_data->>'role'='campaigner' then 'campaigner'::public.app_role else 'clipper'::public.app_role end;
 insert into public.profiles(id,full_name,role) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),v_role)
 on conflict(id) do nothing;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.current_role() returns public.app_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid() and account_status='active' $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(public.current_role()='admin',false) $$;

-- Creator verification: one random code per active request; refreshes return the same request/code.
create or replace function public.request_creator_verification(p_platform text,p_profile_url text) returns public.verification_requests
language plpgsql security definer set search_path=public as $$
declare v_req public.verification_requests;
begin
 if auth.uid() is null or public.current_role()<>'clipper' then raise exception 'Akun creator diperlukan'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and verification_status='verified') then raise exception 'Akun creator sudah terverifikasi'; end if;
 select * into v_req from public.verification_requests where user_id=auth.uid() and status='pending_review' order by created_at desc limit 1;
 if found and (v_req.expires_at is null or v_req.expires_at>now()) then return v_req; end if;
 if found then update public.verification_requests set status='rejected',verification_code=null,admin_note='Verification challenge expired' where id=v_req.id; end if;
 insert into public.verification_requests(user_id,platform,profile_url,verification_code,expires_at)
 values(auth.uid(),p_platform,p_profile_url,'kc-'||lower(encode(gen_random_bytes(5),'hex')),now()+interval '14 days') returning * into v_req;
 update public.profiles set verification_status='pending',updated_at=now() where id=auth.uid();
 return v_req;
end $$;

create or replace function public.request_brand_verification(p_business_type text,p_legal_name text,p_brand_name text,p_registration_number text,p_rep_name text,p_rep_role text,p_email text,p_phone text,p_bank_name text,p_bank_account_name text,p_bank_account_number text,p_document_path text)
returns public.brand_verifications language plpgsql security definer set search_path=public as $$
declare v public.brand_verifications;
begin
 if auth.uid() is null or public.current_role()<>'campaigner' then raise exception 'Akun brand diperlukan'; end if;
 if p_document_path is not null and (storage.foldername(p_document_path))[1]<>auth.uid()::text then raise exception 'Dokumen brand tidak valid'; end if;
 select * into v from public.brand_verifications where campaigner_id=auth.uid() and status='pending' order by created_at desc limit 1;
 if found then raise exception 'Permintaan verifikasi brand masih diproses'; end if;
 insert into public.brand_verifications(campaigner_id,business_type,legal_name,brand_name,registration_number,representative_name,representative_role,email,phone,bank_name,bank_account_name,bank_account_number,document_path)
 values(auth.uid(),p_business_type,p_legal_name,p_brand_name,p_registration_number,p_rep_name,p_rep_role,p_email,p_phone,p_bank_name,p_bank_account_name,p_bank_account_number,p_document_path) returning * into v;
 return v;
end $$;

create or replace function public.create_campaign_with_deposit(
 p_title text,p_brand_name text,p_category text,p_description text,p_brief text,p_platform text,p_distribution_mode text,
 p_budget numeric,p_reward_rate numeric,p_duration integer,p_creator_limit integer,p_rules text,
 p_selected_bank text,p_payer_name text,p_payer_account text,p_payment_reference text,p_proof_path text
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if auth.uid() is null or public.current_role()<>'campaigner' then raise exception 'Akun campaigner diperlukan'; end if;
 if p_proof_path is null or (storage.foldername(p_proof_path))[1]<>auth.uid()::text then raise exception 'Bukti deposit tidak valid'; end if;
 if not exists(select 1 from public.brand_verifications where campaigner_id=auth.uid() and status='verified') then raise exception 'Verifikasi brand harus selesai sebelum membuat campaign'; end if;
 if p_budget<=0 or p_reward_rate<=0 or p_duration<1 then raise exception 'Budget, CPM, atau durasi tidak valid'; end if;
 insert into public.campaigns(campaigner_id,title,brand_name,category,description,brief,platform,distribution_mode,budget_total,budget_remaining,reward_rate,duration_days,creator_limit,rules,status,payment_status)
 values(auth.uid(),p_title,p_brand_name,p_category,p_description,p_brief,p_platform,p_distribution_mode,p_budget,p_budget,p_reward_rate,p_duration,p_creator_limit,p_rules,'draft','pending') returning id into v_id;
 insert into public.campaign_deposits(campaign_id,campaigner_id,amount,selected_bank,payer_account_name,payer_account_number,payment_reference,proof_path)
 values(v_id,auth.uid(),p_budget,p_selected_bank,p_payer_name,p_payer_account,p_payment_reference,p_proof_path);
 return v_id;
end $$;

create or replace function public.get_campaign_creators() returns table(application_id uuid,campaign_id uuid,campaign_title text,clipper_id uuid,creator_name text,verification_status text,application_status text,joined_at timestamptz)
language sql security definer set search_path=public as $$
 select a.id,a.campaign_id,c.title,a.clipper_id,p.full_name,p.verification_status,a.status,a.created_at
 from public.campaign_applications a join public.campaigns c on c.id=a.campaign_id join public.profiles p on p.id=a.clipper_id
 where c.campaigner_id=auth.uid() and public.current_role()='campaigner'
 order by a.created_at desc
$$;

create or replace function public.campaigner_manage_creator(p_application_id uuid,p_status text) returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or public.current_role()<>'campaigner' then raise exception 'Akun campaigner diperlukan'; end if;
 if p_status not in ('joined','blocked') then raise exception 'Status tidak valid'; end if;
 update public.campaign_applications a set status=p_status from public.campaigns c where a.id=p_application_id and c.id=a.campaign_id and c.campaigner_id=auth.uid();
 if not found then raise exception 'Creator atau campaign tidak ditemukan'; end if;
end $$;

create or replace function public.admin_create_internal_campaign(p_title text,p_brief text,p_platform text,p_distribution_mode text,p_budget numeric,p_reward_rate numeric,p_duration integer,p_creator_limit integer default null) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if p_budget<=0 or p_reward_rate<=0 or p_duration<1 or p_duration>180 then raise exception 'Parameter campaign tidak valid'; end if;
 insert into public.campaigns(campaigner_id,title,brand_name,description,brief,platform,distribution_mode,budget_total,budget_remaining,reward_rate,duration_days,creator_limit,status,payment_status,is_internal,start_at,end_at)
 values(auth.uid(),p_title,'KasiClip Internal','Campaign internal KasiClip',p_brief,p_platform,p_distribution_mode,p_budget,p_budget,p_reward_rate,p_duration,p_creator_limit,'active','confirmed',true,now(),now()+make_interval(days=>p_duration)) returning id into v_id;
 return v_id;
end $$;

create or replace function public.join_campaign(p_campaign_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare v_campaign public.campaigns;
begin
 if auth.uid() is null or public.current_role()<>'clipper' then raise exception 'Akun creator diperlukan'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and verification_status='verified') then raise exception 'Verifikasi creator harus selesai'; end if;
 select * into v_campaign from public.campaigns where id=p_campaign_id and status='active' and (end_at is null or end_at>now());
 if not found then raise exception 'Campaign tidak tersedia'; end if;
 if exists(select 1 from public.campaign_applications where campaign_id=p_campaign_id and clipper_id=auth.uid() and status='blocked') then raise exception 'Kamu diblokir dari campaign ini'; end if;
 if v_campaign.creator_limit is not null and (select count(*) from public.campaign_applications where campaign_id=p_campaign_id and status='joined')>=v_campaign.creator_limit then raise exception 'Kuota creator campaign penuh'; end if;
 insert into public.campaign_applications(campaign_id,clipper_id,status) values(p_campaign_id,auth.uid(),'joined') on conflict(campaign_id,clipper_id) do update set status='joined' where public.campaign_applications.status='left';
end $$;

create or replace function public.submit_content(p_campaign_id uuid,p_content_url text,p_claimed_views bigint,p_proof_path text) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if auth.uid() is null or public.current_role()<>'clipper' then raise exception 'Akun creator diperlukan'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and verification_status='verified') then raise exception 'Verifikasi creator harus selesai'; end if;
 if not exists(select 1 from public.campaign_applications where campaign_id=p_campaign_id and clipper_id=auth.uid() and status='joined') then raise exception 'Kamu belum bergabung dengan campaign ini'; end if;
 if not exists(select 1 from public.campaigns where id=p_campaign_id and status='active' and (end_at is null or end_at>now())) then raise exception 'Campaign sudah tidak aktif'; end if;
 if p_proof_path is null or (storage.foldername(p_proof_path))[1]<>auth.uid()::text then raise exception 'Lokasi bukti tidak valid'; end if;
 insert into public.submissions(clipper_id,campaign_id,content_url,claimed_views,proof_path,status)
 values(auth.uid(),p_campaign_id,p_content_url,p_claimed_views,p_proof_path,'pending_review') returning id into v_id;
 return v_id;
end $$;

create or replace function public.claim_creator_rewards(p_amount numeric) returns void language plpgsql security definer set search_path=public as $$
declare v_cloud numeric(18,6); v_wallet numeric(18,6);
begin
 if auth.uid() is null or public.current_role()<>'clipper' then raise exception 'Akun creator diperlukan'; end if;
 if p_amount<1000 then raise exception 'Minimum claim reward Rp1.000'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select coalesce(sum(case when entry_type='creator_reward' and direction='credit' then amount when entry_type='reward_claim' and direction='debit' then -amount else 0 end),0) into v_cloud from public.ledger where user_id=auth.uid();
 if p_amount>v_cloud then raise exception 'Cloud Reward tidak mencukupi'; end if;
 insert into public.ledger(user_id,entry_type,amount,direction,description,idempotency_key) values(auth.uid(),'reward_claim',p_amount,'debit','Claim Cloud Reward','claim-'||gen_random_uuid());
 insert into public.ledger(user_id,entry_type,amount,direction,description,idempotency_key) values(auth.uid(),'wallet_credit',p_amount,'credit','Reward dipindahkan ke wallet','wallet-credit-'||gen_random_uuid());
end $$;

create or replace function public.request_withdrawal(p_amount numeric,p_method text,p_account_name text,p_account_number text) returns uuid language plpgsql security definer set search_path=public as $$
declare v_fee numeric; v_id uuid; v_balance numeric;
begin
 if auth.uid() is null or public.current_role()<>'clipper' then raise exception 'Akun creator diperlukan'; end if;
 if p_amount<50000 then raise exception 'Minimum withdrawal Rp50.000'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select coalesce(sum(case when direction='credit' then amount else -amount end),0) into v_balance from public.ledger where user_id=auth.uid() and entry_type in ('wallet_credit','withdrawal_reservation','withdrawal_refund');
 if p_amount>v_balance then raise exception 'Saldo tersedia tidak mencukupi'; end if;
 v_fee:=case when p_amount<=250000 then 2500 when p_amount<=500000 then 3000 when p_amount<=1000000 then 5000 when p_amount<=2500000 then 7500 else 10000 end;
 insert into public.withdrawals(clipper_id,amount,fee,net_amount,payout_method,payout_account_name,payout_account_number)
 values(auth.uid(),p_amount,v_fee,p_amount-v_fee,p_method,p_account_name,p_account_number) returning id into v_id;
 insert into public.ledger(user_id,withdrawal_id,entry_type,amount,direction,description,idempotency_key)
 values(auth.uid(),v_id,'withdrawal_reservation',p_amount,'debit','Saldo ditahan untuk withdrawal '||v_id,'wd-reserve-'||v_id);
 insert into public.ledger(user_id,withdrawal_id,entry_type,amount,direction,description,idempotency_key)
 values(auth.uid(),v_id,'platform_revenue',v_fee,'credit','Biaya withdrawal','wd-fee-'||v_id);
 return v_id;
end $$;

create or replace function public.admin_review_deposit(p_deposit_id uuid,p_approve boolean,p_note text default null) returns void language plpgsql security definer set search_path=public as $$
declare v public.campaign_deposits;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 select * into v from public.campaign_deposits where id=p_deposit_id for update;
 if not found or v.status<>'pending' then raise exception 'Deposit tidak ditemukan atau sudah diproses'; end if;
 update public.campaign_deposits set status=case when p_approve then 'confirmed' else 'rejected' end,admin_note=p_note,reviewed_by=auth.uid(),reviewed_at=now() where id=p_deposit_id;
 update public.campaigns set payment_status=case when p_approve then 'confirmed' else 'rejected' end,status=case when p_approve then 'pending_review' else 'rejected' end,updated_at=now() where id=v.campaign_id;
 insert into public.notifications(user_id,title,body,kind) select campaigner_id,case when p_approve then 'Deposit dikonfirmasi' else 'Deposit ditolak' end,case when p_approve then 'Deposit campaign sudah dikonfirmasi dan menunggu approval campaign.' else coalesce(p_note,'Bukti pembayaran perlu diperiksa kembali.') end,'billing' from public.campaigns where id=v.campaign_id;
end $$;

create or replace function public.admin_review_campaign(p_campaign_id uuid,p_approve boolean,p_note text default null) returns void language plpgsql security definer set search_path=public as $$
declare v public.campaigns;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 select * into v from public.campaigns where id=p_campaign_id for update;
 if not found or v.payment_status<>'confirmed' or v.status not in ('pending_review','rejected') then raise exception 'Campaign harus lolos konfirmasi pembayaran'; end if;
 update public.campaigns set status=case when p_approve then 'active' else 'rejected' end,start_at=case when p_approve then now() else start_at end,end_at=case when p_approve then now()+make_interval(days=>duration_days) else end_at end,updated_at=now() where id=p_campaign_id;
 insert into public.notifications(user_id,title,body,kind) values(v.campaigner_id,case when p_approve then 'Campaign disetujui' else 'Campaign ditolak' end,case when p_approve then 'Campaign '||v.title||' sudah aktif.' else 'Campaign '||v.title||' ditolak: '||coalesce(p_note,'Periksa detail campaign.') end,'campaign');
end $$;

create or replace function public.admin_review_creator_verification(p_request_id uuid,p_approve boolean,p_note text default null) returns void language plpgsql security definer set search_path=public as $$
declare v public.verification_requests;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 select * into v from public.verification_requests where id=p_request_id for update;
 if not found or v.status<>'pending_review' or (v.expires_at is not null and v.expires_at<=now()) then raise exception 'Permintaan tidak ditemukan, sudah diproses, atau kode sudah kedaluwarsa'; end if;
 update public.verification_requests set status=case when p_approve then 'approved' else 'rejected' end,verification_code=null,reviewer_id=auth.uid(),admin_note=p_note,reviewed_at=now() where id=p_request_id;
 update public.profiles set verification_status=case when p_approve then 'verified' else 'rejected' end,updated_at=now() where id=v.user_id;
 insert into public.notifications(user_id,title,body,kind) values(v.user_id,case when p_approve then 'Creator terverifikasi' else 'Verifikasi creator ditolak' end,case when p_approve then 'Akun creator kamu sudah terverifikasi.' else coalesce(p_note,'Silakan periksa kembali profil dan kode bio kamu.') end,'verification');
end $$;

create or replace function public.admin_review_brand_verification(p_request_id uuid,p_approve boolean,p_note text default null) returns void language plpgsql security definer set search_path=public as $$
declare v public.brand_verifications;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 select * into v from public.brand_verifications where id=p_request_id for update;
 if not found or v.status<>'pending' then raise exception 'Permintaan tidak ditemukan atau sudah diproses'; end if;
 update public.brand_verifications set status=case when p_approve then 'verified' else 'rejected' end,reviewer_id=auth.uid(),admin_note=p_note,reviewed_at=now(),updated_at=now() where id=p_request_id;
 update public.profiles set verification_status=case when p_approve then 'verified' else 'rejected' end,updated_at=now() where id=v.campaigner_id;
 insert into public.notifications(user_id,title,body,kind) values(v.campaigner_id,case when p_approve then 'Brand terverifikasi' else 'Verifikasi brand ditolak' end,case when p_approve then 'Brand kamu sudah terverifikasi dan dapat membuat campaign.' else coalesce(p_note,'Periksa kembali dokumen dan data bisnis.') end,'verification');
end $$;

create or replace function public.admin_review_submission(p_submission_id uuid,p_approve boolean,p_approved_views bigint default null,p_note text default null) returns void language plpgsql security definer set search_path=public as $$
declare v public.submissions; c public.campaigns; v_reward numeric(18,6); v_views bigint;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 select * into v from public.submissions where id=p_submission_id for update;
 if not found or v.status<>'pending_review' then raise exception 'Submission tidak ditemukan atau sudah diproses'; end if;
 if not p_approve then
  update public.submissions set status='rejected',reviewer_id=auth.uid(),admin_note=p_note,reviewed_at=now() where id=p_submission_id;
  insert into public.notifications(user_id,title,body,kind) values(v.clipper_id,'Submission ditolak',coalesce(p_note,'Bukti views belum memenuhi ketentuan.'),'submission');
  return;
 end if;
 select * into c from public.campaigns where id=v.campaign_id for update;
 if c.status not in ('active','completed') or (c.end_at is not null and v.created_at>c.end_at) then raise exception 'Submission dibuat di luar periode campaign aktif'; end if;
 if c.budget_remaining<=0 then raise exception 'Budget campaign sudah habis'; end if;
 v_views:=coalesce(p_approved_views,v.claimed_views);
 if v_views<0 or v_views>v.claimed_views then raise exception 'Approved views tidak valid'; end if;
 v_reward:=round((v_views::numeric*c.reward_rate/1000),6);
 if v_reward>c.budget_remaining then raise exception 'Reward melebihi sisa budget campaign'; end if;
 update public.submissions set status='approved',approved_views=v_views,reward_amount=v_reward,reviewer_id=auth.uid(),admin_note=p_note,reviewed_at=now() where id=p_submission_id;
 update public.campaigns set budget_remaining=greatest(0,budget_remaining-v_reward),status=case when budget_remaining-v_reward<=0 then 'completed'::public.campaign_status else status end,completion_reason=case when budget_remaining-v_reward<=0 then 'budget' else completion_reason end,updated_at=now() where id=c.id;
 insert into public.ledger(user_id,campaign_id,submission_id,entry_type,amount,direction,description,idempotency_key)
 values(v.clipper_id,c.id,v.id,'creator_reward',v_reward,'credit','Reward views valid untuk campaign '||c.title,'reward-'||v.id);
 insert into public.notifications(user_id,title,body,kind) values(v.clipper_id,'Reward disetujui','Reward '||v_reward||' berhasil ditambahkan ke akumulasi reward kamu.','reward');
end $$;

create or replace function public.admin_update_withdrawal(p_withdrawal_id uuid,p_status text,p_note text default null) returns void language plpgsql security definer set search_path=public as $$
declare v public.withdrawals;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if p_status not in ('processing','approved','paid','rejected') then raise exception 'Status tidak valid'; end if;
 select * into v from public.withdrawals where id=p_withdrawal_id for update;
 if not found or v.status in ('paid','rejected') then raise exception 'Withdrawal tidak dapat diubah'; end if;
 update public.withdrawals set status=p_status,admin_note=p_note,processed_by=auth.uid(),paid_at=case when p_status='paid' then now() else paid_at end where id=p_withdrawal_id;
 if p_status='rejected' then
  insert into public.ledger(user_id,withdrawal_id,entry_type,amount,direction,description,idempotency_key)
  values(v.clipper_id,v.id,'withdrawal_refund',v.amount,'credit','Pengembalian saldo withdrawal yang ditolak','wd-refund-'||v.id) on conflict(idempotency_key) do nothing;
  insert into public.ledger(user_id,withdrawal_id,entry_type,amount,direction,description,idempotency_key) values(v.clipper_id,v.id,'platform_revenue',v.fee,'debit','Pembatalan biaya withdrawal','wd-fee-reversal-'||v.id) on conflict(idempotency_key) do nothing;
 end if;
 insert into public.notifications(user_id,title,body,kind) values(v.clipper_id,'Status withdrawal diperbarui','Withdrawal kamu: '||p_status||'. '||coalesce(p_note,''),'wallet');
end $$;

create or replace function public.admin_update_payment_instructions(p_value jsonb) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if coalesce(p_value->>'bank_name','')='' or coalesce(p_value->>'account_name','')='' or coalesce(p_value->>'account_number','')='' then raise exception 'Data rekening pembayaran wajib lengkap'; end if;
 insert into public.platform_settings(key,value,updated_by,updated_at) values('payment_instructions',p_value,auth.uid(),now())
 on conflict(key) do update set value=excluded.value,updated_by=auth.uid(),updated_at=now();
end $$;

create or replace function public.admin_set_user_status(p_user_id uuid,p_status text) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if p_status not in ('active','suspended') then raise exception 'Status akun tidak valid'; end if;
 if p_user_id=auth.uid() then raise exception 'Admin tidak dapat menonaktifkan akun sendiri'; end if;
 update public.profiles set account_status=p_status,updated_at=now() where id=p_user_id;
 if not found then raise exception 'User tidak ditemukan'; end if;
 insert into public.notifications(user_id,title,body,kind) values(p_user_id,case when p_status='active' then 'Akun diaktifkan' else 'Akun ditangguhkan' end,case when p_status='active' then 'Akses akun KasiClip kamu telah diaktifkan.' else 'Akses akun KasiClip kamu ditangguhkan. Hubungi admin untuk informasi.' end,'account');
end $$;

-- Expire campaigns and create H-3 / low-budget notifications. Run periodically with Supabase Cron if enabled.
create or replace function public.refresh_campaign_states() returns void language plpgsql security definer set search_path=public as $$
begin
 with expired_requests as (update public.verification_requests set status='rejected',verification_code=null,admin_note='Verification challenge expired' where status='pending_review' and expires_at is not null and expires_at<=now() returning user_id),
 updated_profiles as (update public.profiles p set verification_status='rejected',updated_at=now() where p.id in (select user_id from expired_requests) returning p.id)
 insert into public.notifications(user_id,title,body,kind) select id,'Kode verifikasi kedaluwarsa','Masa berlaku kode verifikasi creator sudah habis. Ajukan permintaan baru untuk mendapatkan kode baru.','verification' from updated_profiles;
 update public.campaigns set status='completed',completion_reason=case when budget_remaining<=0 then 'budget' else 'time' end,updated_at=now() where status='active' and ((end_at is not null and end_at<=now()) or budget_remaining<=0);
 insert into public.notifications(user_id,title,body,kind)
 select c.campaigner_id,'Campaign segera berakhir','Campaign '||c.title||' akan berakhir dalam 3 hari. Periksa performa dan budget.','campaign'
 from public.campaigns c where c.status='active' and c.end_at between now() and now()+interval '3 days'
 and not exists(select 1 from public.notifications n where n.user_id=c.campaigner_id and n.title='Campaign segera berakhir' and n.body like '%'||c.title||'%' and n.created_at>now()-interval '4 days');
 insert into public.notifications(user_id,title,body,kind)
 select c.campaigner_id,'Budget campaign hampir habis','Sisa budget campaign '||c.title||' kurang dari 10%.','campaign'
 from public.campaigns c where c.status='active' and c.budget_total>0 and c.budget_remaining/c.budget_total<=0.1
 and not exists(select 1 from public.notifications n where n.user_id=c.campaigner_id and n.title='Budget campaign hampir habis' and n.body like '%'||c.title||'%' and n.created_at>now()-interval '1 day');
end $$;

-- RLS
drop policy if exists "profiles read self or admin" on public.profiles;
drop policy if exists "new users create limited profile" on public.profiles;
drop policy if exists "admin updates profiles" on public.profiles;
drop policy if exists "campaigns visible active or owner or admin" on public.campaigns;
drop policy if exists "campaigner create own campaign" on public.campaigns;
drop policy if exists "admin update campaigns" on public.campaigns;
drop policy if exists "verification own read" on public.verification_requests;
drop policy if exists "verification own create" on public.verification_requests;
drop policy if exists "verification admin update" on public.verification_requests;
drop policy if exists "submission owner or admin read" on public.submissions;
drop policy if exists "clipper creates own submission" on public.submissions;
drop policy if exists "admin reviews submissions" on public.submissions;
drop policy if exists "ledger owner or admin read" on public.ledger;
drop policy if exists "withdrawal owner or admin read" on public.withdrawals;
drop policy if exists "clipper requests own withdrawal" on public.withdrawals;
drop policy if exists "admin processes withdrawal" on public.withdrawals;
drop policy if exists "applications own read" on public.campaign_applications;
drop policy if exists "clipper joins campaign" on public.campaign_applications;
alter table public.profiles enable row level security;
alter table public.brand_verifications enable row level security;
alter table public.campaigns enable row level security;
alter table public.campaign_deposits enable row level security;
alter table public.verification_requests enable row level security;
alter table public.campaign_applications enable row level security;
alter table public.submissions enable row level security;
alter table public.ledger enable row level security;
alter table public.withdrawals enable row level security;
alter table public.notifications enable row level security;
alter table public.platform_settings enable row level security;

drop policy if exists profiles_read_self_admin on public.profiles;
create policy profiles_read_self_admin on public.profiles for select using(id=auth.uid() or public.is_admin());
drop policy if exists profiles_update_self_limited on public.profiles;
drop policy if exists brand_verification_read on public.brand_verifications;
create policy brand_verification_read on public.brand_verifications for select using(campaigner_id=auth.uid() or public.is_admin());
drop policy if exists campaign_read on public.campaigns;
create policy campaign_read on public.campaigns for select using(status='active' or campaigner_id=auth.uid() or public.is_admin());
drop policy if exists deposit_read on public.campaign_deposits;
create policy deposit_read on public.campaign_deposits for select using(campaigner_id=auth.uid() or public.is_admin());
drop policy if exists verification_read on public.verification_requests;
create policy verification_read on public.verification_requests for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists applications_read on public.campaign_applications;
create policy applications_read on public.campaign_applications for select using(clipper_id=auth.uid() or public.is_admin() or exists(select 1 from public.campaigns c where c.id=campaign_id and c.campaigner_id=auth.uid()));
drop policy if exists submissions_read on public.submissions;
create policy submissions_read on public.submissions for select using(clipper_id=auth.uid() or public.is_admin() or exists(select 1 from public.campaigns c where c.id=campaign_id and c.campaigner_id=auth.uid()));
drop policy if exists ledger_read on public.ledger;
create policy ledger_read on public.ledger for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists withdrawals_read on public.withdrawals;
create policy withdrawals_read on public.withdrawals for select using(clipper_id=auth.uid() or public.is_admin());
drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists settings_read on public.platform_settings;
create policy settings_read on public.platform_settings for select using(key='payment_instructions' or public.is_admin());

-- Storage: private evidence bucket. Upload paths must start with the authenticated user's UUID.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('kasiclip-private','kasiclip-private',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false;
drop policy if exists kasiclip_private_upload on storage.objects;
create policy kasiclip_private_upload on storage.objects for insert to authenticated with check(bucket_id='kasiclip-private' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.account_status='active'));
drop policy if exists kasiclip_private_read on storage.objects;
create policy kasiclip_private_read on storage.objects for select to authenticated using(bucket_id='kasiclip-private' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Explicit table grants; RLS determines which rows each authenticated user can read.
grant usage on schema public to authenticated;
grant select on public.profiles,public.brand_verifications,public.campaigns,public.campaign_deposits,public.verification_requests,public.campaign_applications,public.submissions,public.ledger,public.withdrawals,public.notifications,public.platform_settings to authenticated;
grant update on public.notifications to authenticated;
revoke insert,update,delete on public.profiles,public.brand_verifications,public.campaigns,public.campaign_deposits,public.verification_requests,public.campaign_applications,public.submissions,public.ledger,public.withdrawals,public.platform_settings from anon,authenticated;
revoke insert,delete on public.notifications from anon,authenticated;

-- Least privilege: users cannot write ledgers or approve their own requests directly.
grant execute on function public.request_creator_verification(text,text) to authenticated;
grant execute on function public.request_brand_verification(text,text,text,text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.create_campaign_with_deposit(text,text,text,text,text,text,text,numeric,numeric,integer,integer,text,text,text,text,text,text) to authenticated;
grant execute on function public.join_campaign(uuid) to authenticated;
grant execute on function public.get_campaign_creators() to authenticated;
grant execute on function public.campaigner_manage_creator(uuid,text) to authenticated;
grant execute on function public.admin_create_internal_campaign(text,text,text,text,numeric,numeric,integer,integer) to authenticated;
grant execute on function public.submit_content(uuid,text,bigint,text) to authenticated;
grant execute on function public.claim_creator_rewards(numeric) to authenticated;
grant execute on function public.request_withdrawal(numeric,text,text,text) to authenticated;
grant execute on function public.admin_review_deposit(uuid,boolean,text) to authenticated;
grant execute on function public.admin_review_campaign(uuid,boolean,text) to authenticated;
grant execute on function public.admin_review_creator_verification(uuid,boolean,text) to authenticated;
grant execute on function public.admin_review_brand_verification(uuid,boolean,text) to authenticated;
grant execute on function public.admin_review_submission(uuid,boolean,bigint,text) to authenticated;
grant execute on function public.admin_update_withdrawal(uuid,text,text) to authenticated;
grant execute on function public.admin_set_user_status(uuid,text) to authenticated;
grant execute on function public.admin_update_payment_instructions(jsonb) to authenticated;
revoke all on function public.refresh_campaign_states() from public,authenticated;

-- Assign admin only from trusted SQL Editor after the account exists:
-- update public.profiles set role='admin' where id='AUTH_USER_UUID';
