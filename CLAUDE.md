# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

======================================================================

MANDATORY SESSION CONTINUITY RULES (HIGHEST PRIORITY)

1. Assume all prior chat context is unreliable or lost
2. Never rely on previous conversations
3. Always read CLAUDE_STATE.md before responding
4. Continue strictly from "Next Actions"
5. Do NOT re-architect, refactor, or redesign unless explicitly instructed
6. Do NOT repeat completed work
7. Do NOT summarize unless explicitly asked
8. Ask questions ONLY if blocked and only one precise question

If CLAUDE_STATE.md is missing or incomplete:

- STOP
- Ask for clarification
- Do NOT guess or proceed

======================================================================

MANDATORY STARTUP PROCEDURE (EVERY RESPONSE)

Before taking any action, Claude MUST:

1. Read:
   - CLAUDE.md
   - CLAUDE_STATE.md
2. Identify:
   - Current Phase
   - What Is IN PROGRESS
   - Next Actions
3. Proceed ONLY from "Next Actions"
4. Implement directly when applicable

If the user says:
"init", "resume", "continue", or "pick up where we left off"

Claude MUST immediately continue from "Next Actions"
without re-planning or re-explaining.

======================================================================

TECH STACK

Backend:
- Node.js + Express (ES modules)
- Prisma ORM + PostgreSQL
- JWT auth with bcryptjs
- Stripe for payments
- Resend for email, Twilio for SMS
- node-cron for scheduled jobs
- zod for validation

Frontend:
- Next.js 16 + React 18
- Zustand for state management
- Tailwind CSS + Radix UI components
- Recharts for analytics
- Framer Motion for animations
- react-hook-form + zod validation

======================================================================

PRODUCTION URLS

- Frontend: https://signal-service-frontend-production.up.railway.app
- Backend API: https://signal-service-api-production.up.railway.app
- Admin user: admin@signalservice.com

======================================================================

PROJECT OVERVIEW

A full-stack trading signal service platform that connects MetaTrader 5 (MT5)
terminals.

The system allows:

- A MASTER MT5 account to send trading signals via an Expert Advisor (EA)
- Signals to be distributed to SLAVE MT5 accounts belonging to subscribers

Core features:

- User authentication with OTP and optional 2FA
- Subscription management with Stripe integration
- Tier-based signal limits and delivery delays
- Automated cron jobs for cleanup and reporting
- Reliable EA ↔ backend HTTP communication

======================================================================

ARCHITECTURE

Signal Flow:

1. Sender EA (MASTER)
   → HTTP POST /api/signals
   → Backend creates Signal record

2. Backend
   → Creates SignalExecution records per subscriber tier

3. Receiver EA (SLAVE)
   → HTTP GET /api/signals/pending
   → Retrieves eligible queued signals

4. Receiver EA
   → Executes trade
   → HTTP POST /api/signals/ack

======================================================================

DATABASE SCHEMA (PRISMA)

Key models:

- User
- Session
- OTPToken
- MT5Account (MASTER / SLAVE)
- SubscriptionTier
- Subscription
- Payment
- Signal
- SignalExecution
- MonthlyReport

Schema source:
backend/prisma/schema.prisma

======================================================================

AUTHENTICATION FLOW

1. Registration
   → User created with emailVerified = false
   → OTP sent

2. Email Verification
   → OTP validated
   → Account activated

3. Login

   - No 2FA → JWT tokens returned
   - With 2FA → OTP challenge

4. JWT
   - Access token (short-lived)
   - Refresh token (7 days, stored in Session table)

======================================================================

MIDDLEWARE CHAIN

Located in backend/src/middleware:

- authenticate
- requireRole
- requireAdmin
- requireEmailVerified
- requireActiveSubscription

======================================================================

SUBSCRIPTION TIERS

Seeded via backend/prisma/seed.ts:

- Free: 5 signals/day, 1 SLAVE, 60s delay
- Basic: 50 signals/day, 2 SLAVEs, 30s delay
- Pro: Unlimited, 5 SLAVEs, 5s delay
- Premium: Unlimited, 20 SLAVEs, instant

======================================================================

CRON JOBS

Managed by backend/src/jobs/scheduler.ts:

- Every minute: cleanup expired signals
- Every hour: mark disconnected MT5 accounts
- Every 6 hours: update account status
- Daily:
  - Subscription checks and downgrades
  - Session cleanup
  - OTP cleanup
- Monthly:
  - Generate reports and email users

======================================================================

KEY IMPLEMENTATION DETAILS

Signal Delay:

- Implemented by offsetting SignalExecution.receivedAt
- Receiver filters by receivedAt <= NOW()

Heartbeat:

- MT5 EAs POST /api/signals/heartbeat
- Updates MT5Account.lastHeartbeat and isConnected

Stripe Webhooks:

- Endpoint: /api/webhooks/stripe
- Requires raw body
- Signature verification enforced

Frontend State:

- Zustand store
- JWT persisted in localStorage
- API client auto-injects Bearer token

MT5 EA Integration:

- SignalSender EA: MASTER terminal sends signals via POST /api/signals
- SignalReceiver EA: SLAVE terminal polls GET /api/signals/pending
- EAs authenticate via JWT Bearer token
- See docs/EA-CONFIGURATION.md for setup guide

======================================================================

DEVELOPMENT COMMANDS

Backend (Node.js + Express + Prisma):

cd backend
npm run dev
npm run db:generate
npm run db:push
npm run db:migrate
npm run db:studio
npm run build
npm start
npm run cron:start

Frontend (Next.js):

cd frontend
npm run dev
npm run build
npm start
npm run lint

======================================================================

ENVIRONMENT VARIABLES

Backend (.env):

- DATABASE_URL
- JWT_SECRET, JWT_EXPIRES_IN, REFRESH_TOKEN_EXPIRES_IN
- RESEND_API_KEY, EMAIL_FROM (email via Resend)
- TWILIO_* (SMS)
- STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PUBLISHABLE_KEY
- PORT, FRONTEND_URL, CORS_ORIGINS

Frontend (.env.local):

- NEXT_PUBLIC_API_URL
- NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY

======================================================================

CRITICAL GUARDRAILS

- No architecture changes without explicit instruction
- No framework or stack changes
- No auth or payment logic refactors unless requested
- Minimal, surgical code edits only
- Never delete working code without approval

Priority order:

1. Correctness
2. Continuity
3. Minimal change
4. Security
5. Performance

======================================================================

FINAL ENFORCEMENT CLAUSE

This repository is the single source of truth.

Claude must behave as if:

- The session is long-running
- Context loss is expected
- CLAUDE_STATE.md defines reality

Failure to follow this file is an error.

======================================================================

END OF CLAUDE.md
