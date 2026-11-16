import {parentPort,workerData} from 'node:worker_threads';
import {createFile} from 'mp4box';
// Parsing untrusted video containers is isolated, memory-bounded and timed out
// by the parent. No shell, URL fetching, external codecs or executable uploads.
try {
  const b=Buffer.from(workerData), ranges=[];let pos=0,boxes=0,ftyp=false;
  while(pos<b.length){
    if(++boxes>512||pos+8>b.length)throw Error();
    let length=b.readUInt32BE(pos),header=8;
    const type=b.toString('ascii',pos+4,pos+8);
    if(length===1){if(pos+16>b.length)throw Error();length=Number(b.readBigUInt64BE(pos+8));header=16;}
    if(length===0)length=b.length-pos;
    if(!Number.isSafeInteger(length)||length<header||pos+length>b.length)throw Error();
    if(type==='ftyp')ftyp=true;
    if(type==='mdat')ranges.push([pos+header,pos+length]);
    pos+=length;
  }
  if(!ftyp||!ranges.length)throw Error();
  const f=createFile();let info,failed=false;
  f.onReady=v=>{info=v;};f.onError=()=>{failed=true;};
  const ab=b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength);ab.fileStart=0;
  f.appendBuffer(ab);f.flush();
  if(failed||!info||info.isFragmented||info.videoTracks.length!==1||info.tracks.length>2)throw Error();
  const v=info.videoTracks[0],duration=info.duration/info.timescale;
  if(!Number.isFinite(duration)||duration<=0||duration>30.1||!/^avc[13]\./.test(v.codec)||!v.nb_samples||v.nb_samples>5000||v.video.width<16||v.video.height<16||v.video.width>1920||v.video.height>1920)throw Error();
  for(const t of info.tracks){
    if(!(t.video||t.audio)||t.audio&&!/^mp4a\./.test(t.codec)||t.duration/t.timescale>30.1)throw Error();
    const track=f.getTrackById(t.id);
    if(!track?.samples?.length||track.samples.length>10000)throw Error();
    for(const s of track.samples)if(!Number.isSafeInteger(s.size)||s.size<1||!ranges.some(([a,z])=>s.offset>=a&&s.offset+s.size<=z))throw Error();
  }
  parentPort.postMessage({mime:'video/mp4',width:v.video.width,height:v.video.height,duration:Math.round(duration*1000)/1000});
} catch {parentPort.postMessage(null);}
