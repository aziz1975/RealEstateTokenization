// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title 100% USDT fractional ownership with buy, sell & dividends
contract MultiPropertyFractionalAdvanced is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20  public immutable paymentToken;     // USDT (6 decimals)
    uint256 public immutable pricePerFraction; // micro-USDT per fraction
    uint256 public immutable maxFractions;     // cap on whole fractions

    string public propertyAddress;
    string public propertyURI;

    uint256 private constant MAGNITUDE = 1e18;
    uint256 public accumDividendPerShare;      // scaled by MAGNITUDE
    mapping(address => uint256) private credit; // holder ⇒ already-credited amount
    uint256 public totalDividends;             // total USDT ever deposited
    uint256 public totalClaimed;               // total USDT ever claimed

    /* ────────────────────────────────────────────────────────────────── */
    /*  Events                                                           */
    /* ────────────────────────────────────────────────────────────────── */
    event FractionsPurchased(address indexed buyer, uint256 fractions, uint256 usdtPaid);
    event DividendsDeposited(address indexed depositor, uint256 usdtAmount);
    event DividendsClaimed(address indexed claimer, uint256 usdtAmount);
    event FractionsSold(address indexed seller, uint256 fractions, uint256 usdtReturned);

    /* ────────────────────────────────────────────────────────────────── */
    /*  Constructor                                                      */
    /* ────────────────────────────────────────────────────────────────── */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxFractions,
        uint256 _pricePerFraction,
        address _paymentToken,
        string memory _propertyAddress,
        string memory _propertyURI
    ) ERC20(_name, _symbol) {
        require(_maxFractions > 0, "Fractions = 0");
        require(_pricePerFraction > 0, "Price = 0");
        require(_paymentToken != address(0), "Token = 0x0");

        maxFractions     = _maxFractions;
        pricePerFraction = _pricePerFraction;
        paymentToken     = IERC20(_paymentToken);

        propertyAddress = _propertyAddress;
        propertyURI     = _propertyURI;
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  1. Buy fractions                                                 */
    /* ────────────────────────────────────────────────────────────────── */
    function buy(uint256 fractions) external nonReentrant {
        require(fractions > 0, "Amount = 0");
        require(totalFractionsSold() + fractions <= maxFractions, "Soldout");

        uint256 cost = fractions * pricePerFraction;
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);

        uint256 minted = fractions * 10**decimals();
        _mint(msg.sender, minted);

        // Set credit so new buyer isn't owed past dividends
        credit[msg.sender] = balanceOf(msg.sender) * accumDividendPerShare / MAGNITUDE;

        emit FractionsPurchased(msg.sender, fractions, cost);
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  2. Sell fractions                                                */
    /* ────────────────────────────────────────────────────────────────── */
    function sell(uint256 fractions) external nonReentrant {
        require(fractions > 0, "Amount = 0");
        uint256 weiFractions = fractions * 10**decimals();
        require(balanceOf(msg.sender) >= weiFractions, "Insufficient balance");

        uint256 usdtAmount = fractions * pricePerFraction;
        uint256 available = paymentToken.balanceOf(address(this)) - pendingDividends();
        require(usdtAmount <= available, "Insufficient proceeds");

        _burn(msg.sender, weiFractions);

        // Update credit for the seller after burn
        credit[msg.sender] = balanceOf(msg.sender) * accumDividendPerShare / MAGNITUDE;

        paymentToken.safeTransfer(msg.sender, usdtAmount);
        emit FractionsSold(msg.sender, fractions, usdtAmount);
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  3. Deposit & claim dividends                                     */
    /* ────────────────────────────────────────────────────────────────── */
    function depositDividends(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Zero deposit");
        // Pull USDT in
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        accumDividendPerShare += (amount * MAGNITUDE) / totalSupply();
        totalDividends        += amount;

        emit DividendsDeposited(msg.sender, amount);
    }

    function claimable(address account) public view returns (uint256) {
        // total owed across all past deposits, minus what was already credited
        uint256 gross = balanceOf(account) * accumDividendPerShare / MAGNITUDE;
        return gross <= credit[account] ? 0 : gross - credit[account];
    }

    function claim() external nonReentrant {
        uint256 amount = claimable(msg.sender);
        require(amount > 0, "Nothing to claim");

        // After reading claimable, set credit to the new "gross"
        credit[msg.sender]   = balanceOf(msg.sender) * accumDividendPerShare / MAGNITUDE;
        totalClaimed        += amount;

        paymentToken.safeTransfer(msg.sender, amount);
        emit DividendsClaimed(msg.sender, amount);
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  4. Hooks & owner utilities                                       */
    /* ────────────────────────────────────────────────────────────────── */
    function _afterTokenTransfer(address from, address to, uint256) internal override {
        // Sync credits for both parties on transfers, mints, and burns
        if (from != address(0)) {
            credit[from] = balanceOf(from) * accumDividendPerShare / MAGNITUDE;
        }
        if (to != address(0)) {
            credit[to]   = balanceOf(to) * accumDividendPerShare / MAGNITUDE;
        }
    }

    function withdrawProceeds(uint256 amount) external onlyOwner nonReentrant {
        uint256 available = paymentToken.balanceOf(address(this)) - pendingDividends();
        require(amount <= available, "Insufficient proceeds");
        paymentToken.safeTransfer(owner(), amount);
    }

    /// Now this is totalDividends minus what’s already been claimed
    function pendingDividends() public view returns (uint256) {
        return totalDividends - totalClaimed;
    }

    /* ──────────────────── Read-only helpers ────────────────────────── */
    function totalFractionsSold() public view returns (uint256) {
        return totalSupply() / 10**decimals();
    }
    function unsoldFractions() external view returns (uint256) {
        return maxFractions - totalFractionsSold();
    }
    function getPrice() external view returns (uint256) {
        return pricePerFraction;
    }
    function getPaymentToken() external view returns (address) {
        return address(paymentToken);
    }
    function getPropertyInfo() external view returns (string memory, string memory) {
        return (propertyAddress, propertyURI);
    }
}
