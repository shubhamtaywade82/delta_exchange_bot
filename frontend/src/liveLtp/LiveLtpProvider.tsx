import React, { useEffect, useState } from 'react';
import { createConsumer, type Subscription } from '@rails/actioncable';
import { LiveLtpContext, type LiveLtpMap } from './liveLtpContext';

type LtpPayload = {
  type?: string;
  symbol?: string;
  price?: unknown;
};

function applyLtpMessage(
  prev: LiveLtpMap,
  data: LtpPayload
): LiveLtpMap | null {
  if (data.type !== 'ltp' || !data.symbol) return null;
  const p = Number(data.price);
  if (!Number.isFinite(p) || p <= 0) return null;
  if (prev[data.symbol] === p) return null;
  return { ...prev, [data.symbol]: p };
}

export function LiveLtpProvider({ children }: { children: React.ReactNode }) {
  const [map, setMap] = useState<LiveLtpMap>({});

  useEffect(() => {
    const consumer = createConsumer('/cable');
    const subscription: Subscription = consumer.subscriptions.create(
      { channel: 'TradingChannel' },
      {
        received(data: LtpPayload) {
          setMap(prev => applyLtpMessage(prev, data) ?? prev);
        },
      }
    );

    return () => {
      subscription.unsubscribe();
      consumer.disconnect();
    };
  }, []);

  return (
    <LiveLtpContext.Provider value={map}>{children}</LiveLtpContext.Provider>
  );
}
