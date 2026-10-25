// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwornToken} from "../src/SwornToken.sol";

/// @dev Restricts valid operations to a closed set of holders for balance conservation checks.
contract SwornTokenHandler is Test {
    SwornToken public immutable token;
    address[4] public actors;

    constructor(SwornToken token_) {
        token = token_;
        actors[0] = makeAddr("holder 0");
        actors[1] = makeAddr("holder 1");
        actors[2] = makeAddr("holder 2");
        actors[3] = makeAddr("holder 3");
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 available = token.balanceOf(from);
        uint256 allowed = token.allowance(from, spender);
        amount = bound(amount, 0, available < allowed ? available : allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
    }
}

contract SwornTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SwornToken internal token;
    SwornTokenHandler internal handler;

    function setUp() public {
        token = new SwornToken();
        handler = new SwornTokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SwornTokenHandler.transfer.selector;
        selectors[1] = SwornTokenHandler.approve.selector;
        selectors[2] = SwornTokenHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndAllBalancesAreConserved() public view {
        uint256 held;
        for (uint256 i; i < 4; ++i) {
            held += token.balanceOf(handler.actors(i));
        }
        assertEq(held, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
