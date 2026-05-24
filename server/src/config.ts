import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";
import * as dotenv from "dotenv";
dotenv.config();

// Facilitator 지갑 (가스비 내는 주체)
export const account = privateKeyToAccount(process.env.FACILITATOR_PRIVATE_KEY as `0x${string}`);

// 블록체인 읽기용 클라이언트
export const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(process.env.RPC_URL),
});

// 블록체인 쓰기용 클라이언트
export const walletClient = createWalletClient({
  account,
  chain: baseSepolia,
  transport: http(process.env.RPC_URL),
});

// 컨트랙트 주소 (배포 후 채울 것)
export const CONTRACTS = {
  KYC_REGISTRY: process.env.KYC_REGISTRY_ADDRESS as `0x${string}`,
  STABLECOIN_FACILITATOR: process.env.FACILITATOR_ADDRESS as `0x${string}`,
  USDC: process.env.USDC_ADDRESS as `0x${string}`,
};
