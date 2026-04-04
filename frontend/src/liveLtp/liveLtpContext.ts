import { createContext, useContext } from 'react';

export type LiveLtpMap = Record<string, number>;

export const LiveLtpContext = createContext<LiveLtpMap>({});

export function useLiveLtp(): LiveLtpMap {
  return useContext(LiveLtpContext);
}
