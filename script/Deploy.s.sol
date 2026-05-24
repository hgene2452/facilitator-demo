// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KYCRegistry.sol";
import "../src/StablecoinFacilitator.sol";

contract Deploy is Script {

    // Base Sepolia USDC 주소
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function run() external {
        uint256 deployerPrivateKey = 0x093aacb27cd2016483a13849a7712db34fd7928e9e2d15d600018cdc141bcec6;
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. KYCRegistry 배포
        KYCRegistry kycRegistry = new KYCRegistry(deployer);
        console.log("KYCRegistry deployed:", address(kycRegistry));

        // 2. StablecoinFacilitator 배포
        // feeAmount = 1000 = $0.001 USDC
        StablecoinFacilitator facilitator = new StablecoinFacilitator(
            USDC,
            address(kycRegistry),
            deployer,        // feeWallet = deployer (테스트용)
            1000             // feeAmount = $0.001
        );
        console.log("StablecoinFacilitator deployed:", address(facilitator));

        // 3. deployer에게 VERIFIER_ROLE 부여
        kycRegistry.grantRole(kycRegistry.VERIFIER_ROLE(), deployer);
        console.log("VERIFIER_ROLE granted to:", deployer);

        vm.stopBroadcast();

        // 4. .env에 넣을 주소 출력
        console.log("KYC_REGISTRY_ADDRESS=%s",    address(kycRegistry));
        console.log("FACILITATOR_ADDRESS=%s",     address(facilitator));
        console.log("USDC_ADDRESS=%s",            USDC);
    }
}