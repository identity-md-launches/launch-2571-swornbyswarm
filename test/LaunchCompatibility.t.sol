// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwornToken} from "../src/SwornToken.sol";

/// @dev Test-only deployer; represents the contract that owns the initial supply.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (SwornToken) {
        return new SwornToken{salt: salt}();
    }

    function distribute(SwornToken token, address distributor, address pool, address remainder) external {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply / 10));
        require(token.transfer(pool, supply * 70 / 100));
        require(token.transfer(remainder, supply * 20 / 100));
    }
}

contract LaunchCompatibilityTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function test_create2MintsEverythingToFactory() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        bytes32 salt = keccak256("sworn factory deployment test");
        address expected = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(SwornToken).creationCode))
                    )
                )
            )
        );

        SwornToken token = factory.deploy(salt);
        assertEq(address(token), expected);
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_distributionClaimsAndPoolTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        SwornToken token = factory.deploy(keccak256("sworn launch flows test"));
        address distributor = makeAddr("launch distributor fixture");
        address pool = makeAddr("pool manager fixture");
        address remainder = makeAddr("remainder recipient fixture");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        factory.distribute(token, distributor, pool, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), 100_000_000 ether);
        assertEq(token.balanceOf(pool), 700_000_000 ether);
        assertEq(token.balanceOf(remainder), 200_000_000 ether);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, 100_000_000 ether));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), 100_000_000 ether);

        // Models only the token side of a buy/sell; no DEX or price calculation is mocked here.
        vm.prank(pool);
        assertTrue(token.transfer(trader, 123 ether));
        assertEq(token.balanceOf(trader), 123 ether);
        assertEq(token.balanceOf(pool), 700_000_000 ether - 123 ether);
        vm.prank(trader);
        assertTrue(token.transfer(pool, 123 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), 700_000_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
