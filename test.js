require('dotenv').config();
const { TronWeb } = require('tronweb');

/* ───────────────────────────────────────────────────────────────── */
/*  Environment config                                              */
/* ───────────────────────────────────────────────────────────────── */

const FULL_NODE = process.env.FULL_NODE_DEVELOPMENT;
const OWNER_KEY = process.env.OWNER_PRIVATE_KEY;
const TEST_KEY  = process.env.TEST_PRIVATE_KEY;
const CONTRACT  = process.env.CONTRACT_ADDRESS;   // deployed MultiProperty
const USDT_ADDR = process.env.USDT_ADDRESS;       // Mock or real USDT

if (!FULL_NODE || !OWNER_KEY || !CONTRACT || !USDT_ADDR) {
  console.error('❌  Check FULL_NODE_DEVELOPMENT, OWNER_PRIVATE_KEY, CONTRACT_ADDRESS and USDT_ADDRESS in .env');
  process.exit(1);
}
if (!TEST_KEY) {
  console.error('❌  Provide TEST_PRIVATE_KEY in .env');
  process.exit(1);
}

/* ───────────────────────────────────────────────────────────────── */
/*  Constants                                                       */
/* ───────────────────────────────────────────────────────────────── */

const FRACTIONS_TO_BUY = 2n;       // whole‑unit fractions
const DIVIDEND_USDT    = 200n;     // rent income in USDT (whole units)

/* ───────────────────────────────────────────────────────────────── */
/*  Main                                                            */
/* ───────────────────────────────────────────────────────────────── */

(async () => {
  /* -------- create signers -------------------------------------- */
  const ownerWeb = new TronWeb(FULL_NODE, FULL_NODE, FULL_NODE, OWNER_KEY);
  const testWeb  = new TronWeb(FULL_NODE, FULL_NODE, FULL_NODE, TEST_KEY);

  const ownerAddr = ownerWeb.address.fromPrivateKey(OWNER_KEY);
  const testAddr  = testWeb.address.fromPrivateKey(TEST_KEY);

  console.log('\nOwner address        :', ownerAddr);
  console.log('Test  address        :', testAddr);
  console.log('Fraction contract    :', CONTRACT);
  console.log('USDT token           :', USDT_ADDR);
  console.log('RPC node             :', FULL_NODE, '\n');

  /* -------- connect contracts ----------------------------------- */
  const tokenAsOwner = await ownerWeb.contract().at(CONTRACT);
  const token        = await testWeb.contract().at(CONTRACT);
  const usdtOwner    = await ownerWeb.contract().at(USDT_ADDR);
  const usdtTest     = await testWeb.contract().at(USDT_ADDR);

  console.log('Token name           :', await token.name().call(), '\n');

  /* -------- buy fractions --------------------------------------- */
  const price  = BigInt((await token.getPrice().call()).toString());     // micro‑USDT
  const cost   = price * FRACTIONS_TO_BUY;                               // micro‑USDT
  const costUI = Number(cost) / 1e6;                                     // whole USDT

  console.log(`Buying ${FRACTIONS_TO_BUY} fractions for ${costUI} USDT …`);

  // Approve spending
  let tx = await usdtTest.approve(CONTRACT, cost.toString()).send();
  console.log('   ➜ approve()  tx id:', tx);

  // Execute purchase
  tx = await token.buy(Number(FRACTIONS_TO_BUY)).send();
  console.log('   ➜ buy()      tx id:', tx, '\n');

  /* -------- deposit dividends (owner) --------------------------- */
  const deposit = DIVIDEND_USDT * 1_000_000n;  // to micro‑USDT
  console.log(`Depositing ${DIVIDEND_USDT} USDT rental income …`);

  // Owner approves then deposits
  tx = await usdtOwner.approve(CONTRACT, deposit.toString()).send();
  console.log('   ➜ approve()  tx id:', tx);

  tx = await tokenAsOwner.depositDividends(deposit.toString()).send();
  console.log('   ➜ deposit()  tx id:', tx, '\n');

  /* -------- claim dividends (test user) ------------------------- */
  const pending = BigInt((await token.claimable(testAddr).call()).toString());
  console.log('Claimable for test address:', Number(pending) / 1e6, 'USDT');

  if (pending > 0n) {
    tx = await token.claim().send();
    console.log('   ➜ claim()    tx id:', tx, '\n');
  } else {
    console.log('   ➜ nothing to claim\n');
  }

  /* -------- final balances -------------------------------------- */
  const balFrac = await token.balanceOf(testAddr).call();
  const balUsdt = await usdtTest.balanceOf(testAddr).call();

  console.log('Final fraction balance :', balFrac.toString(), 'wei‑fractions');
  console.log('Wallet USDT balance    :', Number(balUsdt) / 1e6, 'USDT\n');
})();
