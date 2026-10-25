// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwornToken} from "src/SwornToken.sol";

/// @dev Closed actor set. Expected balances come from cumulative successful inflows/outflows,
/// never from balanceOf; allowance expectations come from approvals and authorized spending.
/// The deployer is actor 0, so it participates in the same authorization checks as other holders.
contract SwornLedgerHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    SwornToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = address(this);
        actors[1] = makeAddr("ledger holder 1");
        actors[2] = makeAddr("ledger holder 2");
        actors[3] = makeAddr("ledger holder 3");
        token = new SwornToken();
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        // Seed every actor with real constructor-minted tokens, without balance/storage cheatcodes.
        for (uint256 i = 1; i < actors.length; ++i) {
            _transfer(actors[0], actors[i], SUPPLY / 4);
        }
        // Give delegated transfers useful initial state; subsequent approvals may replace/revoke it.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % actors.length], i == 0 ? type(uint256).max : SUPPLY / 8);
        }
    }

    function expectedBalance(address account) public view returns (uint256) {
        uint256 initial = account == actors[0] ? SUPPLY : 0;
        return initial + received[account] - sent[account];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, uint8 mode) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), _amount(amountSeed, expectedBalance(from), mode));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 amount;
        uint8 choice = mode % 5;
        if (choice == 1) amount = type(uint256).max;
        else if (choice == 2) amount = type(uint256).max - 1;
        else if (choice == 3) amount = bound(amountSeed, 0, SUPPLY);
        else if (choice == 4) amount = amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed, uint8 mode)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 balance = expectedBalance(from);
        uint256 amount = _amount(amountSeed, allowed < balance ? allowed : balance, mode);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount), "valid delegated transfer failed");
        _recordMovement(from, to, amount);
        if (allowed != type(uint256).max) expectedAllowance[from][spender] = allowed - amount;
    }

    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectTransferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        // Infinite allowance has no larger uint256. Downgrade it explicitly before this attempt.
        if (allowed == type(uint256).max) {
            allowed -= 1;
            _approve(owner, spender, allowed);
        }
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), allowed + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    function rejectTransferFromOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        // Reach the balance failure after allowance spending, including both finite and unlimited approvals.
        if (expectedAllowance[owner][spender] < amount) _approve(owner, spender, amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint8 choice = operation % 3;
        if (choice == 0) {
            uint256 amount = bound(amountSeed, 0, expectedBalance(owner));
            _reject(
                owner,
                abi.encodeCall(token.transfer, (address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else if (choice == 1) {
            _reject(
                owner,
                abi.encodeCall(token.approve, (address(0), amountSeed)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
            );
        } else {
            uint256 balance = expectedBalance(owner);
            uint256 allowed = expectedAllowance[owner][spender];
            uint256 amount = bound(amountSeed, 0, allowed < balance ? allowed : balance);
            _reject(
                spender,
                abi.encodeCall(token.transferFrom, (owner, address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        }
    }

    function rejectPrivilegedCall(uint256 callerSeed, uint256 holderSeed, uint256 amount, uint8 operation) external {
        address holder = _actor(holderSeed);
        bytes memory data;
        uint8 choice = operation % 8;
        if (choice == 0) data = abi.encodeWithSignature("mint(address,uint256)", holder, amount);
        else if (choice == 1) data = abi.encodeWithSignature("burn(uint256)", amount);
        else if (choice == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amount);
        else if (choice == 3) data = abi.encodeWithSignature("pause()");
        else if (choice == 4) data = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        else if (choice == 5) data = abi.encodeWithSignature("freeze(address)", holder);
        else if (choice == 6) data = abi.encodeWithSignature("seize(address)", holder);
        else data = abi.encodeWithSignature("initialize(address)", holder);
        _reject(_actor(callerSeed), data, bytes(""));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Deliberately hit zero, one base unit, and the entire available balance/allowance.
    function _amount(uint256 seed, uint256 maximum, uint8 mode) internal pure returns (uint256) {
        uint8 choice = mode % 4;
        if (choice == 0 || maximum == 0) return 0;
        if (choice == 1) return 1;
        if (choice == 2) return maximum;
        return bound(seed, 0, maximum);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer failed");
        _recordMovement(from, to, amount);
    }

    function _recordMovement(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval failed");
        expectedAllowance[owner][spender] = amount;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(reason, expectedError, "unexpected failure reason");
        // No ledger update: the invariant checks all balances and allowances stayed unchanged.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SwornTokenLedgerInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SwornLedgerHandler internal handler;
    SwornToken internal token;

    function setUp() public {
        handler = new SwornLedgerHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = SwornLedgerHandler.transfer.selector;
        selectors[1] = SwornLedgerHandler.approve.selector;
        selectors[2] = SwornLedgerHandler.transferFrom.selector;
        selectors[3] = SwornLedgerHandler.rejectTransferOverBalance.selector;
        selectors[4] = SwornLedgerHandler.rejectTransferFromOverAllowance.selector;
        selectors[5] = SwornLedgerHandler.rejectTransferFromOverBalance.selector;
        selectors[6] = SwornLedgerHandler.rejectZeroAddress.selector;
        selectors[7] = SwornLedgerHandler.rejectPrivilegedCall.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyBalancesAllowancesAndMetadataMatchLedger() public view {
        uint256 held;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            uint256 actual = token.balanceOf(owner);
            assertEq(actual, handler.expectedBalance(owner), "holder balance differs from net flows");
            held += actual;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance differs from approvals minus authorized spending"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
        }
        assertEq(held, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "swornbyswarm");
        assertEq(token.symbol(), "SWORN");
        assertEq(token.decimals(), 18);
    }

    /// @dev Every sequence must leave holders able to move their complete balances. Each hop is
    /// checked, including intermediate recipients, and ultimately actor 0 holds the full supply.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            handler.transfer(i, (i + 1) % 4, 0, 2);
            invariant_supplyBalancesAllowancesAndMetadataMatchLedger();
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
    }

    /// @dev Pins a nonzero delegated spend, self-transfer, rejection, infinite-approval downgrade,
    /// and revocation so coverage of those transitions does not depend on random selection.
    function test_ledgerTracksSpendingFailuresAndRevocation() public {
        handler.approve(0, 1, 20, 4);
        handler.transferFrom(1, 0, 2, 7, 3);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 13);
        invariant_supplyBalancesAllowancesAndMetadataMatchLedger();

        handler.transferFrom(1, 0, 0, 0, 2);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 0);
        invariant_supplyBalancesAllowancesAndMetadataMatchLedger();

        handler.rejectTransferFromOverAllowance(0, 1, 2);
        handler.rejectTransferFromOverBalance(0, 1, 2, type(uint256).max);
        handler.rejectTransferOverBalance(0, 0, type(uint256).max);
        invariant_supplyBalancesAllowancesAndMetadataMatchLedger();

        handler.approve(0, 1, 0, 1);
        handler.transferFrom(1, 0, 2, 1, 1);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max);
        handler.rejectTransferFromOverAllowance(0, 1, 2);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max - 1);
        invariant_supplyBalancesAllowancesAndMetadataMatchLedger();

        handler.rejectZeroAddress(0, 1, 1, 0);
        handler.rejectZeroAddress(0, 1, 1, 1);
        handler.rejectZeroAddress(0, 1, 1, 2);
        handler.approve(0, 1, 0, 0);
        handler.rejectTransferFromOverAllowance(0, 1, 2);
        for (uint8 i; i < 8; ++i) {
            handler.rejectPrivilegedCall(0, 2, 1, i);
        }
        invariant_supplyBalancesAllowancesAndMetadataMatchLedger();
        afterInvariant();
    }
}
