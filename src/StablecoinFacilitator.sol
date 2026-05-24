// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./KYCRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StablecoinFacilitator
 * @notice EIP-2612 permit을 활용해 KYC 검증 + 수수료 분리 정산을 한번에 처리
 */
contract StablecoinFacilitator is Ownable {
    // 상태 변수
    IERC20Permit public immutable usdcPermit;  // USDC 컨트랙트
    IERC20       public immutable usdc;        // USDC 컨트랙트 (transferFrom 용)
    KYCRegistry  public immutable kycRegistry; // KYC Registry 컨트랙트
    address      public immutable feeWallet;   // 수수료 받는 지갑
    uint256      public immutable feeAmount;   // 고정 수수료 금액

    // 이벤트
    event Settled(
        address indexed payer,      // 구매자
        address indexed recipient,  // 판매자
        uint256 amount,             // 총 결제 금액
        uint256 fee                 // 수수료
    );

    // 에러 처리
    error KYCNotVerified(address user);
    error InvalidRecipient();
    error AmountTooSmall();

    // 생성자
    /**
     * @param _usdc        USDC 컨트랙트 주소
     * @param _kycRegistry KYCRegistry 컨트랙트 주소
     * @param _feeWallet   수수료 받을 지갑 주소
     * @param _feeAmount   고정 수수료 금액 (USDC 6자리, 예: 1000 = $0.001)
     */
    constructor(
        address _usdc,
        address _kycRegistry,
        address _feeWallet,
        uint256 _feeAmount
    ) Ownable(msg.sender) {
        require(_usdc        != address(0), "Invalid USDC address");
        require(_kycRegistry != address(0), "Invalid KYCRegistry address");
        require(_feeWallet   != address(0), "Invalid fee wallet address");

        usdcPermit  = IERC20Permit(_usdc);
        usdc        = IERC20(_usdc);
        kycRegistry = KYCRegistry(_kycRegistry);
        feeWallet   = _feeWallet;
        feeAmount   = _feeAmount;
    }

    // 핵심 함수
    /**
     * @notice KYC 검증 + EIP-2612 permit + 수수료 분리 정산을 한번에 처리
     *
     * @param owner      결제하는 유저 지갑 주소
     * @param recipient  판매자 지갑 주소 (돈 받는 쪽)
     * @param amount     총 결제 금액 (수수료 포함)
     * @param deadline   EIP-2612 서명 만료 시간
     * @param v          서명값 v
     * @param r          서명값 r
     * @param s          서명값 s
     */
    function settleWithFeeAndPermit(
        address owner,
        address recipient,
        uint256 amount,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        // 1. 입력값 검증
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount <= feeAmount)     revert AmountTooSmall();

        // 2. KYC 검증
        if (!kycRegistry.isVerified(owner)) revert KYCNotVerified(owner);

        // 3. EIP-2612 permit 실행
        // 유저 서명으로 이 컨트랙트에 amount만큼 approve
        usdcPermit.permit(
            owner,
            address(this), // spender = 이 컨트랙트
            amount,
            deadline,
            v, r, s
        );

        // 4. 수수료 분리 이체
        uint256 recipientAmount = amount - feeAmount;

        // 판매자한테 결제금 이체
        bool result1 = usdc.transferFrom(owner, recipient, recipientAmount);
        require(result1, "Transfer to recipient failed");

        // 수수료 지갑에 수수료 이체
        bool result2 = usdc.transferFrom(owner, feeWallet, feeAmount);
        require(result2, "Transfer to fee wallet failed");

        emit Settled(owner, recipient, amount, feeAmount);
    }
}