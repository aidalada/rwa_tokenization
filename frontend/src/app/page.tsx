'use client';

import { useState } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import { useQuery, gql } from '@apollo/client';

const RWA_TOKEN_ADDRESS = '0xd0d95536CdEfE06012Ed98Cb263eC10809f4Fe2A'; // Новый RWAToken
const GOVERNOR_ADDRESS  = '0x3622e9478Cb964F7af12016fc5B41E208C0edb5a'; // Новый RWAGovernor

const AMM_ADDRESS       = '0x1234567890123456789012345678901234567890'; 
const VAULT_ADDRESS     = '0x0987654321098765432109876543210987654321';

const GET_USER_DATA = gql`
  query GetUserData($userId: String!) {
    account(id: $userId) {
      hasKYC
      tokenBalance
    }
  }
`;

export default function DAppDashboard() {
  const { address, isConnected, chainId } = useAccount();
  const { switchChain } = useSwitchChain();
  const { writeContract, data: hash } = useWriteContract();
  const { isLoading: isTxPending } = useWaitForTransactionReceipt({ hash });

  const [swapAmount, setSwapAmount] = useState('');
  const [depositAmount, setDepositAmount] = useState('');
  const [errorLog, setErrorLog] = useState('');

  const { data: votingPower } = useReadContract({
    address: RWA_TOKEN_ADDRESS,
    abi: [{ name: 'getVotes', type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] }],
    functionName: 'getVotes',
    args: [address || '0x0000000000000000000000000000000000000000'],
  });

  const { data: graphData } = useQuery(GET_USER_DATA, {
    variables: { userId: address?.toLowerCase() || '' },
    skip: !isConnected,
  });

  const parseWeb3Error = (error: any) => {
    if (error.message.includes('User rejected the request')) {
      return '❌ Действие отменено пользователем в MetaMask.';
    }
    if (error.message.includes('Oracle: Price data is stale')) {
      return '❌ Ошибка оракула: Данные Chainlink устарели, транзакция заблокирована.';
    }
    if (error.message.includes('ERC4626: deposit more than max')) {
      return '❌ Ошибка Vault: Превышен лимит депозита.';
    }
    return `❌ Произошла ошибка: ${error.shortMessage || error.message}`;
  };

  const handleSwap = async () => {
    setErrorLog('');
    try {
      writeContract({
        address: AMM_ADDRESS,
        abi: [{ name: 'swap', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'tokenIn', type: 'address' }, { name: 'amountIn', type: 'uint256' }], outputs: [{ type: 'uint256' }] }],
        functionName: 'swap',
        args: [RWA_TOKEN_ADDRESS, parseUnits(swapAmount, 18)],
      });
    } catch (err) {
      setErrorLog(parseWeb3Error(err));
    }
  };

  const handleDeposit = async () => {
    setErrorLog('');
    try {
      writeContract({
        address: VAULT_ADDRESS,
        abi: [{ name: 'deposit', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'assets', type: 'uint256' }, { name: 'receiver', type: 'address' }], outputs: [{ type: 'uint256' }] }],
        functionName: 'deposit',
        args: [parseUnits(depositAmount, 18), address],
      });
    } catch (err) {
      setErrorLog(parseWeb3Error(err));
    }
  };

  const handleVote = async (proposalId: string, support: number) => {
    setErrorLog('');
    try {
      writeContract({
        address: GOVERNOR_ADDRESS,
        abi: [{ name: 'castVote', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'proposalId', type: 'uint256' }, { name: 'support', type: 'uint8' }], outputs: [{ type: 'uint256' }] }],
        functionName: 'castVote',
        args: [BigInt(proposalId), support],
      });
    } catch (err) {
      setErrorLog(parseWeb3Error(err));
    }
  };

  const proposalStates = ['Pending', 'Active', 'Canceled', 'Defeated', 'Succeeded', 'Queued', 'Expired', 'Executed'];

  const styles = {
    container: {
      backgroundColor: '#0b1329',
      color: '#f8fafc',
      fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      padding: '40px',
      minHeight: '100vh',
    },
    header: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      borderBottom: '1px solid #1e293b',
      paddingBottom: '20px',
      marginBottom: '32px',
    },
    title: {
      fontSize: '28px',
      fontWeight: '800',
      letterSpacing: '-0.5px',
      margin: '0',
    },
    networkAlert: {
      backgroundColor: 'rgba(239, 68, 68, 0.15)',
      border: '1px solid #ef4444',
      padding: '16px 20px',
      borderRadius: '12px',
      marginBottom: '24px',
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
    },
    btnDanger: {
      backgroundColor: '#dc2626',
      color: '#fff',
      border: 'none',
      padding: '10px 16px',
      borderRadius: '8px',
      fontWeight: '600',
      cursor: 'pointer',
    },
    errorAlert: {
      backgroundColor: 'rgba(245, 158, 11, 0.15)',
      border: '1px solid #f59e0b',
      padding: '16px 20px',
      borderRadius: '12px',
      marginBottom: '24px',
      fontSize: '14px',
    },
    grid: {
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
      gap: '24px',
      marginBottom: '32px',
    },
    card: {
      backgroundColor: '#1c2541',
      borderRadius: '16px',
      padding: '24px',
      border: '1px solid #334155',
      boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.3)',
    },
    cardTitle: {
      fontSize: '18px',
      fontWeight: '600',
      color: '#94a3b8',
      marginBottom: '20px',
      marginTop: '0',
      display: 'flex',
      alignItems: 'center',
      gap: '8px',
    },
    profileItem: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      marginBottom: '16px',
    },
    label: {
      color: '#64748b',
      fontSize: '14px',
    },
    valueValue: {
      fontFamily: 'monospace',
      fontSize: '18px',
      fontWeight: '700',
    },
    input: {
      width: '100%',
      padding: '12px 16px',
      borderRadius: '10px',
      backgroundColor: '#0b1329',
      border: '1px solid #475569',
      color: '#fff',
      fontSize: '15px',
      marginBottom: '20px',
      boxSizing: 'border-box' as const,
      outline: 'none',
    },
    btnSwap: {
      width: '100%',
      backgroundColor: '#10b981',
      color: '#fff',
      border: 'none',
      padding: '14px',
      borderRadius: '10px',
      fontWeight: '700',
      fontSize: '15px',
      cursor: 'pointer',
    },
    btnVault: {
      width: '100%',
      backgroundColor: '#06b6d4',
      color: '#fff',
      border: 'none',
      padding: '14px',
      borderRadius: '10px',
      fontWeight: '700',
      fontSize: '15px',
      cursor: 'pointer',
    },
    daoSection: {
      backgroundColor: '#1c2541',
      borderRadius: '16px',
      padding: '28px',
      border: '1px solid #334155',
    },
    daoTitle: {
      fontSize: '22px',
      fontWeight: '700',
      marginBottom: '24px',
      marginTop: '0',
    },
    proposalCard: {
      backgroundColor: '#0b1329',
      borderRadius: '12px',
      padding: '20px',
      border: '1px solid #334155',
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
    },
    badge: {
      backgroundColor: 'rgba(59, 130, 246, 0.15)',
      color: '#60a5fa',
      border: '1px solid rgba(59, 130, 246, 0.3)',
      padding: '4px 12px',
      borderRadius: '20px',
      fontSize: '12px',
      fontWeight: '600',
      marginRight: '12px',
    },
    proposalText: {
      fontSize: '16px',
      fontWeight: '600',
    },
    proposalSub: {
      fontSize: '13px',
      color: '#64748b',
      marginTop: '6px',
      marginBottom: '0',
    },
    btnGroup: {
      display: 'flex',
      gap: '10px',
    },
    btnVoteFor: {
      backgroundColor: '#059669',
      color: '#fff',
      border: 'none',
      padding: '10px 20px',
      borderRadius: '8px',
      fontWeight: '600',
      cursor: 'pointer',
    },
    btnVoteAgainst: {
      backgroundColor: '#dc2626',
      color: '#fff',
      border: 'none',
      padding: '10px 20px',
      borderRadius: '8px',
      fontWeight: '600',
      cursor: 'pointer',
    },
  };

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1 style={styles.title}>🏢 RWA Tokenization Protocol</h1>
        <ConnectButton />
      </header>

      {isConnected && chainId !== 421614 && (
        <div style={styles.networkAlert}>
          <span>⚠️ Вы подключены к неверной сети. Для работы необходим Arbitrum Sepolia.</span>
          <button onClick={() => switchChain({ chainId: 421614 })} style={styles.btnDanger}>
            Переключить сеть
          </button>
        </div>
      )}

      {errorLog && <div style={styles.errorAlert}>{errorLog}</div>}

      <div style={styles.grid}>
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>👤 Твой профиль</h2>
          <div style={styles.profileItem}>
            <span style={styles.label}>Баланс (The Graph):</span>
            <span style={{ ...styles.valueValue, color: '#34d399' }}>
              {graphData?.account ? formatUnits(graphData.account.tokenBalance, 18) : '0.0'} RWA
            </span>
          </div>
          <div style={styles.profileItem}>
            <span style={styles.label}>KYC Статус:</span>
            <span style={{ fontWeight: '600', color: graphData?.account?.hasKYC ? '#34d399' : '#f87171' }}>
              {graphData?.account?.hasKYC ? '✅ Пройден' : '❌ Отсутствует'}
            </span>
          </div>
          <div style={styles.profileItem}>
            <span style={styles.label}>Сила голоса (RPC):</span>
            <span style={{ ...styles.valueValue, color: '#22d3ee' }}>
              {votingPower ? formatUnits(votingPower as bigint, 18) : '0.0'} Votes
            </span>
          </div>
        </div>

        <div style={styles.card}>
          <h2 style={styles.cardTitle}>🔄 AMM Торговый Пул (0.3% Fee)</h2>
          <input type="number" placeholder="Количество токенов..." value={swapAmount} onChange={(e) => setSwapAmount(e.target.value)} style={styles.input} />
          <button onClick={handleSwap} disabled={isTxPending || !swapAmount} style={styles.btnSwap}>
            {isTxPending ? 'Транзакция в пути...' : 'Обменять на пул ✨'}
          </button>
        </div>

        <div style={styles.card}>
          <h2 style={styles.cardTitle}>💰 ERC-4626 Yield Vault</h2>
          <input type="number" placeholder="Сумма депозита..." value={depositAmount} onChange={(e) => setDepositAmount(e.target.value)} style={styles.input} />
          <button onClick={handleDeposit} disabled={isTxPending || !depositAmount} style={styles.btnVault}>
            {isTxPending ? 'Транзакция в пути...' : 'Внести в Vault 🔒'}
          </button>
        </div>
      </div>

      <div style={styles.daoSection}>
        <h2 style={styles.daoTitle}>🏛️ Активные голосования DAO Platform</h2>
        <div style={styles.proposalCard}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center' }}>
              <span style={styles.badge}>🟢 {proposalStates[1]}</span>
              <span style={styles.proposalText}>PIP-01: Обновление AssetManager до версии V2</span>
            </div>
            <p style={styles.proposalSub}>Необходимый кворум для принятия решения: 4% от общего числа голосов.</p>
          </div>
          <div style={styles.btnGroup}>
            <button onClick={() => handleVote('1', 1)} style={styles.btnVoteFor}>За 👍</button>
            <button onClick={() => handleVote('1', 0)} style={styles.btnVoteAgainst}>Против 👎</button>
          </div>
        </div>
      </div>
    </div>
  );
}