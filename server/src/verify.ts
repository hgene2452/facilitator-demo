import { Request, Response } from "express";
import { publicClient, CONTRACTS } from "./config";
import { verifyTypedData } from "viem";

// KYCRegistry ABI
const KYC_REGISTRY_ABI = [
  {
    name: "isVerified",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

// USDC ABI (잔액 조회용)
const USDC_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "nonces",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "DOMAIN_SEPARATOR",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bytes32" }],
  },
] as const;

export async function verifyHandler(req: Request, res: Response) {
  try {
    const { payload, requirements } = req.body;

    // 1. 기본 입력값 체크
    if (!payload || !requirements) {
      return res.status(400).json({
        isValid: false,
        invalidReason: "Missing payload or requirements",
      });
    }

    // 2. payer 주소 + 서명 파라미터 추출
    const owner: `0x${string}` = payload.payload?.authorization?.from;
    const amount: bigint = BigInt(requirements.amount);
    const deadline: bigint = BigInt(payload.payload?.authorization?.validBefore);
    const { v, r, s } = payload.payload?.signature ?? {};

    if (!owner || !deadline || !v || !r || !s) {
      return res.status(400).json({
        isValid: false,
        invalidReason: "Cannot extract payment parameters",
      });
    }

    // 3. 만료일 확인
    const now = BigInt(Math.floor(Date.now() / 1000));
    if (deadline < now) {
      return res.json({
        isValid: false,
        invalidReason: "Signature expired",
        payer: owner,
      });
    }

    // 4. 잔액 확인
    const balance = await publicClient.readContract({
      address: CONTRACTS.USDC,
      abi: USDC_ABI,
      functionName: "balanceOf",
      args: [owner],
    });

    if (balance < amount) {
      return res.json({
        isValid: false,
        invalidReason: "Insufficient USDC balance",
        payer: owner,
      });
    }

    // 5. 서명 유효성 검증
    const domainSeparator = await publicClient.readContract({
      address: CONTRACTS.USDC,
      abi: USDC_ABI,
      functionName: "DOMAIN_SEPARATOR",
      args: [],
    });

    const nonce = await publicClient.readContract({
      address: CONTRACTS.USDC,
      abi: USDC_ABI,
      functionName: "nonces",
      args: [owner],
    });

    // EIP-2612 서명 검증
    const PERMIT_TYPEHASH =
      "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)";

    const isValidSignature = await verifyTypedData({
      address: owner,
      domain: {
        name: "USD Coin",
        version: "2",
        chainId: 84532, // Base Sepolia
        verifyingContract: CONTRACTS.USDC,
      },
      types: {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      },
      primaryType: "Permit",
      message: {
        owner,
        spender: CONTRACTS.STABLECOIN_FACILITATOR,
        value: amount,
        nonce,
        deadline,
      },
      signature: payload.payload.signature,
    });

    if (!isValidSignature) {
      return res.json({
        isValid: false,
        invalidReason: "Invalid signature",
        payer: owner,
      });
    }

    // 6. KYC 검증
    const isKYCVerified = await publicClient.readContract({
      address: CONTRACTS.KYC_REGISTRY,
      abi: KYC_REGISTRY_ABI,
      functionName: "isVerified",
      args: [owner],
    });

    if (!isKYCVerified) {
      return res.json({
        isValid: false,
        invalidReason: "KYC_NOT_VERIFIED",
        payer: owner,
      });
    }

    // 7. 모든 검증 통과
    return res.json({
      isValid: true,
      payer: owner,
    });
  } catch (error) {
    console.error("Verify error:", error);
    return res.status(500).json({
      isValid: false,
      invalidReason: "Internal server error",
    });
  }
}
