// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwornToken} from "src/SwornToken.sol";

/// @dev Complements the original unit suite with allowance boundaries and failure atomicity.
/// forge-config: default.fuzz.runs = 1000
contract SwornTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    SwornToken internal token;
    address internal holder;
    address internal recipient;
    address internal spender;
    address internal otherSpender;

    function setUp() public {
        token = new SwornToken();
        holder = makeAddr("adversarial holder");
        recipient = makeAddr("adversarial recipient");
        spender = makeAddr("adversarial spender");
        otherSpender = makeAddr("adversarial other spender");
    }

    function test_oneBaseUnitCanBeSpentAndReturned() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(holder, spender), 0);

        vm.prank(recipient);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumFiniteAllowanceIsDecrementedOnEverySpend() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedApprovalCanBeDowngradedAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), holder, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(holder), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_maximumTransferCannotOverflowOrCreateTokens() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(holder, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDelegatedTransferStillRequiresBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), holder, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_holderUsingTransferFromNeedsItsOwnAllowance() public {
        assertTrue(token.transfer(holder, 2));
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), 2);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(holder);
        assertTrue(token.approve(holder, 1));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_spenderCanBeTheRecipientWithoutReceivingExtraAuthority() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(spender), 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), spender, 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        assertTrue(token.approve(spender, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_infiniteApprovalDoesNotAllowZeroRecipientEvenForZeroAmount() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferAboveBalanceRevertsAndRestoresAllowance() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(spender);
        token.transferFrom(holder, holder, 2);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_allowanceOnAnotherTokenDoesNotAuthorizeSpending() public {
        SwornToken secondToken = new SwornToken();
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        secondToken.transferFrom(address(this), holder, 1);
        assertEq(secondToken.balanceOf(address(this)), SUPPLY);
        assertEq(secondToken.balanceOf(holder), 0);
        assertEq(secondToken.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function testFuzz_failedDelegatedTransferRestoresFiniteAllowance(
        uint256 balance,
        uint256 requested,
        uint256 approved
    ) public {
        balance = bound(balance, 0, SUPPLY);
        requested = bound(requested, balance + 1, type(uint256).max - 1);
        approved = bound(approved, requested, type(uint256).max - 1);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        vm.prank(holder);
        assertTrue(token.approve(otherSpender, 17));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, requested);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.allowance(holder, otherSpender), 17);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientFailureRestoresAllowance(uint256 approved, uint256 requested) public {
        requested = bound(requested, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), requested);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_reapprovalReplacesRemainingAllowanceAndIsIdempotent(
        uint256 approved,
        uint256 spent,
        uint256 replacement
    ) public {
        spent = bound(spent, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, spent));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - spent);

        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(recipient), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_finiteAllowanceCanBeConsumedInChunksOnlyOnce(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY);
        first = bound(first, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, first));
        assertEq(token.allowance(address(this), spender), approved - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, approved - first));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), holder, 1);
        assertEq(token.balanceOf(holder), first);
        assertEq(token.balanceOf(recipient), approved - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - approved);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalsAreScopedToBothOwnerAndSpender(uint256 balance, uint256 approved) public {
        balance = bound(balance, 1, SUPPLY / 2);
        approved = bound(approved, 1, type(uint256).max);
        assertTrue(token.transfer(holder, balance));
        assertTrue(token.transfer(recipient, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        vm.prank(recipient);
        assertTrue(token.approve(otherSpender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(holder, otherSpender, 1);

        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.allowance(recipient, otherSpender), approved);
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.allowance(recipient, spender), 0);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), balance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferPreservesBalanceAndSpendsAllowance(
        uint256 balance,
        uint256 approved,
        uint256 amount
    ) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, approved < balance ? approved : balance);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(holder, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAndDelegatedReturnAreAnExactRoundTrip(uint256 balance, uint256 amount) public {
        balance = bound(balance, 1, SUPPLY);
        amount = bound(amount, 1, balance);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(holder), balance - amount);
        assertEq(token.balanceOf(recipient), amount);

        vm.prank(recipient);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(recipient, holder, amount));
        assertEq(token.allowance(recipient, spender), 0);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
