'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import { TrendingUp, Calendar } from 'lucide-react';

interface DataPoint {
  date: string;
  signals: number;
  executed: number;
  failed: number;
}

interface PerformanceChartProps {
  data?: DataPoint[];
  isLoading?: boolean;
}

// Generate mock data for demonstration
const generateMockData = (days: number): DataPoint[] => {
  const data: DataPoint[] = [];
  const now = new Date();

  for (let i = days - 1; i >= 0; i--) {
    const date = new Date(now);
    date.setDate(date.getDate() - i);

    const signals = Math.floor(Math.random() * 30) + 10;
    const executed = Math.floor(signals * (0.7 + Math.random() * 0.25));
    const failed = signals - executed;

    data.push({
      date: date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
      signals,
      executed,
      failed,
    });
  }

  return data;
};

const periods = [
  { label: '7D', value: 7 },
  { label: '30D', value: 30 },
  { label: '90D', value: 90 },
];

const CustomTooltip = ({ active, payload, label }: any) => {
  if (active && payload && payload.length) {
    return (
      <motion.div
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        className="glass rounded-xl p-4 shadow-xl"
      >
        <p className="text-foreground-muted text-sm mb-2">{label}</p>
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-primary" />
            <span className="text-sm">Total: <span className="font-semibold text-foreground">{payload[0]?.value}</span></span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-accent-green" />
            <span className="text-sm">Executed: <span className="font-semibold text-accent-green">{payload[1]?.value}</span></span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-accent-red" />
            <span className="text-sm">Failed: <span className="font-semibold text-accent-red">{payload[2]?.value}</span></span>
          </div>
        </div>
      </motion.div>
    );
  }
  return null;
};

export function PerformanceChart({ data, isLoading }: PerformanceChartProps) {
  const [period, setPeriod] = useState(30);

  const chartData = data || generateMockData(period);

  // Calculate totals
  const totalSignals = chartData.reduce((sum, d) => sum + d.signals, 0);
  const totalExecuted = chartData.reduce((sum, d) => sum + d.executed, 0);
  const successRate = totalSignals > 0 ? ((totalExecuted / totalSignals) * 100).toFixed(1) : '0';

  if (isLoading) {
    return (
      <div className="h-[350px] flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5 }}
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-primary/10">
            <TrendingUp className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h3 className="font-display text-lg font-semibold">Signal Performance</h3>
            <p className="text-sm text-foreground-muted">
              {totalSignals} signals • {successRate}% success rate
            </p>
          </div>
        </div>

        {/* Period Selector */}
        <div className="flex items-center gap-1 p-1 bg-background-elevated rounded-lg">
          {periods.map((p) => (
            <button
              key={p.value}
              onClick={() => setPeriod(p.value)}
              className={`px-3 py-1.5 text-sm font-medium rounded-md transition-all ${
                period === p.value
                  ? 'bg-primary text-white'
                  : 'text-foreground-muted hover:text-foreground hover:bg-background-tertiary'
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* Chart */}
      <div className="h-[280px]">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart
            data={chartData}
            margin={{ top: 10, right: 10, left: -20, bottom: 0 }}
          >
            <defs>
              <linearGradient id="signalsGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#0ea5e9" stopOpacity={0.3} />
                <stop offset="95%" stopColor="#0ea5e9" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="executedGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#22c55e" stopOpacity={0.3} />
                <stop offset="95%" stopColor="#22c55e" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="failedGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#ef4444" stopOpacity={0.2} />
                <stop offset="95%" stopColor="#ef4444" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid
              strokeDasharray="3 3"
              stroke="var(--border)"
              opacity={0.5}
              vertical={false}
            />
            <XAxis
              dataKey="date"
              axisLine={false}
              tickLine={false}
              tick={{ fill: 'var(--foreground-subtle)', fontSize: 12 }}
              dy={10}
            />
            <YAxis
              axisLine={false}
              tickLine={false}
              tick={{ fill: 'var(--foreground-subtle)', fontSize: 12 }}
              dx={-10}
            />
            <Tooltip content={<CustomTooltip />} />
            <Area
              type="monotone"
              dataKey="signals"
              stroke="#0ea5e9"
              strokeWidth={2}
              fill="url(#signalsGradient)"
              animationDuration={1000}
            />
            <Area
              type="monotone"
              dataKey="executed"
              stroke="#22c55e"
              strokeWidth={2}
              fill="url(#executedGradient)"
              animationDuration={1200}
            />
            <Area
              type="monotone"
              dataKey="failed"
              stroke="#ef4444"
              strokeWidth={2}
              fill="url(#failedGradient)"
              animationDuration={1400}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Legend */}
      <div className="flex items-center justify-center gap-6 mt-4">
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full bg-primary" />
          <span className="text-sm text-foreground-muted">Total Signals</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full bg-accent-green" />
          <span className="text-sm text-foreground-muted">Executed</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full bg-accent-red" />
          <span className="text-sm text-foreground-muted">Failed</span>
        </div>
      </div>
    </motion.div>
  );
}
