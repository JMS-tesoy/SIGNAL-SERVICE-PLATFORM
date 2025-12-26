// =============================================================================
// SIGNAL SERVICE - Trade Signal Processing
// =============================================================================

import prisma from '../config/database.js';
import { checkSignalLimit } from './subscription.service.js';
import { SignalAction, TradeType, SignalStatus, ExecutionStatus } from '@prisma/client';

// =============================================================================
// TYPES
// =============================================================================

interface IncomingSignal {
  action: string;
  symbol: string;
  type: string;
  volume: number;
  price: number;
  sl?: number;
  tp?: number;
  ticket?: number;
  magic?: number;
  comment?: string;
  accountId: string;
}

interface SignalResult {
  success: boolean;
  message: string;
  signalId?: string;
}

interface PendingSignalsResult {
  success: boolean;
  signals: any[];
  message?: string;
}

// =============================================================================
// RECEIVE SIGNAL FROM SENDER EA
// =============================================================================

export async function receiveSignal(
  providerId: string,
  signal: IncomingSignal
): Promise<SignalResult> {
  try {
    const mt5Account = await prisma.mT5Account.findFirst({
      where: {
        userId: providerId,
        accountId: signal.accountId,
        accountType: 'MASTER',
      },
    });

    if (!mt5Account) {
      return { success: false, message: 'Master account not found' };
    }

    const newSignal = await prisma.signal.create({
      data: {
        providerId,
        mt5AccountId: mt5Account.id,
        action: signal.action.toUpperCase() as SignalAction,
        symbol: signal.symbol,
        type: signal.type.toUpperCase() as TradeType,
        volume: signal.volume,
        price: signal.price,
        sl: signal.sl || null,
        tp: signal.tp || null,
        masterTicket: signal.ticket ? BigInt(signal.ticket) : null,
        magic: signal.magic || null,
        comment: signal.comment || null,
        status: 'PENDING',
        expiresAt: new Date(Date.now() + 120 * 1000), // 2 minutes expiry
      },
    });

    await createExecutionsForSubscribers(newSignal.id, providerId);

    return { success: true, message: 'Signal received', signalId: newSignal.id };
  } catch (error) {
    console.error('Receive signal error:', error);
    return { success: false, message: 'Failed to process signal' };
  }
}

// =============================================================================
// CREATE EXECUTIONS FOR SUBSCRIBERS
// =============================================================================

async function createExecutionsForSubscribers(signalId: string, providerId: string): Promise<void> {
  const subscribers = await prisma.subscription.findMany({
    where: {
      status: 'ACTIVE',
      user: {
        status: 'ACTIVE',
        id: { not: providerId },
        mt5Accounts: { some: { accountType: 'SLAVE' } },
      },
    },
    include: {
      user: {
        include: {
          mt5Accounts: { where: { accountType: 'SLAVE' } },
        },
      },
      tier: true,
    },
  });

  const executions = subscribers.flatMap((sub) =>
    sub.user.mt5Accounts.map((account) => ({
      signalId,
      userId: sub.user.id,
      mt5AccountId: account.id,
      status: 'PENDING' as ExecutionStatus,
    }))
  );

  if (executions.length > 0) {
    await prisma.signalExecution.createMany({ data: executions, skipDuplicates: true });
  }
}

// =============================================================================
// GET PENDING SIGNALS FOR RECEIVER EA
// =============================================================================

