// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StablecoinFacilitator.sol";
import "../src/KYCRegistry.sol";

// Mock USDC (테스트용)
contract MockUSDC {
    string  public name     = "USD Coin";
    string  public symbol   = "USDC";
    uint8   public decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // EIP-2612
    mapping(address => uint256) public nonces;
    bytes32 public DOMAIN_SEPARATOR;

    bytes32 constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply    += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from]             -= amount;
        balanceOf[to]               += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // EIP-2612 permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "USDC: permit expired");

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
            ))
        ));

        address recovered = ecrecover(digest, v, r, s);
        require(recovered == owner, "USDC: invalid permit signature");

        allowance[owner][spender] = value;
    }
}

contract StablecoinFacilitatorTest is Test {

    StablecoinFacilitator public facilitator;
    KYCRegistry           public registry;
    MockUSDC              public usdc;

    // 테스트용 주소
    address admin     = makeAddr("admin");
    address verifier  = makeAddr("verifier");
    address recipient = makeAddr("recipient");
    address feeWallet = makeAddr("feeWallet");

    // 유저는 서명이 필요해서 privateKey로 생성
    uint256 userPrivateKey = 0xA11CE;
    address user           = vm.addr(0xA11CE);

    // 설정값
    uint256 constant FEE_AMOUNT  = 1_000;    // $0.001 USDC
    uint256 constant PAY_AMOUNT  = 100_000;  // $0.1  USDC
    uint256 constant DURATION    = 365 days;
    uint8   constant TIER        = 1;

    bytes32 VERIFIER_ROLE;

    // 셋업
    function setUp() public {
        // 컨트랙트 배포
        usdc      = new MockUSDC();
        registry  = new KYCRegistry(admin);
        facilitator = new StablecoinFacilitator(
            address(usdc),
            address(registry),
            feeWallet,
            FEE_AMOUNT
        );

        // VERIFIER_ROLE 저장 및 부여
        VERIFIER_ROLE = registry.VERIFIER_ROLE();
        vm.startPrank(admin);
        registry.grantRole(VERIFIER_ROLE, verifier);
        vm.stopPrank();

        // user KYC 인증
        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);

        // user에게 USDC 지급
        usdc.mint(user, PAY_AMOUNT * 10);
    }

    // 헬퍼: EIP-2612 서명 생성
    function _signPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            usdc.DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                usdc.nonces(owner),
                deadline
            ))
        ));
        (v, r, s) = vm.sign(privateKey, digest);
    }

    // 정상 정산 테스트
    function test_Settle_Success() public {
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            user,
            address(facilitator),
            PAY_AMOUNT,
            deadline,
            userPrivateKey
        );

        uint256 recipientBefore = usdc.balanceOf(recipient);
        uint256 feeBefore       = usdc.balanceOf(feeWallet);
        uint256 userBefore      = usdc.balanceOf(user);

        facilitator.settleWithFeeAndPermit(
            user, recipient, PAY_AMOUNT, deadline, v, r, s
        );

        // 수신자 잔액 확인
        assertEq(usdc.balanceOf(recipient), recipientBefore + PAY_AMOUNT - FEE_AMOUNT);
        // 수수료 지갑 잔액 확인
        assertEq(usdc.balanceOf(feeWallet), feeBefore + FEE_AMOUNT);
        // 유저 잔액 확인
        assertEq(usdc.balanceOf(user), userBefore - PAY_AMOUNT);
    }

    // KYC 실패 테스트
    function test_Settle_RevertIf_KYCNotVerified() public {
        uint256 unverifiedUserKey = 0xB0B;
        address unverifiedAddr    = vm.addr(0xB0B);

        usdc.mint(unverifiedAddr, PAY_AMOUNT);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            unverifiedAddr,
            address(facilitator),
            PAY_AMOUNT,
            deadline,
            unverifiedUserKey
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                StablecoinFacilitator.KYCNotVerified.selector,
                unverifiedAddr
            )
        );
        facilitator.settleWithFeeAndPermit(
            unverifiedAddr, recipient, PAY_AMOUNT, deadline, v, r, s
        );
    }

    // 입력값 검증 테스트
    function test_Settle_RevertIf_InvalidRecipient() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            user, address(facilitator), PAY_AMOUNT, deadline, userPrivateKey
        );

        vm.expectRevert(StablecoinFacilitator.InvalidRecipient.selector);
        facilitator.settleWithFeeAndPermit(
            user, address(0), PAY_AMOUNT, deadline, v, r, s
        );
    }

    function test_Settle_RevertIf_AmountTooSmall() public {
        uint256 deadline   = block.timestamp + 1 hours;
        uint256 tinyAmount = FEE_AMOUNT; // amount == feeAmount → 실패해야 함

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            user, address(facilitator), tinyAmount, deadline, userPrivateKey
        );

        vm.expectRevert(StablecoinFacilitator.AmountTooSmall.selector);
        facilitator.settleWithFeeAndPermit(
            user, recipient, tinyAmount, deadline, v, r, s
        );
    }

    // 만료 테스트
    function test_Settle_RevertIf_PermitExpired() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            user, address(facilitator), PAY_AMOUNT, deadline, userPrivateKey
        );

        // deadline 이후로 시간 이동
        vm.warp(deadline + 1);

        vm.expectRevert("USDC: permit expired");
        facilitator.settleWithFeeAndPermit(
            user, recipient, PAY_AMOUNT, deadline, v, r, s
        );
    }

    // 이벤트 테스트
    function test_Event_SettledEmitted() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            user, address(facilitator), PAY_AMOUNT, deadline, userPrivateKey
        );

        vm.expectEmit(true, true, false, true);
        emit StablecoinFacilitator.Settled(user, recipient, PAY_AMOUNT, FEE_AMOUNT);

        facilitator.settleWithFeeAndPermit(
            user, recipient, PAY_AMOUNT, deadline, v, r, s
        );
    }
}