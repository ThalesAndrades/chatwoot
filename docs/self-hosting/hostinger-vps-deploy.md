# Deploy a Chatwoot demo on a Hostinger VPS (Docker)

A turnkey walkthrough to run a **full Chatwoot demo** — login page, admin access, and sample
data showcasing every feature — on a **Hostinger VPS** using the bundled
`docker-compose.production.yaml`.

> **Why a VPS and not Hostinger's "Node.js" hosting?** Chatwoot is a **Ruby on Rails**
> application that needs **PostgreSQL (with pgvector), Redis, and Sidekiq** — it cannot run on
> Node.js / shared hosting. A **Hostinger VPS** (KVM) running Docker is the supported target.
> Hostinger even ships a one-click **Chatwoot VPS template**; this guide does it manually so
> you control the demo seed and admin login.

---

## 0. Prerequisites
- A **Hostinger VPS** (KVM 2 or larger recommended: 2 vCPU / 4 GB+), Ubuntu 22.04/24.04.
- A public hostname for the VPS. The simplest option is the **Hostinger provisional domain**
  (`srvXXXXXX.hstgr.cloud`, shown in hPanel → VPS → Overview) — it resolves publicly, so HTTPS
  works out of the box. A custom subdomain (e.g. `chat.yourdomain.com` with an A record to the
  VPS IP) also works. Avoid using the bare IP — Let's Encrypt can't issue a certificate for it.
- SSH access to the VPS.

## 1. Install Docker
```bash
ssh root@YOUR_VPS_IP
curl -fsSL https://get.docker.com | sh
docker compose version   # verify Compose v2 is available
```

## 2. Get the deploy files
```bash
git clone https://github.com/ThalesAndrades/chatwoot.git
cd chatwoot
cp docs/self-hosting/env.demo.example .env
```

## 3. Configure `.env`
Edit `.env` and set the secrets:
```bash
# generate a secret key
docker run --rm chatwoot/chatwoot:latest bundle exec rake secret   # -> SECRET_KEY_BASE
```
Fill in: `SECRET_KEY_BASE`, the three `ACTIVE_RECORD_ENCRYPTION_*` keys (generate with
`db:encryption:init`, step 5), `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, your `FRONTEND_URL`, and
your **demo admin** values (`DEMO_ADMIN_EMAIL`, `DEMO_ADMIN_PASSWORD`).

> ⚠️ **Password policy:** Chatwoot requires **≥6 chars with at least 1 uppercase, 1 number, and
> 1 special character**. `Admin@123` is valid; `admin` is not.

> ⚠️ **Postgres password in two places:** the compose `postgres` service sets its own
> `POSTGRES_PASSWORD`. Edit `docker-compose.production.yaml` so the `postgres` service password
> **matches** `POSTGRES_PASSWORD` in `.env`, and confirm `POSTGRES_DB=chatwoot` matches
> `POSTGRES_DATABASE`.

## 4. Start the database & cache
```bash
docker compose -f docker-compose.production.yaml up -d postgres redis
```

## 5. Generate encryption keys, then prepare the database
```bash
# prints the 3 ACTIVE_RECORD_ENCRYPTION_* values — paste them into .env
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails db:encryption:init

# create schema + run migrations
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails db:chatwoot_prepare
```

## 6. Seed the demo (admin login + sample data)
```bash
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails demo:setup
```
This creates a **SuperAdmin** user from your `.env` values and a **Demo Company** account with
rich sample data — teams, custom roles, agents, labels, 50 canned responses, and contacts with
conversations across **every channel** (Website, Facebook, WhatsApp, Email, SMS, API, Telegram,
Line). The task prints the final login at the end.

## 7. Bring the app up
```bash
docker compose -f docker-compose.production.yaml up -d
```
The Rails service listens on `127.0.0.1:3000` (loopback only) — finish with a reverse proxy.

## 8. Domain + HTTPS (Caddy — easiest)
The compose binds Rails to localhost, so put a TLS-terminating proxy in front. Caddy gets you a
free auto-renewing certificate in one file:
```bash
# /root/Caddyfile  — use the same host as FRONTEND_URL (e.g. your Hostinger provisional domain)
srvXXXXXX.hstgr.cloud {
    reverse_proxy 127.0.0.1:3000
}
```
```bash
docker run -d --name caddy --network host \
  -v /root/Caddyfile:/etc/caddy/Caddyfile \
  -v caddy_data:/data caddy:latest
```
Keep `FORCE_SSL=true` in `.env` (TLS is terminated by Caddy).

## 9. Log in
Open your `FRONTEND_URL` (e.g. **`https://srvXXXXXX.hstgr.cloud`**) and sign in with your `DEMO_ADMIN_EMAIL` /
`DEMO_ADMIN_PASSWORD`. The same user can open the instance-wide **Super Admin** panel at
`/super_admin`.

---

## What the demo shows out of the box
All **OSS (free) features** are enabled by default and populated with sample data:
omnichannel inboxes, conversations, contacts & segments, labels, canned responses, teams &
agents, custom roles, automations, macros, help center, campaigns, and reports.

**Premium features** (Captain AI, SLA, SAML, custom branding, audit logs) are **not** part of
this OSS demo — they require the Enterprise build plus configuration (and Captain needs your own
OpenAI key). See [`cost-and-performance.md`](./cost-and-performance.md) for the AI/Captain setup.

## Operating the instance
```bash
docker compose -f docker-compose.production.yaml logs -f rails       # tail logs
docker compose -f docker-compose.production.yaml pull && \
  docker compose -f docker-compose.production.yaml up -d              # upgrade to latest image
docker compose -f docker-compose.production.yaml run --rm rails \
  bundle exec rails db:chatwoot_prepare                               # run migrations after upgrade
```

> **Re-seeding:** running `demo:setup` again **resets** the Demo Company account's sample data
> (teams/inboxes/labels/contacts/conversations) — handy to get a clean demo, destructive to any
> real data in that account.
