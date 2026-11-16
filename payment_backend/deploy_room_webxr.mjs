// Administrator-only deploy of a dedicated static reference viewer.
// Never publishes the portal, backend, user media, .env or credentials.
import {loadEnvFile} from 'node:process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
const base=dirname(fileURLToPath(import.meta.url)),root=resolve(base,'..');
const directory=resolve(root,'web_room_ar');
const site='luvly-44c77-room-ar',origin=`https://${site}.web.app`;
const model=JSON.parse(readFileSync(resolve(directory,'model.json'),'utf8'));
if(model.id!=='princess-wedding'||!/^\/princess-room-[0-9a-f]{16}\.glb$/.test(model.url))throw Error('Unexpected reference');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const glb=readFileSync(resolve(directory,model.url.slice(1)));
if(sha(glb)!==model.sha256||glb.length>10_000_000)throw Error('Reference integrity failed');
if(!readFileSync(resolve(directory,'index.html'),'utf8').includes('ar-modes="webxr"'))throw Error('WebXR-only mode required');
const names=['index.html','room.css','room.js','model.json','model-viewer-4.4.0.min.js','MODEL_VIEWER_LICENSE.txt',model.url.slice(1)];
const files=new Map(names.map(name=>{
  const raw=readFileSync(resolve(directory,name)),compressed=gzipSync(raw,{level:9});
  return ['/'+name,{raw,compressed,hash:sha(compressed)}];
}));
console.log(JSON.stringify({site,origin,files:[...files].map(([path,x])=>({path,bytes:x.raw.length})),deploy:process.argv.includes('--deploy')}));
if(!process.argv.includes('--deploy'))process.exit(0);
loadEnvFile(resolve(base,'.env'));
const key=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(key)});
try{
  const token=await app.options.credential.getAccessToken();
  const headers={Authorization:`Bearer ${token.access_token}`,'Content-Type':'application/json'};
  async function api(path,method='GET',body){
    const response=await fetch('https://firebasehosting.googleapis.com/v1beta1/'+path,{
      method,headers,body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(45000)});
    const json=await response.json();
    if(!response.ok)throw Error(`Hosting ${method} ${path.split('?')[0]} failed (${response.status}, ${json.error?.status??'unknown'})`);
    return json;
  }
  const sites=await api('projects/luvly-44c77/sites');
  const existing=sites.sites?.find(x=>x.name.endsWith('/sites/'+site));
  if(!existing)await api(`projects/luvly-44c77/sites?siteId=${site}`,'POST',{});
  else{
    const history=await api(`sites/${site}/releases?pageSize=1`);
    if(history.releases?.length&&!history.releases[0].message?.startsWith('Luvly room AR'))
      throw Error('Refusing to replace an unrelated site');
  }
  const version=await api(`sites/${site}/versions`,'POST',{config:{
    headers:[
      {glob:'**',headers:{'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff',
        'Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex, nofollow',
        'Permissions-Policy':'camera=(self), xr-spatial-tracking=(self), microphone=(), geolocation=()',
        'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; worker-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"}},
      {glob:'**/*.glb',headers:{'Content-Type':'model/gltf-binary','Cache-Control':'public,max-age=31536000,immutable'}},
      {glob:'model-viewer-4.4.0.min.js',headers:{'Cache-Control':'public,max-age=31536000,immutable'}},
    ],
  }});
  if(!version.name?.startsWith(`sites/${site}/versions/`))throw Error('Unexpected version');
  const populate=await api(version.name+':populateFiles','POST',{
    files:Object.fromEntries([...files].map(([path,x])=>[path,x.hash])),
  });
  if(new URL(populate.uploadUrl).origin!=='https://upload-firebasehosting.googleapis.com')throw Error('Unexpected upload host');
  for(const hash of populate.uploadRequiredHashes??[]){
    const file=[...files.values()].find(x=>x.hash===hash);if(!file)throw Error('Unknown upload requested');
    const response=await fetch(populate.uploadUrl+'/'+hash,{method:'POST',
      headers:{Authorization:headers.Authorization,'Content-Type':'application/octet-stream'},
      body:file.compressed,signal:AbortSignal.timeout(60000)});
    if(!response.ok)throw Error('Static upload failed: '+response.status);
  }
  await api(version.name+'?update_mask=status','PATCH',{status:'FINALIZED'});
  const release=await api(`sites/${site}/releases?versionName=${encodeURIComponent(version.name)}`,'POST',{
    message:'Luvly room AR 2101 — Chrome WebXR only; static reference model',
  });
  mkdirSync(resolve(root,'work/room-ar-2101'),{recursive:true});
  writeFileSync(resolve(root,'work/room-ar-2101/hosting-release.json'),JSON.stringify({origin,version:version.name,
    release:release.name,files:[...files].map(([path,x])=>({path,sha256:sha(x.raw)}))},null,2));
  console.log('PASS dedicated WebXR site released: '+origin);
}finally{await deleteApp(app);}
