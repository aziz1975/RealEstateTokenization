// enhanced‑test.js
require('dotenv').config();
const { TronWeb } = require('tronweb');

/* -------------------------------------------------------------------------- */
/*  Environment & CLI config                                                  */
/* -------------------------------------------------------------------------- */

const FULL_NODE = process.env.FULL_NODE_DEVELOPMENT;
const OWNER_KEY = process.env.OWNER_PRIVATE_KEY;              // required
const TEST_KEY  = process.env.TEST_PRIVATE_KEY;    
const CONTRACT  = process.env.CONTRACT_ADDRESS;               // deployed token

if (!FULL_NODE || !OWNER_KEY || !CONTRACT) {
  console.error('❌  Check FULL_NODE_DEVELOPMENT, OWNER_PRIVATE_KEY and CONTRACT_ADDRESS in .env');
  process.exit(1);
}
if (!TEST_KEY) {
  console.error('❌  Provide a test private key via --pk <key> or TEST_PRIVATE_KEY in .env');
  process.exit(1);
}

/* -------------------------------------------------------------------------- */
/*  Constants                                                                 */
/* -------------------------------------------------------------------------- */

const FRACTIONS_TO_BUY = 2n;               // BigInt – whole‑unit fractions
const DIVIDEND_TRX     = 100n;             // how many TRX to deposit

/* -------------------------------------------------------------------------- */
/*  Helpers                                                                   */
/* -------------------------------------------------------------------------- */

const sun = (trx) => trx * 1_000_000n;     // TRX → SUN unit converter

/* -------------------------------------------------------------------------- */
/*  Main                                                                      */
/* -------------------------------------------------------------------------- */

(async () => {
  /* ---------- create two signers ----------------------------------------- */
  const ownerWeb = new TronWeb(FULL_NODE, FULL_NODE, FULL_NODE, OWNER_KEY);
  const testWeb  = new TronWeb(FULL_NODE, FULL_NODE, FULL_NODE, TEST_KEY);

  const ownerAddr = ownerWeb.address.fromPrivateKey(OWNER_KEY);
  const testAddr  = testWeb.address.fromPrivateKey(TEST_KEY);

  console.log('Owner address :', ownerAddr);
  console.log('Test  address :', testAddr);
  console.log('Contract      :', CONTRACT);
  console.log('RPC node      :', FULL_NODE, '\n');

  /* ---------- connect contract from each signer ------------------------- */
  const tokenAsOwner = await ownerWeb.contract().at(CONTRACT);
  const token        = await testWeb.contract().at(CONTRACT);

  console.log('Token name    :', await token.name().call(), '\n');

  /* ---------- buy fractions --------------------------------------------- */
  const unsold   = await token.unsoldFractions().call();
  const priceSun = BigInt((await token.getPriceSun().call()).toString());
  const cost     = priceSun * FRACTIONS_TO_BUY;

  console.log(`Buying ${FRACTIONS_TO_BUY} fractions for ${Number(cost)/1e6} TRX …`);
  let tx = await token.buy(Number(FRACTIONS_TO_BUY))
                      .send({ callValue: cost.toString() });
  console.log('   ➜ buy()       tx id:', tx, '\n');

  /* ---------- deposit dividends (owner only) ---------------------------- */
  const depositSun = sun(DIVIDEND_TRX);
  console.log(`Depositing ${DIVIDEND_TRX} TRX rental income as owner …`);
  tx = await tokenAsOwner.depositDividends()
                         .send({ callValue: depositSun.toString() });
  console.log('   ➜ deposit      tx id:', tx, '\n');

  /* ---------- claim dividends as test address --------------------------- */
  const pending = BigInt((await token.claimable(testAddr).call()).toString());
  console.log('Claimable for test address:', Number(pending)/1e6, 'TRX');

  if (pending > 0n) {
    tx = await token.claim().send();
    console.log('   ➜ claim()      tx id:', tx, '\n');
  } else {
    console.log('   ➜ nothing to claim\n');
  }

  /* ---------- final balances ------------------------------------------- */
  const balFrac = await token.balanceOf(testAddr).call();
  const balTrx  = await testWeb.trx.getBalance(testAddr);

  console.log('Final fraction balance :', balFrac.toString(), 'wei‑fractions');
  console.log('Wallet TRX balance     :', balTrx / 1e6, 'TRX');
})();
