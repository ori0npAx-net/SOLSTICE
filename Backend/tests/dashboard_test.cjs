const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_EXE||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1100}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:8080');
  await page.waitForFunction(()=>document.getElementById('connectionText').textContent==='DATABASE CONNECTED');
  assert.equal(await page.locator('#panelRows tr').count(),16);
  assert.equal(await page.locator('#panelStatus').textContent(),'16 registered');
  assert.equal(await page.locator('#panelSelect option').count(),16);
  assert.equal(await page.locator('#historyClock').inputValue(),'simulation');
  await page.selectOption('#dateSelect','');
  await page.waitForFunction(()=>document.getElementById('historyScope').textContent.startsWith('All dates'));
  await page.selectOption('#historyClock','legacy');
  await page.waitForFunction(()=>document.getElementById('readingRows').textContent.includes('Legacy'));
  await page.selectOption('#historyClock','simulation');
  await page.waitForFunction(()=>document.getElementById('readingRows').textContent.includes('Simulation')&&!document.getElementById('readingRows').textContent.includes('Legacy'));
  const download=page.waitForEvent('download');await page.click('#exportBtn');const file=await download;assert(file.suggestedFilename().endsWith('.csv'));
  await page.evaluate(()=>window.scrollTo(0,0));
  await page.screenshot({path:path.resolve(__dirname,'../../GodotSimulation/.runtime/dashboard-preview.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:path.resolve(__dirname,'../../GodotSimulation/.runtime/dashboard-mobile.png'),fullPage:true});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1),'Page must fit mobile width');
  assert.deepEqual(errors,[]);
  console.log('DASHBOARD PASS: 16 panels, clock/date filters, legacy history, CSV, desktop/mobile layout and no script errors');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