export async function getPendingSignals(
  userId: string,
  accountId: string
): Promise<PendingSignalsResult> {
  try {
    const limitCheck = await checkSignalLimit(userId);
    if (!limitCheck.allowed) {
      return { success: true, signals: [], message: 'Daily signal limit reached' };
    }

    const mt5Account = await prisma.mT5Account.findFirst({
      where: { userId, accountId, accountType: 'SLAVE' },
    });

    if (!mt5Account) {
      return { success: false, signals: [], message: 'Slave account not found' };
    }

    const subscription = await prisma.subscription.findUnique({
      where: { userId },
      include: { tier: true },
    });

    const signalDelay = subscription?.tier.signalDelay || 0;
    const delayedTime = new Date(Date.now() - signalDelay * 1000);

    const executions = await prisma.signalExecution.findMany({
      where: {
        userId,
        mt5AccountId: mt5Account.id,
        status: 'PENDING',
        signal: {
          status: { in: ['PENDING', 'ACTIVE'] },
          expiresAt: { gt: new Date() },
          createdAt: { lte: delayedTime },
        },
      },
      include: { signal: true },
      orderBy: { receivedAt: 'asc' },
      take: 10,
    });

    const signals = executions.map((exec) => ({
      signal_id: exec.id,
      action: exec.signal.action,
      symbol: exec.signal.symbol,
      type: exec.signal.type,
      volume: Number(exec.signal.volume),
      price: Number(exec.signal.price),
      sl: exec.signal.sl ? Number(exec.signal.sl) : 0,
      tp: exec.signal.tp ? Number(exec.signal.tp) : 0,
      ticket: exec.signal.masterTicket ? Number(exec.signal.masterTicket) : 0,
      magic: exec.signal.magic || 0,
      timestamp_utc: exec.signal.createdAt.toISOString(),
    }));

    return { success: true, signals };
  } catch (error) {
    console.error('Get pending signals error:', error);
    return { success: false, signals: [], message: 'Failed to fetch signals' };
  }
}

// =============================================================================
// ACKNOWLEDGE SIGNAL EXECUTION (IDEMPOTENT)
// =============================================================================

const TERMINAL_STATUSES: ExecutionStatus[] = ['EXECUTED', 'FAILED', 'EXPIRED', 'SKIPPED'];

export async function acknowledgeExecution(
  executionId: string,
  userId: string,
  status: string,
  details?: {
    executedVolume?: number;
    executedPrice?: number;
    slippage?: number;
    slaveTicket?: number;
    errorCode?: number;
    errorMessage?: string;
  }
): Promise<SignalResult> {
  try {
    // Check current execution state first (idempotency check)
    const existing = await prisma.signalExecution.findFirst({
      where: { id: executionId, userId },
    });

    if (!existing) {
      return { success: false, message: 'Execution not found' };
    }

    // If already in a terminal state, return success (idempotent)
    if (TERMINAL_STATUSES.includes(existing.status)) {
      return {
        success: true,
        message: `Already acknowledged as ${existing.status}`
      };
    }

    // Parse incoming status
    let execStatus: ExecutionStatus;
    if (status.startsWith('EXECUTED')) execStatus = 'EXECUTED';
    else if (status.startsWith('FAILED')) execStatus = 'FAILED';
    else if (status === 'EXPIRED') execStatus = 'EXPIRED';
    else if (status.startsWith('REJECTED') || status.startsWith('SKIPPED')) execStatus = 'SKIPPED';
    else execStatus = 'PENDING';

    // Use conditional update to prevent race conditions
    const result = await prisma.signalExecution.updateMany({
      where: {
        id: executionId,
        userId,
        status: 'PENDING', // Only update if still PENDING
      },
      data: {
        status: execStatus,
        executedAt: execStatus === 'EXECUTED' ? new Date() : null,
        acknowledgedAt: new Date(),
        executedVolume: details?.executedVolume,
        executedPrice: details?.executedPrice,
        slippage: details?.slippage,
        slaveTicket: details?.slaveTicket ? BigInt(details.slaveTicket) : null,
        errorCode: details?.errorCode,
        errorMessage: details?.errorMessage || (status.includes(':') ? status.split(':')[1] : null),
      },
    });

    // If no rows updated, another request already processed it
    if (result.count === 0) {
      const current = await prisma.signalExecution.findFirst({
        where: { id: executionId, userId },
        select: { status: true },
      });
      return {
        success: true,
        message: `Already acknowledged as ${current?.status || 'UNKNOWN'}`
      };
    }

    return { success: true, message: 'Execution acknowledged' };
  } catch (error) {
    console.error('Acknowledge execution error:', error);
    return { success: false, message: 'Failed to acknowledge execution' };
  }
}

