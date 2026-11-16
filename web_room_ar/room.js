// WebXR only: deliberately excludes the crashing external Scene Viewer path.
const viewer=document.querySelector('#gown');
const place=document.querySelector('#place');
const status=document.querySelector('#status');
const progress=document.querySelector('#progress');
const recovery=document.querySelector('#recovery');
let loaded=false,failed=false,arLaunchFailed=false,xrSupported=null;
function message(text,error=false){status.textContent=text;status.classList.toggle('error',error);}
function available(){
  if(failed||arLaunchFailed)return;
  if(!loaded){message('Loading your gown. Please keep this page open.');return;}
  if(viewer.canActivateAR){
    place.disabled=false;place.textContent='Place in my room';
    message('Tap Place in my room, allow the camera if asked, then scan a well-lit floor.');
  }else if(xrSupported===false){
    message('Room AR is unavailable in this browser. Open this page in current Chrome on an AR-supported Android phone with Google Play Services for AR. You can still explore the 3D model here.',true);
  }else{
    message('Checking room AR support. If no placement button appears, update Chrome and Google Play Services for AR.');
  }
}
function error(text){failed=true;place.disabled=true;progress.hidden=true;recovery.hidden=false;message(text,true);}
document.querySelector('#retry').addEventListener('click',()=>location.reload());
viewer.addEventListener('load',()=>{loaded=true;progress.hidden=true;available();});
viewer.addEventListener('error',()=>error('The gown could not load. Check your connection and try again.'));
viewer.addEventListener('progress',event=>{
  if(!loaded)progress.textContent=`Loading your gown… ${Math.round(event.detail.totalProgress*100)}%`;
});
viewer.addEventListener('ar-status',event=>{
  const state=event.detail.status;
  if(state==='failed'){
    arLaunchFailed=true;
    recovery.hidden=false;
    message('Room AR could not start. Check camera access, Chrome and Google Play Services for AR, then try again.',true);
  }else if(state==='session-started'){arLaunchFailed=false;message('Move your phone slowly to find a clear floor.');}
  else if(state==='object-placed')message('Gown placed. Walk around it; pinch to adjust its illustrative scale.');
  else if(state==='not-presenting')available();
});
// The model-viewer ar-button slot owns the user-gesture activation. Do not
// call activateAR again here, which would request two immersive sessions.
place.addEventListener('click',()=>message('Starting room AR…'));
async function start(){
  const requested=new URLSearchParams(location.search).get('model');
  if(requested&&requested!=='princess-wedding')throw Error('Unknown reference model');
  const response=await fetch('/model.json',{cache:'no-cache'});
  if(!response.ok)throw Error('Model manifest unavailable');
  const model=await response.json();
  const url=new URL(model.url,location.origin);
  if(model.id!=='princess-wedding'||url.origin!==location.origin||url.search||url.hash||
     !/^\/princess-room-[0-9a-f]{16}\.glb$/.test(url.pathname))
    throw Error('Invalid reference model');
  await customElements.whenDefined('model-viewer');
  viewer.src=url.href;
  try{xrSupported=!!navigator.xr&&await navigator.xr.isSessionSupported('immersive-ar');}
  catch{xrSupported=false;}
  available();
}
start().catch(()=>error('The room view could not start. Check your connection and try again.'));
setTimeout(()=>{
  if(!loaded&&!failed){recovery.hidden=false;message('Loading is taking longer than expected. Check your connection, or try again.',true);}
},30000);
setInterval(()=>{
  const state=viewer.getAttribute('ar-status');
  if(loaded&&!failed&&(!state||state==='not-presenting'))available();
},2000);
