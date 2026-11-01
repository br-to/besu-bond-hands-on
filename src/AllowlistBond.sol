// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract AllowlistBond {
    string public name = "Toy Corporate Bond 2027";
    string public symbol = "TCB27";
    uint8 public constant decimals = 0;
    uint256 public totalSupply;
    uint256 public immutable faceValuePerUnit;
    uint256 public immutable maturity;
    address public immutable issuer;

    mapping(address => uint256) public balanceOf;
    mapping(address => bool) public isAllowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event AllowlistUpdated(address indexed account, bool allowed);

    error NotIssuer();
    error NotAllowed(address account);
    error InsufficientBalance();

    constructor(uint256 _faceValuePerUnit, uint256 _maturity) {
        issuer = msg.sender;
        faceValuePerUnit = _faceValuePerUnit;
        maturity = _maturity;
        isAllowed[msg.sender] = true;
    }

    modifier onlyIssuer() {
        if (msg.sender != issuer) revert NotIssuer();
        _;
    }

    function setAllowed(address account, bool allowed) external onlyIssuer {
        isAllowed[account] = allowed;
        emit AllowlistUpdated(account, allowed);
    }

    function issue(address to, uint256 units) external onlyIssuer {
        if (!isAllowed[to]) revert NotAllowed(to);
        totalSupply += units;
        balanceOf[to] += units;
        emit Transfer(address(0), to, units);
    }

    function transfer(address to, uint256 units) external returns (bool) {
        if (!isAllowed[msg.sender]) revert NotAllowed(msg.sender);
        if (!isAllowed[to]) revert NotAllowed(to);
        if (balanceOf[msg.sender] < units) revert InsufficientBalance();
        balanceOf[msg.sender] -= units;
        balanceOf[to] += units;
        emit Transfer(msg.sender, to, units);
        return true;
    }
}
