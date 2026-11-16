// Read-only demonstration preflight. Never loads credentials or changes records.
import {readFileSync} from 'node:fs';
import {validBackendOrigin} from './backend_origin.mjs';
const checks=[];
async function check(label,url,{expected=200,headers,method='GET',sandbox=false}={}) {
  try {
    const r=await fetch(url,{method,headers,redirect:'error',signal:AbortSignal.timeout(10000)});
    const body=await r.text();
    const ok=r.status===expected&&(!sandbox||JSON.parse(body).environment==='sandbox');
    checks.push({label,ok,status:r.status});
  } catch { checks.push({label,ok:false,status:'unreachable or invalid response'}); }
}
await check('Local portal','http://localhost:5000');
let origin;
try {
  const env=readFileSync(new URL('.env',import.meta.url),'utf8');
  const candidate=new URL(/^PAYMENT_RETURN_URL=(.+)$/m.exec(env)?.[1].trim());
  if(candidate.pathname==='/return'&&validBackendOrigin(candidate.origin))origin=candidate.origin;
} catch { /* Report configuration unavailable without printing secrets. */ }
if(origin) {
  await check('Mobile public backend',`${origin}/health`,{sandbox:true});
  await check('Public authentication required',`${origin}/v1/notifications`,{expected:401});
  await check('Staff portal CORS',`${origin}/v1/notifications`,{method:'OPTIONS',headers:{Origin:'http://localhost:5000'},expected:204});
  await check('Other origins rejected',`${origin}/v1/notifications`,{method:'OPTIONS',headers:{Origin:'https://untrusted.example'},expected:403});
  await check('Maintenance is not public',`${origin}/internal/maintenance`,{method:'POST',expected:401});
} else checks.push({label:'Mobile endpoint configuration',ok:false,status:'missing'});
for(const c of checks) console.log(`${c.ok?'PASS':'FAIL'} ${c.label}: ${c.status}`);
console.log('Readiness only: this does not verify signed-in flows, payments, email or Calendar authorization.');
if(checks.some(c=>!c.ok)) process.exitCode=1;
