// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KYCRegistry
 * @dev 지갑 주소의 KYC 인증 상태를 온체인에 기록하는 컨트랙트
 * @notice block.timestamp는 validators에 의해 15초 범위 내에서 조작 가능함 (@TODO 확인필요)
 */
contract KYCRegistry is AccessControl {
    // 역할 정의
    // KYC 관리자 역할 (인증/취소 권한)
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    // 데이터 구조
    struct KYCRecord {
        bool verified;
        uint256 expiredAt;
        uint8 tier;
    }

    mapping(address => KYCRecord) private _records;

    // 이벤트
    event Verified(address indexed user, uint8 tier, uint256 expiredAt);
    event Revoked(address indexed user);

    // 생성자
    /**
     * @param admin KYC 관리자 역할을 부여받을 주소
     */
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // 핵심 함수
    /**
     * @notice 유저 KYC 인증 등록
     * @param user     인증할 지갑 주소
     * @param tier     등급 (1 또는 2)
     * @param duration 유효 기간 (초 단위, 예: 365일 = 31_536_000)
     */
    function verify(address user, uint8 tier, uint256 duration) external onlyRole(VERIFIER_ROLE) {
        require(user != address(0), "Invalid address");
        require(tier >= 1 && tier <= 2, "Tier must be greater than or equal to 1 and less than or equal to 2");
        require(duration > 0, "Duration must be greater than 0");

        uint256 expiredAt = block.timestamp + duration;
        _records[user] = KYCRecord({
            verified: true,
            expiredAt: expiredAt,
            tier: tier
        });

        emit Verified(user, tier, expiredAt);
    }

    /**
     * @notice 유저 KYC 인증 취소
     * @param user 취소할 지갑 주소
     */
    function revoke(address user) external onlyRole(VERIFIER_ROLE) {
        require(_records[user].verified, "User is not verified");

        _records[user].verified = false;

        emit Revoked(user);
    }

    // 조회 함수
    /**
     * @notice 인증 여부 확인 (Facilitator가 결제 전에 호출)
     * @param user 확인할 지갑 주소
     * @return 인증됐고 만료되지 않았으면 true
     */
    function isVerified(address user) external view returns (bool) {
        KYCRecord memory record = _records[user];
        return record.verified && block.timestamp < record.expiredAt;
    }

    /**
     * @notice 유저 등급 확인
     * @param user 확인할 지갑 주소
     */
    function getTier(address user) external view returns (uint8) {
        KYCRecord memory record = _records[user];
        require(record.verified && block.timestamp < record.expiredAt, "User is not verified or expired");
        return record.tier;
    }

    /**
     * @notice 유저 KYC 전체 정보 조회
     * @param user 확인할 지갑 주소
     */
    function getRecord(address user) external view returns (bool verified, uint256 expiredAt, uint8 tier) {
        KYCRecord memory record = _records[user];
        require(record.verified && block.timestamp < record.expiredAt, "User is not verified or expired");
        return (record.verified, record.expiredAt, record.tier);
    }
}