# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A full-stack trading signal service platform that connects MetaTrader 5 (MT5) terminals. The system allows a MASTER MT5 account to send trading signals via an Expert Advisor (EA), which are then distributed to SLAVE MT5 accounts belonging to subscribers. The platform includes user authentication, OTP verification, subscription management (with Stripe integration), and automated cron jobs for cleanup and reporting.

## Development Commands

### Backend (Node.js + Express + Prisma)

```bash
cd backend

# Development
npm run dev                # Start development server with tsx watch

# Database
npm run db:generate        # Generate Prisma client
npm run db:push           # Push schema changes to database (no migration)
npm run db:migrate        # Create and apply migrations
npm run db:studio         # Open Prisma Studio GUI

# Production
npm run build             # Compile TypeScript to dist/
npm start                 # Run compiled code from dist/

# Cron Jobs
npm run cron:start        # Start scheduler in standalone mode
```

### Frontend (Next.js + React)

```bash
cd frontend

# Development
npm run dev               # Start Next.js dev server (port 3000)

# Production
npm run build             # Build for production
npm start                 # Start production server

# Linting
npm run lint              # Run ESLint
```

## Architecture

### Signal Flow

1. **Sender EA (MASTER)** → HTTP POST `/api/signals` → Backend creates `Signal` record
2. **Backend** → Creates `SignalExecution` records for all active subscribers based on their subscription tier
3. **Receiver EA (SLAVE)** → HTTP GET `/api/signals/pending` → Retrieves queued signals with tier-based delay
4. **Receiver EA** → Executes trade → HTTP POST `/api/signals/ack` → Confirms execution

### Database Schema (Prisma)

Key models in [backend/prisma/schema.prisma](backend/prisma/schema.prisma):

- **User** - Main user table with email, password, 2FA settings, and subscription relationship
- **Session** - JWT session tokens (access + refresh)
- **OTPToken** - One-time passwords for email verification, 2FA, password reset
- **MT5Account** - Linked MT5 accounts (MASTER or SLAVE type) with heartbeat tracking
- **SubscriptionTier** - Predefined tiers (Free, Basic, Pro, Premium) with limits
- **Subscription** - User subscription state with Stripe integration
- **Payment** - Payment history linked to Stripe
- **Signal** - Trading signals sent from MASTER accounts
- **SignalExecution** - Queued signals for SLAVE accounts with execution status
- **MonthlyReport** - Generated reports with trading statistics

### Authentication Flow

1. **Registration** → User created with `emailVerified: false` → OTP sent via email
2. **Email Verification** → User enters OTP → Account activated
3. **Login** → If 2FA disabled: returns JWT tokens → If 2FA enabled: returns challenge requiring OTP
4. **2FA Verification** → User enters OTP (email/SMS/TOTP) → Returns JWT tokens
5. **JWT Tokens** → Access token (short-lived) + Refresh token (7 days) stored in Session table

### Middleware Chain

Located in [backend/src/middleware](backend/src/middleware):

- **authenticate** - Verifies JWT access token, loads user into `req.user`
- **requireRole** - RBAC check (USER, PROVIDER, ADMIN, SUPER_ADMIN)
- **requireAdmin** - Admin/super admin only
- **requireEmailVerified** - Ensures email is verified
- **requireActiveSubscription** - Checks for active subscription

### Subscription Tier Features

Defined in Prisma schema and seeded via [backend/prisma/seed.ts](backend/prisma/seed.ts):

- **Free**: 5 signals/day, 1 SLAVE account, 60s delay
- **Basic**: 50 signals/day, 2 SLAVE accounts, 30s delay
- **Pro**: Unlimited signals, 5 SLAVE accounts, 5s delay
- **Premium**: Unlimited signals, 20 SLAVE accounts, instant delivery

### Cron Jobs

Managed by [backend/src/jobs/scheduler.ts](backend/src/jobs/scheduler.ts):

- **Every minute**: Cleanup expired signals
- **Every hour**: Mark disconnected MT5 accounts (no heartbeat in 15 min)
- **Every 6 hours**: Update account connection status
- **Daily at midnight**: Check expiring subscriptions, send reminders, downgrade expired to Free tier
- **Daily at 1 AM**: Cleanup expired sessions
- **Daily at 2 AM**: Cleanup expired OTP tokens
- **Monthly (1st at 3 AM)**: Generate monthly reports and email to users

## Key Implementation Details

### Signal Delay Implementation

When creating `SignalExecution` records in [backend/src/services/signal.service.ts](backend/src/services/signal.service.ts):
- Each execution's `receivedAt` timestamp is offset by the subscription tier's `signalDelay` value
- Receiver EAs query `/api/signals/pending` which filters executions where `receivedAt <= NOW()`

