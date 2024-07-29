// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

contract BasicToken {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function burn(address from, uint256 amount) external {
        totalSupply -= amount;
        balanceOf[from] -= amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract LongToken is BasicToken {}

contract ShortToken is BasicToken {}

contract TokenIssuer {
    address public immutable underlying;
    address public immutable cash;
    address public immutable longToken;
    address public immutable shortToken;

    uint256 public maturity;
    uint256 public volatility;
    uint256 public strike;

    constructor(address underlying_, address cash_) {
        underlying = underlying_;
        cash = cash_;
        longToken = address(new LongToken());
        shortToken = address(new ShortToken());
    }

    function start(uint256 maturity_, uint256 volatility_, uint256 strike_) external {
        maturity = maturity_;
        volatility = volatility_;
        strike = strike_;
    }

    receive() external payable {}

    /// @dev Mint both long / short tokens given `amountUnderlying` of underlying.
    function mintBoth(uint256 amountUnderlying, address to) external {
        LongToken(longToken).mint(to, amountUnderlying);
        ShortToken(shortToken).mint(to, amountUnderlying);

        uint256 underlyingBalance = BasicToken(underlying).balanceOf(address(this));
        BasicToken(underlying).transferFrom(msg.sender, address(this), amountUnderlying);
        require(
            BasicToken(underlying).balanceOf(address(this)) == underlyingBalance + amountUnderlying,
            "TokenIssuer: mintBoth failed to recieve enough underlying tokens"
        );
    }

    /// @dev Burn both long / short tokens given `amountUnderlying` of underlying.
    function burnBoth(uint256 amountUnderlying, address to) external {
        LongToken(longToken).burn(to, amountUnderlying);
        ShortToken(shortToken).burn(to, amountUnderlying);

        uint256 underlyingBalance = BasicToken(underlying).balanceOf(address(this));
        BasicToken(underlying).transfer(to, amountUnderlying);
        require(
            BasicToken(underlying).balanceOf(address(this)) == underlyingBalance - amountUnderlying,
            "TokenIssuer: burnBoth failed to send enough underlying tokens"
        );
    }

    function exerciseCashForUnderlying(uint256 amountCash, address to) external {
        require(block.timestamp > maturity, "TokenIssuer: maturity not reached");

        // Pull in cash to receive amountCash / strike amount of underlying.
        uint256 cashBalance = BasicToken(cash).balanceOf(address(this));
        BasicToken(cash).transferFrom(msg.sender, address(this), amountCash);
        require(
            BasicToken(cash).balanceOf(address(this)) == cashBalance + amountCash,
            "TokenIssuer: exerciseCashForUnderlying failed to recieve enough cash tokens"
        );

        uint256 underlyingAmount = amountCash * 1e18 / strike;
        BasicToken(underlying).transfer(to, underlyingAmount);
    }

    function redeemShortForUnderlying(uint256 amountShort, address to) external {
        require(block.timestamp > maturity, "TokenIssuer: maturity not reached");

        // Burn short tokens to receive equivalent amount of underlying.
        ShortToken(shortToken).burn(msg.sender, amountShort);

        uint256 underlyingBalance = BasicToken(underlying).balanceOf(address(this));
        BasicToken(underlying).transfer(to, amountShort);
        require(
            BasicToken(underlying).balanceOf(address(this)) == underlyingBalance - amountShort,
            "TokenIssuer: redeemShortForUnderlying failed to send enough underlying tokens"
        );
    }
}
