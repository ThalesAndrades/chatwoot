# Self-hosted Chatwoot — Cost & Performance Tuning

A practical, code-backed setup to run a **self-hosted Chatwoot** at **maximum performance
for the lowest cost**. Every knob below maps to a real environment variable or config file
in this repository — start from [`env.optimized.example`](./env.optimized.example).

> **Scope:** self-hosted (your own infra + your own OpenAI key). On self-hosted you pay
> OpenAI **per token directly** — there are no Chatwoot Cloud credits or markup, so the
> cheapest-capable model is almost always the right call.

---

## TL;DR — the high-impact moves

| Area | Do this | Why it saves / speeds up |
|------|---------|--------------------------|
| Ruby runtime | `RUBY_YJIT_ENABLE=1` | ~15–30% faster on Ruby 3.4, **free** |
| Ruby memory | `MALLOC_ARENA_MAX=2` | Lower RAM = smaller/cheaper box |
| Web concurrency | `WEB_CONCURRENCY = vCPUs`, `RAILS_MAX_THREADS=5` | Uses every core without over-allocating RAM |
| AI model | Captain → `gpt-4.1-mini` (or `gpt-4.1-nano`) | Cheapest capable OpenAI models |
| AI embeddings | `text-embedding-3-small` | Cheapest viable embedding |
| AI crawler | Leave `CAPTAIN_FIRECRAWL_API_KEY` empty | Uses the free built-in crawler |
| Storage | `ACTIVE_STORAGE_SERVICE=local` (small installs) | Zero object-storage bill |
| Abuse | `ENABLE_RACK_ATTACK=true` | No wasted compute or AI spend on bots |
| DB hygiene | `REMOVE_STALE_CONTACT_INBOX_JOB_STATUS=true` | Leaner tables = faster queries |

---

## 1. Sizing & web concurrency (Puma)

Puma's total concurrency is **`WEB_CONCURRENCY` (workers) × `RAILS_MAX_THREADS` (threads)**
(`config/puma.rb`). Because MRI Ruby has a GIL, **5 threads per worker is the sweet spot**;
add throughput with *workers*, not more threads.

```bash
WEB_CONCURRENCY   = number of vCPUs      # 2 vCPU -> 2 workers
RAILS_MAX_THREADS = 5                     # also sets the web DB connection pool
```

`preload_app!` is already enabled, so workers share memory via copy-on-write — adding a
worker costs far less RAM than a full process. Start at `WEB_CONCURRENCY=2` on a 2 vCPU /
4 GB box and scale linearly with cores.

## 2. Background jobs (Sidekiq)

```bash
SIDEKIQ_CONCURRENCY = 10    # default; this ALSO sets the worker's DB pool
```

`config/sidekiq.yml` ships a sensible priority queue order (`critical → high → … → low →
housekeeping`). On a memory-constrained 2 GB box, drop `SIDEKIQ_CONCURRENCY` to `5` to
shrink the footprint; raise it (and your DB `max_connections`) only if jobs back up.

## 3. PostgreSQL

- **`pgvector` is required** — Captain stores knowledge embeddings in `vector(1536)` columns
  with `ivfflat` indexes. Install the extension before enabling Captain.
- **Connection budget:** size `max_connections` for
  `(WEB_CONCURRENCY × RAILS_MAX_THREADS) + SIDEKIQ_CONCURRENCY + headroom`. The baseline
  (2×5 + 10) needs ~25; Postgres' default of 100 is plenty. **Past ~4 web workers, put
  PgBouncer (transaction pooling) in front** instead of raising `max_connections` — it's the
  cheapest way to scale connections.
- `POSTGRES_STATEMENT_TIMEOUT=14s` (default) caps runaway queries so one bad request can't
  pin a CPU.

## 4. Redis

`REDIS_URL` + `REDIS_PASSWORD` are enough. Two app-specific pools exist
(`config/initializers/01_redis.rb`): `REDIS_ALFRED_SIZE` (online presence, default 5) and
`REDIS_VELMA_SIZE` (reporting, default 10). Leave them at defaults; raise only under
sustained load. One small Redis instance comfortably serves cache + Sidekiq + presence.