### Heartbeat System

MT5 EAs periodically POST to `/api/signals/heartbeat` with:
- `accountId` - EA identifier
- `balance`, `equity`, `profit` - Account stats

This updates `MT5Account.lastHeartbeat` and `isConnected` status.

### Stripe Webhook Handling

Located in [backend/src/routes/webhook.routes.ts](backend/src/routes/webhook.routes.ts):
- Endpoint: `/api/webhooks/stripe`
- Requires raw body (configured in [backend/src/index.ts](backend/src/index.ts:51))
- Handles events: `checkout.session.completed`, `invoice.payment_succeeded`, `invoice.payment_failed`, `customer.subscription.deleted`

### Frontend State Management

Using Zustand with persistence in [frontend/src/lib/store.ts](frontend/src/lib/store.ts):
- `useAuthStore` - User, subscription, JWT tokens
- Tokens stored in localStorage (via persist middleware)
- API client in [frontend/src/lib/api.ts](frontend/src/lib/api.ts) automatically injects Bearer token

## Environment Variables

### Backend (.env)

```env
DATABASE_URL="postgresql://user:pass@localhost:5432/signal_service"
JWT_SECRET="your-secret-key"
JWT_EXPIRES_IN="1h"
REFRESH_TOKEN_EXPIRES_IN="7d"
SMTP_HOST="smtp.gmail.com"
SMTP_PORT=587
SMTP_USER="your-email@gmail.com"
SMTP_PASS="your-app-password"
TWILIO_ACCOUNT_SID="..."
TWILIO_AUTH_TOKEN="..."
TWILIO_PHONE_NUMBER="+1234567890"
STRIPE_SECRET_KEY="sk_test_..."
STRIPE_WEBHOOK_SECRET="whsec_..."
PORT=3001
FRONTEND_URL="http://localhost:3000"
```

### Frontend (.env.local)

```env
NEXT_PUBLIC_API_URL="http://localhost:3001"
```

## Testing Workflow

### Test New Features

1. Start backend: `cd backend && npm run dev`
2. Start frontend: `cd frontend && npm run dev`
3. Check Prisma Studio: `cd backend && npm run db:studio` (optional)

### Test Signal Flow

1. Create test users with different subscription tiers
2. Register MASTER account: POST `/api/signals` with `accountId` and `X-Account-Id` header
3. Register SLAVE accounts for subscribers
4. Send signal from MASTER EA
5. Query pending signals: GET `/api/signals/pending?accountId=SLAVE_001`
6. Verify delay based on subscription tier

### Database Migrations

When modifying [backend/prisma/schema.prisma](backend/prisma/schema.prisma):

1. Make schema changes
2. Run `npm run db:push` for development (no migration files)
3. For production, run `npm run db:migrate` to create migration files
4. Always run `npm run db:generate` after schema changes to update Prisma Client

## Common Patterns

### Adding New Routes

1. Create route file in [backend/src/routes/](backend/src/routes/)
2. Import and register in [backend/src/index.ts](backend/src/index.ts)
3. Apply middleware: `router.post('/endpoint', authenticate, requireEmailVerified, handler)`

### Adding New Services

1. Create service file in [backend/src/services/](backend/src/services/)
2. Export async functions that interact with Prisma
3. Handle errors and return structured results

### Frontend API Calls

Use the API client from [frontend/src/lib/api.ts](frontend/src/lib/api.ts):

```typescript
import { authApi } from '@/lib/api';
import { useAuthStore } from '@/lib/store';

const { data, error } = await authApi.login(email, password);
if (data?.accessToken) {
  useAuthStore.getState().setTokens(data.accessToken, data.refreshToken);
}
```

## Important Notes

- **Path Aliases**: Backend uses `@/*` for `src/*` (configured in tsconfig.json)
- **Module System**: Backend uses ES modules (`"type": "module"` in package.json)
- **BigInt Handling**: Signal tickets use `BigInt` type - convert with `BigInt(value)` when creating, use `.toString()` when serializing to JSON
- **Date Handling**: All timestamps in Prisma are `DateTime` - use `new Date()` for current time
- **Password Hashing**: Uses bcryptjs with 12 rounds (in [backend/src/services/auth.service.ts](backend/src/services/auth.service.ts))
- **Token Verification**: JWT tokens verified in [backend/src/services/auth.service.ts](backend/src/services/auth.service.ts) with type checking (access vs refresh)
- **Cron Jobs**: Automatically started in [backend/src/index.ts](backend/src/index.ts:99) unless `NODE_ENV=test`
