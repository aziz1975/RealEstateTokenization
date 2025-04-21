// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ----------------------------------------------------------------------------
 *  MultiPropertyFractionalAdvanced
 * ----------------------------------------------------------------------------
 *  ▸ Minimal fractional‑ownership contract for **one** real‑estate asset.
 *  ▸ Fixed supply issued on purchase, ERC‑20 compatible.
 *  ▸ Rental / income TRX is pooled and claimable by holders pro‑rata.
 *  ▸ NO governance / voting – keeps surface area small for audits.
 * ----------------------------------------------------------------------------*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MultiPropertyFractionalAdvanced is ERC20, Ownable, ReentrancyGuard {
    /* --------------------------------------------------------------------- */
    /*  Immutable configuration                                              */
    /* --------------------------------------------------------------------- */

    uint256 public immutable pricePerFractionSun;  // 1 TRX = 1e6 SUN
    uint256 public immutable maxFractions;         // whole‑unit fractions

    string  public propertyAddress;                // e.g. "123 Lakeview Dr, Austin TX"
    string  public propertyURI;                    // off‑chain/IPFS JSON

    /* --------------------------------------------------------------------- */
    /*  Dividend accounting                                                  */
    /* --------------------------------------------------------------------- */

    uint256 private constant MAGNITUDE = 1e18;     // precision helper

    uint256 public accumDividendPerShare;          // scaled by MAGNITUDE
    mapping(address => uint256) private credit;    // bookkeeping for each holder
    uint256 public totalDividends;                 // lifetime TRX distributed

    /* --------------------------------------------------------------------- */
    /*  Events                                                               */
    /* --------------------------------------------------------------------- */

    event FractionsPurchased(address indexed buyer, uint256 fractions, uint256 trxPaid);
    event DividendsDeposited(address indexed depositor, uint256 amount);
    event DividendsClaimed  (address indexed claimer,   uint256 amount);

    /* --------------------------------------------------------------------- */
    /*  Constructor                                                          */
    /* --------------------------------------------------------------------- */

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxFractions,
        uint256 _pricePerFractionSun,
        string memory _propertyAddress,
        string memory _propertyURI
    ) ERC20(_name, _symbol) {
        require(_maxFractions > 0, "Fractions = 0");
        require(_pricePerFractionSun > 0, "Price = 0");

        maxFractions        = _maxFractions;
        pricePerFractionSun = _pricePerFractionSun;
        propertyAddress     = _propertyAddress;
        propertyURI         = _propertyURI;
    }

    /* --------------------------------------------------------------------- */
    /*  Purchase flow                                                        */
    /* --------------------------------------------------------------------- */

    function buy(uint256 fractions) external payable nonReentrant {
        require(fractions > 0, "Amount = 0");
        require(totalFractionsSold() + fractions <= maxFractions, "Soldout");

        uint256 cost = fractions * pricePerFractionSun;
        require(msg.value == cost, "Wrong TRX amount");

        // Mint fractions (scaled to 18 decimals like regular ERC‑20)
        _mint(msg.sender, fractions * 10 ** decimals());

        // Initialise dividend credit so new holder isn't owed past payouts
        credit[msg.sender] += (fractions * 10 ** decimals()) * accumDividendPerShare / MAGNITUDE;

        emit FractionsPurchased(msg.sender, fractions, cost);
    }

    /* --------------------------------------------------------------------- */
    /*  Dividend handling                                                    */
    /* --------------------------------------------------------------------- */

    /**
     * External deposit by owner – rental income, sale proceeds, etc.
     */
    function depositDividends() external payable onlyOwner nonReentrant {
        _allocateDividends(msg.value);
        emit DividendsDeposited(msg.sender, msg.value);
    }

    /**
     * Anyone sending TRX directly is treated as depositing dividends.
     */
    receive() external payable {
        _allocateDividends(msg.value);
        emit DividendsDeposited(msg.sender, msg.value);
    }

    /** Compute pending payout for any account */
    function claimable(address account) public view returns (uint256) {
        uint256 gross = balanceOf(account) * accumDividendPerShare / MAGNITUDE;
        if (gross <= credit[account]) return 0;
        return gross - credit[account];
    }

    /** Withdraw caller's pending dividends */
    function claim() external nonReentrant {
        uint256 amount = claimable(msg.sender);
        require(amount > 0, "Nothing to claim");

        credit[msg.sender] += amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "TRX transfer failed");

        emit DividendsClaimed(msg.sender, amount);
    }

    /** Internal: update global & per‑share accounting */
    function _allocateDividends(uint256 amount) internal {
        require(amount > 0, "Zero deposit");
        require(totalSupply() > 0, "No supply");

        accumDividendPerShare += (amount * MAGNITUDE) / totalSupply();
        totalDividends        += amount;
    }

    /* --------------------------------------------------------------------- */
    /*  Transfer hook – keeps credits in sync                                */
    /* --------------------------------------------------------------------- */

    function _afterTokenTransfer(address from, address to, uint256) internal override {
        if (from != address(0)) {
            credit[from] = balanceOf(from) * accumDividendPerShare / MAGNITUDE;
        }
        if (to != address(0)) {
            credit[to]   = balanceOf(to) * accumDividendPerShare / MAGNITUDE;
        }
    }

    /* --------------------------------------------------------------------- */
    /*  Owner utilities                                                      */
    /* --------------------------------------------------------------------- */

    function withdrawProceeds(uint256 amountSun) external onlyOwner nonReentrant {
        uint256 available = address(this).balance - pendingDividends();
        require(amountSun <= available, "Insufficient proceeds");
        (bool ok, ) = owner().call{value: amountSun}("");
        require(ok, "Transfer failed");
    }

    function pendingDividends() public view returns (uint256) {
        return totalSupply() * accumDividendPerShare / MAGNITUDE - credit[address(0)] - credit[address(this)];
    }

    /* --------------------------------------------------------------------- */
    /*  Read‑only helpers                                                    */
    /* --------------------------------------------------------------------- */

    function totalFractionsSold() public view returns (uint256) {
        return totalSupply() / 10 ** decimals();
    }

    function unsoldFractions() external view returns (uint256) {
        return maxFractions - totalFractionsSold();
    }

    function getPriceSun() external view returns (uint256) {
        return pricePerFractionSun;
    }

    function getPropertyInfo() external view returns (string memory, string memory) {
        return (propertyAddress, propertyURI);
    }
}