## 5. Storage & assets

- **Small installs:** `ACTIVE_STORAGE_SERVICE=local` keeps attachments on disk — **no object
  storage bill**.
- **At scale:** switch to `s3` (works with S3, Cloudflare R2, etc.) for durability and to
  offload bandwidth, and set `ASSET_CDN_HOST` to a CDN (Cloudflare's free tier works) so
  static assets are served from the edge — faster *and* cheaper egress.

## 6. Logging & abuse protection

- `LOG_LEVEL=info` (or `warn` to cut volume further) + `RAILS_LOG_TO_STDOUT=true`.
- `ENABLE_RACK_ATTACK=true` with `RACK_ATTACK_LIMIT=300` throttles abusive traffic — directly
  prevents wasted compute and, importantly, **wasted AI token spend** from bot floods.

## 7. Ruby runtime (free wins)

```bash
RUBY_YJIT_ENABLE=1     # YJIT JIT compiler on Ruby 3.4 — pure speed, no cost
MALLOC_ARENA_MAX=2     # reduces glibc memory fragmentation — lower RAM = smaller box
```

---

## 8. AI / Captain — lowest cost, kept capable

Captain is an **Enterprise-edition** feature. On self-hosted you supply your **own OpenAI
key** and pay OpenAI **per token** — so cost = real model pricing, and the cheapest capable
model wins.

> **Where to set these:** Captain keys are **not** read from `.env`. Configure them in
> **Super Admin → Settings → Configuration** (these are `InstallationConfig` records, see
> `config/installation_config.yml`).

Cost-optimal values:

| Setting | Recommended | Notes |
|---------|-------------|-------|
| `CAPTAIN_OPEN_AI_MODEL` | `gpt-4.1-mini` | Cheapest capable default. Use `gpt-4.1-nano` for max savings on simple flows. |
| `CAPTAIN_EMBEDDING_MODEL` | `text-embedding-3-small` | Cheapest viable embedding (1536-dim). |
| `CAPTAIN_OPEN_AI_ENDPOINT` | *(default)* | Override only for Azure OpenAI / OpenRouter / a local OpenAI-compatible LLM. |
| `CAPTAIN_FIRECRAWL_API_KEY` | *(empty)* | Empty = free built-in crawler; set only if you need Firecrawl's quality. |

### Per-feature model picks (in-app, per account)

The in-app AI model catalog (`config/llm.yml`) carries a `credit_multiplier` per model.
Lower multiplier = lower relative cost. The defaults leave money on the table for two
features — switch them to the `multiplier: 1` option:

| Feature | Default | Cost-optimal | Multiplier change |
|---------|---------|--------------|-------------------|
| Assistant (customer-facing) | `gpt-5.1` | **`gpt-5-mini`** | 2 → **1** |
| Copilot (agent-facing) | `gpt-5.1` | **`gpt-5-mini`** | 2 → **1** |
| Reply editor | `gpt-4.1-mini` | already optimal | 1 |
| Label suggestion | `gpt-4.1-nano` | already optimal | 1 |

> Anthropic (Claude) and Gemini models appear in the catalog but are flagged
> `coming_soon` — OpenAI is the only live provider today.

### Keep token spend down
- Curate the Captain knowledge base (fewer, higher-quality documents → fewer tokens per
  retrieval; retrieval already returns only the top-5 nearest FAQs).
- Keep `ENABLE_ACCOUNT_SIGNUP=false` and Rack::Attack on so bots can't trigger paid AI calls.

---

## Apply it

1. `cp docs/self-hosting/env.optimized.example .env`
2. Fill the secrets (`SECRET_KEY_BASE`, encryption keys, DB/Redis passwords, SMTP).
3. Size `WEB_CONCURRENCY` / `SIDEKIQ_CONCURRENCY` to your box.
4. Install the Postgres `pgvector` extension (only if using Captain).
5. Set the Captain values in **Super Admin → Settings → Configuration**.
6. Restart web + worker.
