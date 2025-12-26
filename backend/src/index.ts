// =============================================================================
// SIGNAL SERVICE BACKEND - Main Application Entry Point
// =============================================================================

import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';

// Routes
import authRoutes from './routes/auth.routes.js';
import securityRoutes from './routes/security.routes.js';
import otpRoutes from './routes/otp.routes.js';
import userRoutes from './routes/user.routes.js';
import subscriptionRoutes from './routes/subscription.routes.js';
import signalRoutes from './routes/signal.routes.js';
import webhookRoutes from './routes/webhook.routes.js';
import adminRoutes from './routes/admin.routes.js';
import downloadRoutes from './routes/download.routes.js';

// Middleware
import { requestLogger } from './middleware/logger.middleware.js';
import { errorHandler, notFoundHandler } from './middleware/error.middleware.js';

// Cron Jobs
import { startCronJobs } from './jobs/scheduler.js';

const app = express();
const PORT = process.env.PORT || 3001;

// =============================================================================
// GLOBAL MIDDLEWARE
// =============================================================================

// Security headers
app.use(helmet());

// CORS - Support multiple origins for development and production
const allowedOrigins = [
  process.env.FRONTEND_URL || 'http://localhost:3000',
  'http://localhost:3000',
  // Add production URLs via CORS_ORIGINS env var (comma-separated)
  ...(process.env.CORS_ORIGINS?.split(',').map(o => o.trim()) || []),
].filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, etc)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Too many requests, please try again later.' },
});
app.use('/api/', limiter);

// Stripe webhooks need raw body
app.use('/api/webhooks/stripe', express.raw({ type: 'application/json' }));

// JSON body parser
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Request logging
app.use(requestLogger);

// =============================================================================
// HEALTH CHECK
// =============================================================================

app.get('/health', (req: Request, res: Response) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// =============================================================================
// API ROUTES
// =============================================================================

app.use('/api/auth', authRoutes);
app.use('/api/security', securityRoutes);
app.use('/api/otp', otpRoutes);
app.use('/api/users', userRoutes);
app.use('/api/subscriptions', subscriptionRoutes);
app.use('/api/signals', signalRoutes);
app.use('/api/webhooks', webhookRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/downloads', downloadRoutes);

// =============================================================================
// ERROR HANDLING
// =============================================================================

app.use(notFoundHandler);
app.use(errorHandler);

// =============================================================================
// START SERVER
// =============================================================================

app.listen(PORT, () => {
  console.log(`🚀 Signal Service Backend running on http://localhost:${PORT}`);
  
  if (process.env.NODE_ENV !== 'test') {
    startCronJobs();
  }
});

export default app;
