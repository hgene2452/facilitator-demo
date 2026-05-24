import express from "express";
import * as dotenv from "dotenv";
import { verifyHandler } from "./verify";
import { settleHandler } from "./settle";
dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// x402 표준 엔드포인트
app.post("/verify", verifyHandler);
app.post("/settle", settleHandler);

// 지원하는 결제 방식 반환
app.get("/supported", (req, res) => {
  res.json([
    {
      x402Version: 2,
      scheme: "exact",
      network: "eip155:84532", // Base Sepolia
    },
  ]);
});

app.listen(PORT, () => {
  console.log(`Facilitator server running on port ${PORT}`);
});
