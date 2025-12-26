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

---

## What Is IN PROGRESS

- MT5 Live Connection Testing

---

## What Is BLOCKED

- None

---

## Next Actions (STRICT ORDER — DO NOT REORDER)

1. End-to-end testing of MT5 EA ↔ backend flow
   - Test signal send/receive with real EAs
   - Verify delay enforcement works correctly
2. Frontend integration verification
   - Dashboard signal history
   - Subscription management UI
   - MT5 account management
3. Production deployment preparation
   - Environment variable validation
   - Database migration scripts
   - Monitoring and alerting setup
4. Documentation
   - API documentation update
   - EA configuration guide
   - Deployment runbook

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
