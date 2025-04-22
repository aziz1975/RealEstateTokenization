// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * --------------------------------------------------------------------------
 *  MultiPropertyFractionalAdvanced – 100 % USDT
 * --------------------------------------------------------------------------
 *  • Fractions are sold for, and dividends are paid in, the same ERC‑20
 *    payment token (USDT on TRON, 6 decimals).
 *  • No native TRX is used anywhere.
 * ------------------------------------------------------------------------ */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MultiPropertyFractionalAdvanced is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ────────────────────────────────────────────────────────────────── */
    /*  Immutable configuration                                          */
    /* ────────────────────────────────────────────────────────────────── */

    IERC20  public immutable paymentToken;     // USDT (6 decimals)
    uint256 public immutable pricePerFraction; // micro‑USDT (6 dec.)
    uint256 public immutable maxFractions;     // whole‑unit fractions

    string  public propertyAddress;
    string  public propertyURI;

    /* ────────────────────────────────────────────────────────────────── */
    /*  Dividend accounting (all in USDT)                                */
    /* ────────────────────────────────────────────────────────────────── */

    uint256 private constant MAGNITUDE = 1e18;

    uint256 public accumDividendPerShare;          // scaled by MAGNITUDE
    mapping(address => uint256) private credit;    // withdrawals ledger
    uint256 public totalDividends;                 // lifetime USDT distributed

    /* ────────────────────────────────────────────────────────────────── */
    /*  Events                                                           */
    /* ────────────────────────────────────────────────────────────────── */

    event FractionsPurchased (address indexed buyer, uint256 fractions, uint256 usdtPaid);
    event DividendsDeposited(address indexed depositor, uint256 usdtAmount);
    event DividendsClaimed  (address indexed claimer,   uint256 usdtAmount);

    /* ────────────────────────────────────────────────────────────────── */
    /*  Constructor                                                      */
    /* ────────────────────────────────────────────────────────────────── */

    constructor(
        string  memory _name,
        string  memory _symbol,
        uint256 _maxFractions,
        uint256 _pricePerFraction,       // in micro‑USDT
        address _paymentToken,           // USDT contract address
        string  memory _propertyAddress,
        string  memory _propertyURI
    ) ERC20(_name, _symbol) {
        require(_maxFractions     > 0,             "Fractions = 0");
        require(_pricePerFraction > 0,             "Price = 0");
        require(_paymentToken     != address(0),   "Token = 0x0");

        maxFractions     = _maxFractions;
        pricePerFraction = _pricePerFraction;
        paymentToken     = IERC20(_paymentToken);

        propertyAddress  = _propertyAddress;
        propertyURI      = _propertyURI;
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  Purchase flow                                                    */
    /* ────────────────────────────────────────────────────────────────── */

    function buy(uint256 fractions) external nonReentrant {
        require(fractions > 0, "Amount = 0");
        require(totalFractionsSold() + fractions <= maxFractions, "Soldout");

        uint256 cost = fractions * pricePerFraction;

        // Pull USDT from buyer
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);

        // Mint fractional tokens (18 decimals)
        _mint(msg.sender, fractions * 10 ** decimals());

        // Initialise dividend credit
        credit[msg.sender] += (fractions * 10 ** decimals()) * accumDividendPerShare / MAGNITUDE;

        emit FractionsPurchased(msg.sender, fractions, cost);
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  Dividend handling (USDT)                                         */
    /* ────────────────────────────────────────────────────────────────── */

    /// Owner deposits rental income / sale proceeds in USDT
    function depositDividends(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Zero deposit");

        // Pull USDT from owner
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        _allocateDividends(amount);
        emit DividendsDeposited(msg.sender, amount);
    }

    function claimable(address account) public view returns (uint256) {
        uint256 gross = balanceOf(account) * accumDividendPerShare / MAGNITUDE;
        if (gross <= credit[account]) return 0;
        return gross - credit[account];
    }

    function claim() external nonReentrant {
        uint256 amount = claimable(msg.sender);
        require(amount > 0, "Nothing to claim");

        credit[msg.sender] += amount;
        paymentToken.safeTransfer(msg.sender, amount);

        emit DividendsClaimed(msg.sender, amount);
    }

    function _allocateDividends(uint256 amount) internal {
        require(totalSupply() > 0, "No supply");
        accumDividendPerShare += (amount * MAGNITUDE) / totalSupply();
        totalDividends        += amount;
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  Transfer hook                                                    */
    /* ────────────────────────────────────────────────────────────────── */

    function _afterTokenTransfer(address from, address to, uint256) internal override {
        if (from != address(0)) {
            credit[from] = balanceOf(from) * accumDividendPerShare / MAGNITUDE;
        }
        if (to != address(0)) {
            credit[to]   = balanceOf(to)   * accumDividendPerShare / MAGNITUDE;
        }
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  Owner utilities                                                  */
    /* ────────────────────────────────────────────────────────────────── */

    /// Withdraw sale proceeds that are *not* owed as dividends
    function withdrawProceeds(uint256 amount) external onlyOwner nonReentrant {
        uint256 available = paymentToken.balanceOf(address(this)) - pendingDividends();
        require(amount <= available, "Insufficient proceeds");
        paymentToken.safeTransfer(owner(), amount);
    }

    function pendingDividends() public view returns (uint256) {
        return totalSupply() * accumDividendPerShare / MAGNITUDE
             - credit[address(0)]
             - credit[address(this)];
    }

    /* ────────────────────────────────────────────────────────────────── */
    /*  Read‑only helpers                                                */
    /* ────────────────────────────────────────────────────────────────── */

    function totalFractionsSold() public view returns (uint256) {
        return totalSupply() / 10 ** decimals();
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
