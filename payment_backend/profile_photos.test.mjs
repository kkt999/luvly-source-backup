import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {ProfilePhotosService,validProfilePhoto} from './profile_photos.mjs';
import {StaffWorkspaceService} from './staff_workspace.mjs';
import {createHandler} from './http_app.mjs';

// A real, metadata-free, synthetic 64px JPEG, generated with the app's encoder.
export const photo={mime:'image/jpeg',width:64,height:64,data:'/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDIBCQkJDAsMGA0NGDIhHCEyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMv/AABEIAEAAQAMBEQACEQEDEQH/xAGiAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgsQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+gEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoLEQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/AMysz6YKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoA//2Q=='};
const fails=code=>e=>e.code===code;
function fixture(){
  const data=new Map(Object.entries({'brides/bride':{name:'Bride'},'brides/other':{name:'Other'},'staff/employee':{active:true,role:'staff'},'staff/inactive':{active:false,role:'staff'}}));let queue=Promise.resolve();
  const store={atomic:fn=>{const operation=queue.then(async()=>{const writes=new Map();let writing=false;const result=await fn({get:async p=>{assert(!writing,'read after write');return structuredClone(data.get(p));},set:(p,r)=>{writing=true;writes.set(p,r);}});for(const[p,r]of writes)data.set(p,structuredClone(r));return result;});queue=operation.catch(()=>{});return operation;}};
  const workspace=new StaffWorkspaceService({store});
  const service=new ProfilePhotosService({store,access:(tx,uid)=>workspace.account(tx,uid),now:()=>123456});
  return {data,service};
}
const input=(patch={})=>({photo,revision:0,requestId:'upload1',...patch});

test('accepts the real small JPEG and verifies square dimensions and canonical base64',()=>{
  assert(validProfilePhoto(photo));
  for(const patch of [{height:65},{width:512,height:512},{mime:'image/svg+xml'},{data:photo.data+' '},{data:'not a photograph'},{url:'https://example.com/p.png'},{width:63,height:63},{width:513,height:513}])assert(!validProfilePhoto({...photo,...patch}));
});
test('oversized, HTML, truncated JPEG and metadata-bearing uploads are refused',()=>{
  assert(!validProfilePhoto({...photo,data:'A'.repeat(87388)}));assert(!validProfilePhoto({...photo,data:Buffer.from('<html></html>').toString('base64')}));
  const bytes=Buffer.from(photo.data,'base64');assert(!validProfilePhoto({...photo,data:bytes.subarray(0,bytes.length-3).toString('base64')}));
  const exif=Buffer.concat([bytes.subarray(0,2),Buffer.from([0xff,0xe1,0,8,69,120,105,102,0,0]),bytes.subarray(2)]);assert(!validProfilePhoto({...photo,data:exif.toString('base64')}));
});
test('own-photo save persists and another device can load it without local files',async()=>{
  const f=fixture();assert.deepEqual(await f.service.get('bride'),{uid:'bride',revision:0,photo:null});
  const saved=await f.service.save('bride',input());assert.equal(saved.revision,1);assert.deepEqual((await f.service.get('bride')).photo,photo);assert.equal((await f.service.get('other')).photo,null);assert.equal([...f.data.keys()].filter(p=>p.startsWith('profilePhotos/')).length,1);
});
test('owner is derived from auth, and inactive or unknown accounts cannot access photos',async()=>{
  const f=fixture();await assert.rejects(f.service.save('bride',input({uid:'other'})),fails('INVALID_PROFILE_PHOTO'));await assert.rejects(f.service.save('bride',input({role:'manager'})),fails('INVALID_PROFILE_PHOTO'));
  for(const uid of ['unknown','inactive']){await assert.rejects(f.service.get(uid),fails('ACCOUNT_ACCESS_REQUIRED'));await assert.rejects(f.service.save(uid,input()),fails('ACCOUNT_ACCESS_REQUIRED'));}
  await f.service.save('employee',input());assert.equal((await f.service.get('bride')).photo,null);
});
test('concurrent saves use revisions; uncertain retries do not duplicate or overwrite',async()=>{
  const f=fixture();const results=await Promise.allSettled([f.service.save('bride',input()),f.service.save('bride',input({requestId:'upload2'}))]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'PROFILE_PHOTO_CHANGED');
  assert.equal((await f.service.save('bride',input())).revision,1);await assert.rejects(f.service.save('bride',input({photo:null})),fails('REQUEST_CONFLICT'));
});
test('remove keeps a revision tombstone; a stale upload cannot resurrect a removed picture',async()=>{
  const f=fixture();await f.service.save('bride',input());await f.service.save('bride',input({requestId:'remove',revision:1,photo:null}));assert.deepEqual(await f.service.get('bride'),{uid:'bride',revision:2,photo:null});
  await assert.rejects(f.service.save('bride',input({requestId:'stale'})),fails('PROFILE_PHOTO_CHANGED'));assert.equal((await f.service.get('bride')).photo,null);
});
test('invalid stored photo is an explicit error, not a false empty avatar',async()=>{
  const f=fixture();f.data.set('profilePhotos/bride',{revision:1,photo:{...photo,data:'bad'}});await assert.rejects(f.service.get('bride'),fails('PROFILE_PHOTO_UNAVAILABLE'));
});
test('HTTP uses verified token identity and enforces photo-specific size limits',async()=>{
  const f=fixture(),server=createServer(createHandler({profilePhotos:f.service,service:{createQuote:()=>({})},verifyToken:async token=>({uid:token})}));await new Promise(r=>server.listen(0,'127.0.0.1',r));
  try{
    const base=`http://127.0.0.1:${server.address().port}`,headers={Authorization:'Bearer bride','Content-Type':'application/json'};
    assert.equal((await fetch(base+'/v1/my-profile-photo')).status,401);assert.equal((await fetch(base+'/v1/my-profile-photo?uid=other',{headers})).status,400);
    const saved=await fetch(base+'/v1/my-profile-photo',{method:'POST',headers,body:JSON.stringify(input())});assert.equal(saved.status,200);
    assert.equal((await (await fetch(base+'/v1/my-profile-photo',{headers:{Authorization:'Bearer other'}})).json()).photo,null);
    assert.equal((await fetch(base+'/v1/my-profile-photo',{method:'POST',headers,body:JSON.stringify(input({extra:'x'.repeat(10000)}))})).status,400);
    assert.equal((await fetch(base+'/v1/my-profile-photo',{method:'POST',headers,body:JSON.stringify(input({extra:'x'.repeat(100000)}))})).status,413);
    assert.equal((await fetch(base+'/v1/invoices',{method:'POST',headers,body:JSON.stringify({extra:'x'.repeat(10000)})})).status,413);
  }finally{await new Promise(r=>server.close(r));}
});
