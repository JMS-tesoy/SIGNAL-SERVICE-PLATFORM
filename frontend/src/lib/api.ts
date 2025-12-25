// =============================================================================
// API CLIENT - HTTP Request Utilities
// =============================================================================

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001';

// =============================================================================
// TYPES
// =============================================================================

interface ApiOptions extends RequestInit {
  token?: string | null;
}

interface ApiResponse<T> {
  data?: T;
  error?: string;
  status: number;
}

// =============================================================================
// BASE FETCH WRAPPER
// =============================================================================

async function apiFetch<T>(
  endpoint: string,
  options: ApiOptions = {}
): Promise<ApiResponse<T>> {
  const { token, ...fetchOptions } = options;

  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };

  if (token) {
    (headers as Record<string, string>)['Authorization'] = `Bearer ${token}`;
  }

  try {
    const response = await fetch(`${API_URL}${endpoint}`, {
      ...fetchOptions,
      headers,
    });

    const data = await response.json().catch(() => null);

    if (!response.ok) {
      return {
        error: data?.error || `Request failed with status ${response.status}`,
        status: response.status,
      };
    }

    return {
      data,
      status: response.status,
    };
  } catch (error) {
    return {
      error: 'Network error. Please check your connection.',
      status: 0,
    };
  }
}

// =============================================================================
// AUTH API
// =============================================================================

export const authApi = {
  register: (email: string, password: string, name?: string) =>
    apiFetch('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify({ email, password, name }),
    }),

  login: (email: string, password: string) =>
    apiFetch<{
      accessToken?: string;
      refreshToken?: string;
      user?: any;
      requiresTwoFactor?: boolean;
      twoFactorMethod?: string;
      tempToken?: string;
    }>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),

  verify2FA: (tempToken: string, code: string, method: string) =>
    apiFetch<{
      accessToken: string;
      refreshToken: string;
      user: any;
    }>('/api/auth/verify-2fa', {
      method: 'POST',
      body: JSON.stringify({ tempToken, code, method }),
    }),

  refreshToken: (refreshToken: string) =>
    apiFetch<{ accessToken: string }>('/api/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken }),
    }),

  logout: (token: string) =>
    apiFetch('/api/auth/logout', {
      method: 'POST',
      token,
    }),

  forgotPassword: (email: string) =>
    apiFetch('/api/auth/forgot-password', {
      method: 'POST',
      body: JSON.stringify({ email }),
    }),

  resetPassword: (email: string, code: string, newPassword: string) =>
    apiFetch('/api/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({ email, code, newPassword }),
    }),

  verifyEmail: (email: string, code: string) =>
    apiFetch('/api/auth/verify-email', {
      method: 'POST',
      body: JSON.stringify({ email, code }),
    }),

  resendVerification: (email: string) =>
    apiFetch('/api/auth/resend-verification', {
      method: 'POST',
      body: JSON.stringify({ email }),
    }),

  me: (token: string) =>
    apiFetch<{ user: any }>('/api/auth/me', { token }),
};

// =============================================================================
// OTP API
// =============================================================================

export const otpApi = {
  sendEmailOTP: (token: string, type: string) =>
    apiFetch('/api/otp/send/email', {
      method: 'POST',
      token,
      body: JSON.stringify({ type }),
    }),

  sendSMSOTP: (token: string, type: string, phone?: string) =>
    apiFetch('/api/otp/send/sms', {
      method: 'POST',
      token,
      body: JSON.stringify({ type, phone }),
    }),

  verify: (token: string, code: string, type: string) =>
    apiFetch('/api/otp/verify', {
      method: 'POST',
      token,
      body: JSON.stringify({ code, type }),
    }),

  setupTOTP: (token: string) =>
    apiFetch<{ secret: string; qrCode: string; manualEntryKey: string }>(
      '/api/otp/totp/setup',
      { method: 'POST', token }
    ),

  enableTOTP: (token: string, code: string) =>
    apiFetch<{ backupCodes: string[] }>('/api/otp/totp/enable', {
      method: 'POST',
      token,
      body: JSON.stringify({ code }),
    }),

  disableTOTP: (token: string, password: string) =>
    apiFetch('/api/otp/totp/disable', {
      method: 'POST',
      token,
      body: JSON.stringify({ password }),
    }),

  getStatus: (token: string) =>
    apiFetch<{
      twoFactorEnabled: boolean;
      twoFactorMethod: string;
      emailVerified: boolean;
    }>('/api/otp/status', { token }),
};

