require('dotenv').config();
const MultiProperty = artifacts.require('MultiPropertyFractionalAdvanced');

module.exports = async function (deployer, network, accounts) {
  /* ------------------------------------------------------------- *
   *  1. Pull required values from the environment                 *
   * ------------------------------------------------------------- */
  const USDT_ADDRESS       = process.env.USDT_ADDRESS;     // already deployed mock‑USDT

  if (!USDT_ADDRESS) {
    throw new Error(
      '🛑  USDT_ADDRESS missing.  Add it to .env before migrating.'
    );
  }

  /* ------------------------------------------------------------- *
   *  2. Define property‑specific parameters                       *
   * ------------------------------------------------------------- */
  const NAME               = 'Lakeview Fractional';
  const SYMBOL             = 'LVF';
  const MAX_FRACTIONS      = 1_000;                // whole‑unit fractions
  const PRICE_PER_FRACTION = 100 * 1e6;            // 100 USDT (6‑decimals → 100 × 1 000 000)
  const PROPERTY_ADDR      = '123 Lakeview Dr, Austin TX';
  const PROPERTY_URI       = 'ipfs://Qm…';         // replace with your metadata CID

  /* ------------------------------------------------------------- *
   *  3. Deploy                                                    *
   * ------------------------------------------------------------- */
  await deployer.deploy(
    MultiProperty,
    NAME,
    SYMBOL,
    MAX_FRACTIONS,
    PRICE_PER_FRACTION.toString(),
    USDT_ADDRESS,
    PROPERTY_ADDR,
    PROPERTY_URI
  );

  const instance = await MultiProperty.deployed();
  console.log('\n✅  MultiPropertyFractionalAdvanced deployed at:', instance.address);
};
