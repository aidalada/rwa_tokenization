'use client'; // <-- 1. ЭТО САМАЯ ВАЖНАЯ СТРОЧКА!

import React from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WagmiProvider, http } from 'wagmi';
import { arbitrumSepolia } from 'wagmi/chains';
import { RainbowKitProvider, getDefaultConfig } from '@rainbow-me/rainbowkit';
import { ApolloClient, InMemoryCache, ApolloProvider } from '@apollo/client';

import '@rainbow-me/rainbowkit/styles.css';

// 1. Настройка Wagmi + RainbowKit (MetaMask + WalletConnect)
const config = getDefaultConfig({
  appName: 'RWA Platform DAO',
  projectId: 'YOUR_WALLETCONNECT_PROJECT_ID', // Получать на cloud.walletconnect.com
  chains: [arbitrumSepolia],
  transports: {
    [arbitrumSepolia.id]: http(),
  },
});

// 2. Настройка Клиента The Graph
const apolloClient = new ApolloClient({
  uri: 'https://api.studio.thegraph.com/query/1753443/final/v0.0.1',
  cache: new InMemoryCache(),
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          {/* 2. ИСПРАВЛЕНО ИМЯ ПЕРЕМЕННОЙ НА apolloClient */}
          <ApolloProvider client={apolloClient}> 
            {children}
          </ApolloProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}