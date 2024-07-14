// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OFT } from "@layerzerolabs/oft/OFT.sol";

contract OFTWrappedERC20 is OFT {
    IERC20 immutable baseToken;

    event Wrap(address indexed user, uint256 indexed amount);
    event Unwrap(address indexed user, uint256 indexed amount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        address _baseToken
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        baseToken = IERC20(_baseToken);
    }

    function wrap(uint256 amount) external {
        baseToken.transferFrom(msg.sender, address(this), amount);
    }

    function unwrap(uint256 amount) external {
        _burn(msg.sender, amount);
        baseToken.transfer(msg.sender, amount);
    }
}