// =============================================================================
// SUBSCRIPTION API
// =============================================================================

export const subscriptionApi = {
  getTiers: () =>
    apiFetch<{ tiers: any[] }>('/api/subscriptions/tiers'),

  getCurrent: (token: string) =>
    apiFetch<{ subscription: any }>('/api/subscriptions/current', { token }),

  createCheckout: (token: string, tierId: string, billingCycle: string) =>
    apiFetch<{ url: string }>('/api/subscriptions/checkout', {
      method: 'POST',
      token,
      body: JSON.stringify({ tierId, billingCycle }),
    }),

  cancel: (token: string, immediately?: boolean) =>
    apiFetch('/api/subscriptions/cancel', {
      method: 'POST',
      token,
      body: JSON.stringify({ immediately }),
    }),

  resume: (token: string) =>
    apiFetch('/api/subscriptions/resume', {
      method: 'POST',
      token,
    }),

  changeTier: (token: string, tierId: string, billingCycle?: string) =>
    apiFetch('/api/subscriptions/change-tier', {
      method: 'POST',
      token,
      body: JSON.stringify({ tierId, billingCycle }),
    }),

  getPayments: (token: string, limit?: number) =>
    apiFetch<{ payments: any[] }>(
      `/api/subscriptions/payments${limit ? `?limit=${limit}` : ''}`,
      { token }
    ),

  getBillingPortal: (token: string) =>
    apiFetch<{ url: string }>('/api/subscriptions/billing-portal', { token }),

  getSignalLimit: (token: string) =>
    apiFetch<{ allowed: boolean; remaining: number; limit: number }>(
      '/api/subscriptions/signal-limit',
      { token }
    ),
};

// =============================================================================
// SIGNAL API
// =============================================================================

export const signalApi = {
  getHistory: (token: string, params?: { limit?: number; offset?: number; symbol?: string }) => {
    const query = new URLSearchParams();
    if (params?.limit) query.set('limit', params.limit.toString());
    if (params?.offset) query.set('offset', params.offset.toString());
    if (params?.symbol) query.set('symbol', params.symbol);
    
    return apiFetch<{ signals: any[]; total: number }>(
      `/api/signals/history?${query.toString()}`,
      { token }
    );
  },

  getStats: (token: string, period?: string) =>
    apiFetch<any>(
      `/api/signals/stats${period ? `?period=${period}` : ''}`,
      { token }
    ),
};

// =============================================================================
// USER API
// =============================================================================

