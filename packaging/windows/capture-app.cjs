const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const browser = await chromium.launch({headless: true});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1});
  await page.goto(process.env.LAUNDRY_TEST_URL, {waitUntil: 'networkidle'});
  await page.screenshot({path: path.join(__dirname, '../../installer-evidence/02-installed-application.png'), fullPage: true});
  await browser.close();
})().catch(error => { console.error(error); process.exit(1); });