// =============================================================================
// UPDATE HEARTBEAT
// =============================================================================

export async function updateHeartbeat(
  userId: string,
  accountId: string,
  data: { balance?: number; equity?: number; profit?: number }
): Promise<SignalResult> {
  try {
    await prisma.mT5Account.updateMany({
      where: { userId, accountId },
      data: {
        isConnected: true,
        lastHeartbeat: new Date(),
        balance: data.balance,
        equity: data.equity,
        profit: data.profit,
      },
    });
    return { success: true, message: 'Heartbeat updated' };
  } catch (error) {
    console.error('Heartbeat update error:', error);
    return { success: false, message: 'Failed to update heartbeat' };
  }
}

// =============================================================================
// GET SIGNAL HISTORY
// =============================================================================

export async function getSignalHistory(
  userId: string,
  options: { limit?: number; offset?: number; symbol?: string; startDate?: Date; endDate?: Date } = {}
) {
  const { limit = 50, offset = 0, symbol, startDate, endDate } = options;

  const where: any = {
    OR: [{ providerId: userId }, { executions: { some: { userId } } }],
  };

  if (symbol) where.symbol = symbol;
  if (startDate || endDate) {
    where.createdAt = {};
    if (startDate) where.createdAt.gte = startDate;
    if (endDate) where.createdAt.lte = endDate;
  }

  const [signals, total] = await Promise.all([
    prisma.signal.findMany({
      where,
      include: {
        executions: { where: { userId } },
        provider: { select: { name: true, email: true } },
      },
      orderBy: { createdAt: 'desc' },
      skip: offset,
      take: limit,
    }),
    prisma.signal.count({ where }),
  ]);

  return { signals, total, limit, offset };
}

// =============================================================================
// GET SIGNAL STATISTICS
// =============================================================================

export async function getSignalStatistics(userId: string, period: 'day' | 'week' | 'month' | 'all' = 'month') {
  const now = new Date();
  let startDate: Date;

  switch (period) {
    case 'day': startDate = new Date(now.setHours(0, 0, 0, 0)); break;
    case 'week': startDate = new Date(now.setDate(now.getDate() - 7)); break;
    case 'month': startDate = new Date(now.setMonth(now.getMonth() - 1)); break;
    case 'all': startDate = new Date(0); break;
  }

  const executions = await prisma.signalExecution.findMany({
    where: { userId, receivedAt: { gte: startDate } },
    include: { signal: true },
  });

  const stats = {
    totalSignals: executions.length,
    executed: executions.filter((e) => e.status === 'EXECUTED').length,
    failed: executions.filter((e) => e.status === 'FAILED').length,
    skipped: executions.filter((e) => e.status === 'SKIPPED').length,
    expired: executions.filter((e) => e.status === 'EXPIRED').length,
    bySymbol: {} as Record<string, number>,
    byAction: { OPEN: 0, CLOSE: 0, MODIFY: 0 },
  };

  executions.forEach((exec) => {
    stats.bySymbol[exec.signal.symbol] = (stats.bySymbol[exec.signal.symbol] || 0) + 1;
    stats.byAction[exec.signal.action]++;
  });

  return stats;
}

// =============================================================================
// CLEANUP EXPIRED SIGNALS
// =============================================================================

export async function cleanupExpiredSignals(): Promise<number> {
  const result = await prisma.signal.updateMany({
    where: { status: { in: ['PENDING', 'ACTIVE'] }, expiresAt: { lt: new Date() } },
    data: { status: 'EXPIRED' },
  });

  await prisma.signalExecution.updateMany({
    where: { status: 'PENDING', signal: { status: 'EXPIRED' } },
    data: { status: 'EXPIRED' },
  });

  return result.count;
}
