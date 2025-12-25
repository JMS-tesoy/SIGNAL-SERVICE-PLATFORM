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

---

## What Is IN PROGRESS

- End-to-end MT5 EA ↔ backend reliability validation
- Hardening `/api/signals/ack` acknowledgment flow
- Edge case handling:
  - Duplicate acknowledgments
  - Late SLAVE polling
  - Disconnected MT5 accounts
- Production-mode verification of cron jobs
- Security review of auth, Stripe, and webhook handling

---

## What Is BLOCKED

- None

---

## Next Actions (STRICT ORDER — DO NOT REORDER)

1. Harden signal acknowledgment flow
   - Make `/api/signals/ack` idempotent
   - Prevent double execution marking
2. Validate subscription tier enforcement
   - Signal count limits
   - SLAVE account limits
   - Delay enforcement correctness
3. Add defensive validation for MT5 polling
   - Invalid or unknown accountId
   - Expired or inactive subscriptions
4. Audit cron jobs
   - Safe re-runs
   - No destructive overlap
5. Verify Stripe webhook security
   - Signature validation
   - Event replay protection

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