export const userApi = {
  getProfile: (token: string) =>
    apiFetch<{ user: any }>('/api/users/profile', { token }),

  updateProfile: (token: string, data: { name?: string; phone?: string }) =>
    apiFetch('/api/users/profile', {
      method: 'PUT',
      token,
      body: JSON.stringify(data),
    }),

  changePassword: (token: string, currentPassword: string, newPassword: string) =>
    apiFetch('/api/users/password', {
      method: 'PUT',
      token,
      body: JSON.stringify({ currentPassword, newPassword }),
    }),

  getMT5Accounts: (token: string) =>
    apiFetch<{ accounts: any[] }>('/api/users/mt5-accounts', { token }),

  addMT5Account: (token: string, data: {
    accountId: string;
    accountType: 'MASTER' | 'SLAVE';
    broker?: string;
    server?: string;
  }) =>
    apiFetch('/api/users/mt5-accounts', {
      method: 'POST',
      token,
      body: JSON.stringify(data),
    }),

  deleteMT5Account: (token: string, accountId: string) =>
    apiFetch(`/api/users/mt5-accounts/${accountId}`, {
      method: 'DELETE',
      token,
    }),

  getSessions: (token: string) =>
    apiFetch<{ sessions: any[] }>('/api/users/sessions', { token }),

  revokeSession: (token: string, sessionId: string) =>
    apiFetch(`/api/users/sessions/${sessionId}`, {
      method: 'DELETE',
      token,
    }),

  revokeAllSessions: (token: string) =>
    apiFetch('/api/users/sessions', {
      method: 'DELETE',
      token,
    }),
};

// =============================================================================
// SECURITY API - Email Verification, 2FA, Sessions
// =============================================================================

export const securityApi = {
  // Email Verification
  sendEmailVerification: (token: string) =>
    apiFetch('/api/security/email/send-verification', {
      method: 'POST',
      token,
    }),

  verifyEmail: (token: string, code: string) =>
    apiFetch('/api/security/email/verify', {
      method: 'POST',
      token,
      body: JSON.stringify({ code }),
    }),

  getEmailStatus: (token: string) =>
    apiFetch<{ verified: boolean; verifiedAt: string | null }>(
      '/api/security/email/status',
      { token }
    ),

  // Two-Factor Authentication
  get2FAStatus: (token: string) =>
    apiFetch<{ enabled: boolean; method: string | null }>(
      '/api/security/2fa/status',
      { token }
    ),

  setupTOTP: (token: string) =>
    apiFetch<{ qrCode: string; manualEntryKey: string; secret: string }>(
      '/api/security/2fa/setup-totp',
      { method: 'POST', token }
    ),

  enableTOTP: (token: string, code: string) =>
    apiFetch<{ message: string; backupCodes: string[] }>(
      '/api/security/2fa/enable-totp',
      {
        method: 'POST',
        token,
        body: JSON.stringify({ code }),
      }
    ),

  enableEmail2FA: (token: string) =>
    apiFetch('/api/security/2fa/enable-email', {
      method: 'POST',
      token,
    }),

  disable2FA: (token: string, password: string) =>
    apiFetch('/api/security/2fa/disable', {
      method: 'POST',
      token,
      body: JSON.stringify({ password }),
    }),

  // Session Management
  getSessions: (token: string) =>
    apiFetch<{ sessions: any[] }>('/api/security/sessions', { token }),

  revokeSession: (token: string, sessionId: string) =>
    apiFetch(`/api/security/sessions/${sessionId}`, {
      method: 'DELETE',
      token,
    }),

  revokeAllSessions: (token: string) =>
    apiFetch<{ message: string; revokedCount: number }>(
      '/api/security/sessions/revoke-all',
      {
        method: 'POST',
        token,
      }
    ),

  // Security Activity
  getActivity: (token: string) =>
    apiFetch<{
      lastLogin: { at: string | null; ip: string | null };
      emailVerified: boolean;
      twoFactorEnabled: boolean;
      recentSessions: any[];
    }>('/api/security/activity', { token }),
};

// =============================================================================
// DOWNLOAD API
// =============================================================================

export interface DownloadFile {
  id: string;
  name: string;
  description: string;
  filename: string;
}

export const downloadApi = {
  getAvailableDownloads: (token: string) =>
    apiFetch<{ downloads: DownloadFile[] }>('/api/downloads', { token }),

  getDownloadUrl: (fileId: string) => `${API_URL}/api/downloads/${fileId}`,
};

export default {
  auth: authApi,
  otp: otpApi,
  subscription: subscriptionApi,
  signal: signalApi,
  user: userApi,
  security: securityApi,
  download: downloadApi,
};
