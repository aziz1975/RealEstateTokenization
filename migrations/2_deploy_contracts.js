/* global artifacts, deployer */
const Token = artifacts.require('MultiPropertyFractionalAdvanced');

module.exports = async (deployer, network, accounts) => {
  // Tweak for your property
  const NAME         = 'CityCenter Condo Fraction';
  const SYMBOL       = 'CCCF';
  const MAX_SHARES   = 1_000;          // whole‑unit fractions
  const PRICE_SUN    = 50_000_000;     // 50 TRX (50 × 1e6 SUN)
  const STREET_ADDR  = '456 CityCenter Blvd, Chicago IL';
  const META_URI     = 'ipfs://QmYourJson';

  await deployer.deploy(
    Token,
    NAME,
    SYMBOL,
    MAX_SHARES,
    PRICE_SUN,
    STREET_ADDR,
    META_URI
  );
};
