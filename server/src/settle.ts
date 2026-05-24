import { Request, Response } from "express";
import { walletClient, publicClient, CONTRACTS } from "./config";

// StablecoinFacilitator ABI
const FACILITATOR_ABI = [
  {
    name: "settleWithFeeAndPermit",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "owner", type: "address" },
      { name: "recipient", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "deadline", type: "uint256" },
      { name: "v", type: "uint8" },
      { name: "r", type: "bytes32" },
      { name: "s", type: "bytes32" },
    ],
    outputs: [],
  },
] as const;

export async function settleHandler(req: Request, res: Response) {
  try {
    const { payload, requirements } = req.body;

    if (!payload || !requirements) {
      return res.status(400).json({
        success: false,
        errorReason: "Missing payload or requirements",
      });
    }

    // 파라미터 추출
    const owner: `0x${string}` = payload.payload.authorization.from;
    const recipient: `0x${string}` = requirements.payTo;
    const amount: bigint = BigInt(requirements.amount);
    const deadline: bigint = BigInt(payload.payload.authorization.validBefore);
    const { v, r, s } = payload.payload.signature;

    // 우리 컨트랙트 호출 ← 핵심
    const txHash = await walletClient.writeContract({
      address: CONTRACTS.STABLECOIN_FACILITATOR,
      abi: FACILITATOR_ABI,
      functionName: "settleWithFeeAndPermit",
      args: [owner, recipient, amount, deadline, v, r, s],
    });

    // 트랜잭션 확정 대기
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

    return res.json({
      success: true,
      network: payload.accepted.network,
      transaction: txHash,
      payer: owner,
    });
  } catch (error) {
    console.error("Settle error:", error);
    return res.status(500).json({
      success: false,
      errorReason: "Settlement failed",
    });
  }
}
