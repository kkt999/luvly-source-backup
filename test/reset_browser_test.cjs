// Headless browser regression test. Serves only auth_site and mocks all Auth
// responses; no real user, email or password is sent to Firebase.
const {chromium} = require('playwright');
const {createServer} = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const files = new Set(['index.html','reset.mjs','reset-api.mjs','password-policy.mjs','style.css']);
const root = path.resolve(__dirname, '../auth_site');
const server = createServer((req,res) => {
  const filename = new URL(req.url, 'http://localhost').pathname.slice(1) || 'index.html';
  if (!files.has(filename)) { res.writeHead(404); res.end(); return; }
  const type = filename.endsWith('.mjs') ? 'text/javascript' : filename.endsWith('.css') ? 'text/css' : 'text/html';
  res.writeHead(200, {'Content-Type':type, 'Referrer-Policy':'no-referrer'});
  res.end(fs.readFileSync(path.join(root,filename)));
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const url = `http://127.0.0.1:${server.address().port}/`;
  const browser = await chromium.launch({channel:'chrome', headless:true});
  try {
    const page = await browser.newPage({viewport:{width:390,height:844}});
    const problems = [];
    page.on('pageerror', e=>problems.push(e.message));
    let confirms = 0, verifies = 0, mode = 'ok';
    await page.route('**/*', async route=>{
      if (route.request().url().startsWith(url)) return route.continue();
      if (!route.request().url().startsWith('https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?')) return route.abort();
      const data = route.request().postDataJSON();
      assert.equal(data.oobCode, 'synthetic-code');
      if (data.newPassword) confirms++; else verifies++;
      if (mode === 'network') return route.abort('internetdisconnected');
      if (mode === 'expired') return route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({error:{message:'EXPIRED_OOB_CODE'}})});
      return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({email:'synthetic@example.com',requestType:'PASSWORD_RESET'})});
    });
    const open = ()=>page.goto(url+'?mode=resetPassword&oobCode=synthetic-code');
    await open();
    await page.locator('#reset-form').waitFor({state:'visible'});
    assert.equal(new URL(page.url()).search, '');
    await page.getByLabel('New password',{exact:true}).fill('12345678');
    await page.getByLabel('Confirm new password',{exact:true}).fill('12345678');
    await page.getByRole('button',{name:'Save new password',exact:true}).click();
    assert.match(await page.locator('#error').textContent(), /five password requirements/);
    assert.equal(confirms,0);
    await page.locator('#password').fill('Unique1!password');
    await page.locator('#confirmation').fill('Different1!password');
    await page.locator('#submit').click();
    assert.match(await page.locator('#error').textContent(), /do not match/);
    assert.equal(confirms,0);
    await page.locator('#confirmation').fill('Unique1!password');
    await page.screenshot({path:path.resolve(__dirname,'previews/reset-password-mobile.png'),fullPage:true});
    await page.locator('#submit').click();
    await page.getByText('Your password has been updated.',{exact:false}).waitFor();
    assert.equal(confirms,1);
    assert.equal(await page.locator('#password').inputValue(),'');
    mode = 'expired';
    await open();
    await page.getByText('This link is invalid, expired or already used.',{exact:false}).waitFor();
    assert.equal(await page.locator('#reset-form').isVisible(),false);
    mode = 'network';
    await open();
    await page.locator('#retry').waitFor({state:'visible'});
    mode = 'ok';
    await page.locator('#retry').click();
    await page.locator('#reset-form').waitFor({state:'visible'});
    for (const width of [320,390,1024]) {
      await page.setViewportSize({width,height:844});
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth <= window.innerWidth),true,`overflow at ${width}`);
    }
    await page.goto(url);
    await page.getByText('Open the password-reset link',{exact:false}).waitFor();
    assert.equal(await page.locator('#reset-form').isVisible(),false);
    assert.ok(verifies >= 3);
    assert.deepEqual(problems,[]);
    console.log('PASS reset browser: weak/mismatch blocked, confirmation, expired/missing code, network retry, 320/390/1024 layouts');
  } finally { await browser.close(); }
})().catch(e=>{console.error(e.message);process.exitCode=1;}).finally(()=>server.close());
