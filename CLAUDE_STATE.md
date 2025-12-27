# CLAUDE_STATE.md

## Session State — DO NOT DELETE OR RENAME

This file is the single source of truth for session continuity when using Claude Code,
especially after usage or rate-limit resets.

---

## Goal

Build and harden a production-ready MT5 trading signal service platform with:

- MASTER → SLAVE signal distribution
- Tier-based delays and limits
- Secure authentication and OTP
- Stripe-based subscriptions
- Reliable EA ↔ backend communication

---

## Current Phase

Core backend and MT5 signal pipeline stabilization and hardening.

---

## What Is DONE

- **EA API Key Authentication (Dec 27, 2025):**
  - Added `POST /api/user/mt5-accounts/:id/api-key` to generate API keys
  - Added `DELETE /api/user/mt5-accounts/:id/api-key` to revoke API keys
  - API keys never expire (unlike JWT tokens which expire in 1 hour)
  - Auth middleware already supports `X-API-Key` header authentication
  - Updated docs/EA-CONFIGURATION.md with new API key workflow
- System architecture finalized (MT5 MASTER → Backend → MT5 SLAVE)
- Prisma schema completed:
  - User, Session, OTPToken
  - MT5Account (MASTER / SLAVE)
  - SubscriptionTier, Subscription, Payment
  - Signal, SignalExecution, MonthlyReport
- JWT authentication with optional 2FA implemented
- Subscription tiers with limits and signal delays defined
- Signal delay implemented using `receivedAt` offset
- Heartbeat endpoint for MT5 connection tracking
- Stripe webhook endpoint implemented and wired
- Cron scheduler integrated for cleanup and reporting
- Frontend auth and token handling via Zustand
- API client auto-injects Bearer tokens
- Session continuity guardrails enforced via `CLAUDE.md`
- **Hardening Complete (Dec 2025):**
  - `/api/signals/ack` is now idempotent (race-safe, duplicate-proof)
  - Subscription tier enforcement validated (limits, delays, SLAVE accounts)
  - MT5 polling hardened (explicit accountId required, subscription period check)
  - Cron jobs audited for safe re-runs (no duplicate emails)
  - Stripe webhooks secured (signature validation + event replay protection)
- **Frontend Enhancement (Dec 2025):**
  - Dark/Light theme toggle with CSS variables and smooth transitions
  - Advanced analytics charts (Performance, WinLoss, SymbolBar, SuccessGauge)
  - Admin dashboard with role-based access (Overview, Users, Signals, Revenue)
  - Admin API client with all management endpoints
  - Display font (Space Grotesk) for headers
  - Micro-interactions and polish (noise texture, glass effects, animations)
  - Sidebar toggle fixed (ChevronLeft/Right on desktop, Menu on mobile)
  - Avatar change functionality in Settings (upload, remove, base64 storage)
  - Avatar display in dashboard header and sidebar
- **Dashboard Chart Fix (Dec 27, 2025):**
  - Fixed PerformanceChart to show Growth/Drawdown instead of mock signal data
  - Fixed SymbolBarChart to show empty state instead of mock data
  - Chart now displays real performance metrics when data is available
- **E2E Testing Complete (Dec 27, 2025):**
  - Signal send flow tested (MASTER → Backend)
  - Signal receive flow tested (Backend → SLAVE)
  - SignalExecution creation verified for subscribers
  - Delay enforcement confirmed (60s Free tier via createdAt filter)
  - Provider isolation verified (MASTER user excluded from own signals)
  - Frontend homepage and API integration verified
- **Documentation Complete (Dec 27, 2025):**
  - README.md already comprehensive with API endpoints
  - Created docs/EA-CONFIGURATION.md (MT5 EA setup guide)
  - Created docs/DEPLOYMENT.md (Railway deployment runbook)
- **Deployment LIVE (Dec 27, 2025):**
  - Frontend: https://signal-service-frontend-production.up.railway.app ✅
  - Backend: https://signal-service-api-production.up.railway.app ✅
  - Both services healthy and operational
  - Admin user: admin@signalservice.com

---

## What Is IN PROGRESS

- None (platform fully deployed and operational)

---

## What Is BLOCKED

- None

---

## Next Actions (STRICT ORDER — DO NOT REORDER)

1. Deploy updated backend with API key endpoints
   - Push changes to trigger Railway deployment
   - Verify new endpoints work in production

2. Generate API keys for MT5 accounts
   - Login to get access token
   - Create MT5 accounts via API (MASTER and SLAVE)
   - Generate API keys for each account
   - See docs/EA-CONFIGURATION.md for step-by-step guide

3. Configure MT5 EAs with API keys
   - Update SignalSender EA with MASTER API key
   - Update SignalReceiver EA with SLAVE API key
   - Test live trade signal copying

4. Configure Stripe webhooks for production (optional)
   - Add webhook endpoint: https://signal-service-api-production.up.railway.app/api/webhooks/stripe
   - Update STRIPE_WEBHOOK_SECRET env var on Railway

5. Configure Resend email domain (optional)
   - Verify domain at resend.com/domains
   - Currently only fxjoel237@gmail.com can receive test emails

Claude must always start from this section unless explicitly instructed otherwise.

---

## Constraints / Guardrails

- No architecture changes
- No framework or stack changes
- No auth or payment logic refactors unless explicitly instructed
- Backend: Node.js + Express + Prisma only
- Frontend: Next.js + Zustand only
- MT5 communication remains EA-based over HTTP
- Minimal, surgical code changes only
- Repository code is authoritative

---

## Resume Instruction

If the user says:
"Resume", "Continue", or "Pick up where we left off"

Claude MUST:

1. Read CLAUDE.md
2. Read this file
3. Continue from "Next Actions"
4. Implement without re-explaining or re-planning

---

## End of CLAUDE_STATE.md
