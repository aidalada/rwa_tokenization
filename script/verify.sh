#!/bin/bash

# Подгружаем переменные окружения из .env
if [ -f .env ]; then
    export $(cat .env | grep -v '#' | xargs)
else
    echo "❌ Error: .env file not found!"
    exit 1
fi

# Проверка обязательных глобальных переменных
if [ -z "$RPC_URL" ] || [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "❌ Error: RPC_URL or ETHERSCAN_API_KEY is not defined in .env"
    exit 1
fi

echo "🚀 Starting post-deployment verification on network..."

# 1. Верификация токена RWA
if [ ! -z "$DEPLOYED_RWA_TOKEN" ]; then
    echo "📝 Verifying RWAToken at $DEPLOYED_RWA_TOKEN..."
    forge verify-contract $DEPLOYED_RWA_TOKEN src/RWAToken.sol:RWAToken \
        --rpc-url $RPC_URL \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --watch
fi

# 2. Верификация KYC Паспорта
if [ ! -z "$DEPLOYED_KYC_PASSPORT" ]; then
    echo "📝 Verifying KYCPassport at $DEPLOYED_KYC_PASSPORT..."
    forge verify-contract $DEPLOYED_KYC_PASSPORT src/KYCPassport.sol:KYCPassport \
        --rpc-url $RPC_URL \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --constructor-args $(cast abi-encode "constructor(address)" "$INITIAL_OWNER") \
        --watch
fi

# 3. Верификация Governor DAO
if [ ! -z "$DEPLOYED_GOVERNOR" ]; then
    echo "📝 Verifying RWAGovernor at $DEPLOYED_GOVERNOR..."
    # Передаем параметры конструктора для точной сверки хеша байткода
    forge verify-contract $DEPLOYED_GOVERNOR src/RWAGovernor.sol:RWAGovernor \
        --rpc-url $RPC_URL \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --constructor-args $(cast abi-encode "constructor(address,address,uint48,uint32,uint256)" "$DEPLOYED_RWA_TOKEN" "$DEPLOYED_TIMELOCK" "$GOVERNOR_VOTING_DELAY" "$GOVERNOR_VOTING_PERIOD" "$GOVERNOR_THRESHOLD") \
        --watch
fi

echo "✅ Verification process complete!"