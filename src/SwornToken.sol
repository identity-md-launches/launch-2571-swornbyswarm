// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title swornbyswarm (SWORN)
/// @notice Fixed-supply ERC-20. All tokens are minted once to the deploying address.
/// @dev The launch factory receives the supply when it deploys this contract.
/// There are no administrative roles, transfer fees, or external mint/burn functions.
contract SwornToken is ERC20 {
    /// @notice One billion SWORN, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("swornbyswarm", "SWORN") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
