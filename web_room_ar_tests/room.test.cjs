const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../web_room_ar/room.js'),'utf8');
async function page({supported=true,manifest,search=''}={}){
  const elements=new Map(),intervals=[];
  const element=id=>{
    if(!elements.has(id))elements.set(id,{disabled:id==='#place',hidden:false,textContent:'',src:'',attrs:{},listeners:{},
      canActivateAR:supported,activateCount:0,activateAR(){this.activateCount++;},
      classList:{toggle(){}},getAttribute(name){return this.attrs[name]??null;},
      addEventListener(name,handler){this.listeners[name]=handler;},
      emit(name,detail){if(name==='ar-status')this.attrs['ar-status']=detail.status;this.listeners[name]?.({detail});},
    });return elements.get(id);
  };
  const context={document:{querySelector:element},URL,URLSearchParams,
    location:{origin:'https://luvly-44c77-room-ar.web.app',search,reload(){}},
    navigator:{xr:{isSessionSupported:async()=>supported}},
    customElements:{whenDefined:async()=>{}},
    fetch:async()=>({ok:true,json:async()=>manifest??{id:'princess-wedding',url:'/princess-room-0123456789abcdef.glb'}}),
    setTimeout(){},setInterval(fn){intervals.push(fn);},
  };
  vm.runInNewContext(source,context);
  await new Promise(resolve=>setImmediate(resolve));
  return {element,poll:()=>intervals.forEach(fn=>fn())};
}
test('supported device loads the model without requesting an automatic camera session',async()=>{
  const p=await page();const viewer=p.element('#gown');
  assert.match(viewer.src,/^https:\/\/luvly-44c77-room-ar.web.app\/princess-room-/);
  assert.equal(viewer.activateCount,0);
  viewer.emit('load');assert.equal(p.element('#place').disabled,false);
  assert.equal(p.element('#place').textContent,'Place in my room');
  p.element('#place').emit('click');assert.equal(viewer.activateCount,0,'slot activation must not be duplicated');
});
test('unsupported browser gets an explicit explanation and no fake room AR',async()=>{
  const p=await page({supported:false});p.element('#gown').emit('load');
  assert.equal(p.element('#place').disabled,true);
  assert.match(p.element('#status').textContent,/unavailable in this browser/);
});
test('camera/session failure remains visible after a mode change and polling',async()=>{
  const p=await page();const viewer=p.element('#gown');viewer.emit('load');
  viewer.emit('ar-status',{status:'failed'});const error=p.element('#status').textContent;
  viewer.emit('ar-status',{status:'not-presenting'});p.poll();
  assert.match(error,/could not start/);assert.equal(p.element('#status').textContent,error);
  assert.equal(p.element('#recovery').hidden,false);
});
test('external model URLs and unknown models are rejected before any model loads',async()=>{
  for(const options of [{manifest:{id:'princess-wedding',url:'https://example.com/private.glb'}},
    {search:'?model=not-a-gown'}]){
    const p=await page(options);assert.equal(p.element('#gown').src,'');
    assert.match(p.element('#status').textContent,/could not start/);
  }
});
test('download failure has a retry path',async()=>{
  const p=await page();p.element('#gown').emit('error');p.poll();
  assert.match(p.element('#status').textContent,/could not load/);
  assert.equal(p.element('#recovery').hidden,false);
});
