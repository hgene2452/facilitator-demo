// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KYCRegistry.sol";

/**
 * @title KYCRegistryTest
 * @notice vm.prank()       → 딱 다음 호출 1번만 적용
 * @notice vm.startPrank()  → stopPrank()까지 모든 호출 적용
 * @notice vm.expectRevert() → 다음 호출이 revert할 것으로 예상
 * @notice vm.expectEmit()   → 다음 호출이 특정 이벤트를 emit할 것으로 예상
 */
contract KYCRegistryTest is Test {
    KYCRegistry public registry;

    // 테스트용 주소들
    address admin    = makeAddr("admin");
    address verifier = makeAddr("verifier");
    address user     = makeAddr("user");
    address stranger = makeAddr("stranger"); // 아무 권한 없는 사람

    // 기본 설정값
    uint8   constant TIER     = 1;
    uint256 constant DURATION = 365 days;
    bytes32 VERIFIER_ROLE;

    // 셋업
    function setUp() public {
        // admin으로 컨트랙트 배포
        vm.prank(admin);
        registry = new KYCRegistry(admin);
        VERIFIER_ROLE = registry.VERIFIER_ROLE();

        // admin이 verifier에게 VERIFIER_ROLE 부여
        vm.startPrank(admin);
        registry.grantRole(registry.VERIFIER_ROLE(), verifier);
        vm.stopPrank();
    }

    // verify() 테스트
    function test_Verify_Success() public {
        // verifier가 user를 인증
        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);

        // 인증됐는지 확인
        assertTrue(registry.isVerified(user));
        assertEq(registry.getTier(user), TIER);
    }

    function test_Verify_RevertIf_NotVerifier() public {
        // 권한 없는 stranger가 verify() 호출 → 실패해야 함
        vm.prank(stranger);
        vm.expectRevert();
        registry.verify(user, TIER, DURATION);
    }

    function test_Verify_RevertIf_ZeroAddress() public {
        vm.prank(verifier);
        vm.expectRevert("Invalid address");
        registry.verify(address(0), TIER, DURATION);
    }

    function test_Verify_RevertIf_InvalidTier() public {
        // tier = 0 → 실패
        vm.prank(verifier);
        vm.expectRevert();
        registry.verify(user, 0, DURATION);

        // tier = 3 → 실패
        vm.prank(verifier);
        vm.expectRevert();
        registry.verify(user, 3, DURATION);
    }

    function test_Verify_RevertIf_ZeroDuration() public {
        vm.prank(verifier);
        vm.expectRevert("Duration must be greater than 0");
        registry.verify(user, TIER, 0);
    }

    // revoke() 테스트
    function test_Revoke_Success() public {
        // 먼저 인증
        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);
        assertTrue(registry.isVerified(user));

        // 인증 취소
        vm.prank(verifier);
        registry.revoke(user);

        // 취소됐는지 확인
        assertFalse(registry.isVerified(user));
    }

    function test_Revoke_RevertIf_NotVerifier() public {
        // 먼저 인증
        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);

        // 권한 없는 stranger가 revoke() 호출 → 실패
        vm.prank(stranger);
        vm.expectRevert();
        registry.revoke(user);
    }

    function test_Revoke_RevertIf_NotVerified() public {
        // 인증 안 된 유저를 revoke → 실패
        vm.prank(verifier);
        vm.expectRevert("User is not verified");
        registry.revoke(user);
    }

    // isVerified() 테스트
    function test_IsVerified_ExpiredAfterDuration() public {
        // 인증 (1년 유효)
        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);
        assertTrue(registry.isVerified(user));

        // 1년 후로 시간 이동
        vm.warp(block.timestamp + DURATION + 1);

        // 만료됐는지 확인
        assertFalse(registry.isVerified(user));
    }

    function test_IsVerified_StillValidBeforeExpiry() public {
        // 인증 (1년 유효)
        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);

        // 6개월 후 (아직 유효)
        vm.warp(block.timestamp + 180 days);

        assertTrue(registry.isVerified(user));
    }

    // getTier() 테스트
    function test_Role_AdminCanGrantVerifier() public {
        address newVerifier = makeAddr("newVerifier");

        // admin이 새 verifier 추가
        vm.startPrank(admin);
        registry.grantRole(registry.VERIFIER_ROLE(), newVerifier);
        vm.stopPrank();

        // 새 verifier가 verify() 호출 가능한지 확인
        vm.prank(newVerifier);
        registry.verify(user, TIER, DURATION);
        assertTrue(registry.isVerified(user));
    }

    function test_Role_AdminCanRevokeVerifier() public {
        // admin이 verifier 권한 제거
        vm.startPrank(admin);
        registry.revokeRole(registry.VERIFIER_ROLE(), verifier);
        vm.stopPrank();

        // 권한 제거된 verifier가 verify() 호출 → 실패
        vm.prank(verifier);
        vm.expectRevert();
        registry.verify(user, TIER, DURATION);
    }

    function test_Role_StrangerCannotGrantRole() public {
        // stranger는 DEFAULT_ADMIN_ROLE 없음을 먼저 확인
        assertFalse(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), stranger));

        // 권한 없는 stranger가 역할 부여 시도 → 실패
        vm.prank(stranger);
        vm.expectRevert();
        registry.grantRole(VERIFIER_ROLE, stranger);
    }

    // 이벤트 테스트
    function test_Event_VerifiedEmitted() public {
        uint256 expectedExpiredAt = block.timestamp + DURATION;

        vm.expectEmit(true, false, false, true);
        emit KYCRegistry.Verified(user, TIER, expectedExpiredAt);

        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);
    }

    function test_Event_RevokedEmitted() public {
        vm.prank(verifier);
        registry.verify(user, TIER, DURATION);

        vm.expectEmit(true, false, false, false);
        emit KYCRegistry.Revoked(user);

        vm.prank(verifier);
        registry.revoke(user);
    }
}