'use strict';
const $=id=>document.getElementById(id),limit=16*1024*1024;
let ready=false,encoderReady=false,tab='receive',playing=false,prepared=false,encoding=false;
let fps=15,lastTick=0,sent=0,stream=null,cameraEpoch=0,worker=null,workerReady=false,inFlight=false,videoCallback=0;
let recovered=null,saving=false,torchOn=false,lastMediaTime=-1;
const scratch=document.createElement('canvas');let scratchContext;
function message(id,text){$(id).textContent=text;}
function size(n){return n<1024?n+' B':n<1048576?(n/1024).toFixed(1)+' KB':(n/1048576).toFixed(2)+' MB';}
function nativeCall(name,...args){return window.CimbarNative?.[name]?.(...args);}
var Module={canvas:$('canvas'),print:()=>{},printErr:()=>{},onRuntimeInitialized(){ready=true;$('pick').disabled=false;$('createText').disabled=false;message('loadStatus','无需网络，让另一部手机打开“扫描”即可接收。');},onAbort(){message('loadStatus','无法启动离线编码器，请更新 Android System WebView 后重试');}};
function pauseSend(){playing=false;$('play').textContent='开始播放';nativeCall('setSending',false);}
function stopCamera(){cameraEpoch++;if(videoCallback){if($('video').cancelVideoFrameCallback)$('video').cancelVideoFrameCallback(videoCallback);else cancelAnimationFrame(videoCallback);videoCallback=0;}stream?.getTracks().forEach(t=>t.stop());stream=null;$('video').srcObject=null;$('cameraStart').textContent='继续扫描';$('zoomLabel').hidden=true;$('torch').hidden=true;torchOn=false;}
function switchTab(next){if(encoding)return;tab=next;pauseSend();stopCamera();document.body.classList.remove('expanded');$('receive').hidden=next!=='receive';$('send').hidden=next!=='send';$('receiveTab').classList.toggle('selected',next==='receive');$('sendTab').classList.toggle('selected',next==='send');}
$('receiveTab').onclick=()=>switchTab('receive');$('sendTab').onclick=()=>switchTab('send');
$('back').onclick=()=>{if(document.body.classList.contains('expanded')){document.body.classList.remove('expanded');message('enlarge','放大显示');}else{pauseSend();stopCamera();nativeCall('close');}};
function initWorker(){
 worker?.terminate();workerReady=false;inFlight=false;recovered=null;$('save').hidden=true;$('cameraStart').disabled=true;$('cameraStart').hidden=false;$('progress').value=0;
 message('receiveStatus','正在加载离线解码器…');worker=new Worker('decoder-worker.js');
 worker.onmessage=({data})=>{inFlight=false;
  if(data.type==='ready'){workerReady=true;$('cameraStart').disabled=false;message('receiveStatus','准备就绪，点击开始扫描');return;}
  if(data.type==='error'){stopCamera();message('receiveStatus',data.message);return;}
  if(data.type==='progress'){
   const p=Math.min(.99,Math.max(0,...data.progress));$('progress').value=p;
   message('receiveStatus','正在接收 · '+Math.floor(p*100)+'%');
   if(data.elapsed>1000)message('speed','已解码 '+size(data.received)+' · 解码 '+size(data.received/(data.elapsed/1000))+'/秒');
  }
  if(data.type==='complete'){recovered=data;stopCamera();$('progress').value=1;$('cameraStart').hidden=true;$('save').hidden=false;message('receiveStatus','接收完成：'+data.name);message('speed',size(data.bytes.length)+(data.verified?' · 完整性校验通过':'')+' · 可以保存到手机');}
 };
 worker.onerror=()=>{stopCamera();message('receiveStatus','解码器加载失败，请重新识别；旧系统请更新 Android System WebView');};
}
function scheduleVideo(){if(!stream)return;videoCallback=$('video').requestVideoFrameCallback?$('video').requestVideoFrameCallback(capture):requestAnimationFrame(capture);}
function capture(now){
 if(!stream)return;scheduleVideo();
 const video=$('video');if(inFlight||!workerReady||recovered||video.readyState<2||video.currentTime===lastMediaTime)return;
 lastMediaTime=video.currentTime;inFlight=true;
 try{
  if(typeof VideoFrame!=='undefined'){
   const frame=new VideoFrame(video,{timestamp:Math.round(now*1000)});
   try{worker.postMessage({frame},[frame]);}catch(e){frame.close();throw e;}
  }else{
   const width=video.videoWidth,height=video.videoHeight;
   if(scratch.width!==width||scratch.height!==height){scratch.width=width;scratch.height=height;}
   scratchContext??=scratch.getContext('2d',{willReadFrequently:true});scratchContext.drawImage(video,0,0);
   const pixels=scratchContext.getImageData(0,0,width,height).data;worker.postMessage({pixels,width,height},[pixels.buffer]);
  }
 }catch(_){inFlight=false;stopCamera();message('receiveStatus','相机画面读取失败，请更新 Android System WebView 后重试');}
}
async function startCamera(){
 if(!workerReady||recovered)return;
 if(stream){stopCamera();message('receiveStatus','已暂停，接收进度已保留');return;}
 const epoch=++cameraEpoch;$('cameraStart').disabled=true;
 try{
  if(!navigator.mediaDevices?.getUserMedia)throw Error('当前系统不支持相机，请更新 Android System WebView');
  const result=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:'environment'},width:{ideal:1920},height:{ideal:1080},frameRate:{ideal:30,max:30}}});
  if(epoch!==cameraEpoch||tab!=='receive'){result.getTracks().forEach(t=>t.stop());return;}
  stream=result;$('video').srcObject=result;await $('video').play();
  if(epoch!==cameraEpoch)return;
  const track=result.getVideoTracks()[0],cap=track.getCapabilities?.()||{};
  if(cap.focusMode?.includes('continuous'))track.applyConstraints({advanced:[{focusMode:'continuous'}]}).catch(()=>{});
  $('torch').hidden=!cap.torch;
  if(cap.zoom){$('zoomLabel').hidden=false;Object.assign($('zoom'),{min:cap.zoom.min,max:cap.zoom.max,step:cap.zoom.step||.1,value:track.getSettings().zoom||cap.zoom.min});}
  nativeCall('report','camera ready '+$('video').videoWidth+'x'+$('video').videoHeight);message('receiveStatus','正在扫描，请将彩色码四角全部放入画面');$('cameraStart').textContent='暂停扫描';lastMediaTime=-1;scheduleVideo();
 }catch(e){if(epoch===cameraEpoch){stopCamera();message('receiveStatus',e.name==='NotAllowedError'?'请允许相机权限后重新扫描':String(e.message||e));}}
 finally{$('cameraStart').disabled=false;}
}
$('cameraStart').onclick=startCamera;
$('reset').onclick=()=>{if(saving)return;stopCamera();initWorker();message('speed','手机之间直接传输，无需联网');};
$('torch').onclick=async()=>{try{await stream?.getVideoTracks()[0].applyConstraints({advanced:[{torch:!torchOn}]});torchOn=!torchOn;message('torch',torchOn?'关闭补光':'补光灯');}catch(_){message('receiveStatus','此摄像头暂不支持补光');}};
$('zoom').oninput=()=>stream?.getVideoTracks()[0].applyConstraints({advanced:[{zoom:Number($('zoom').value)}]}).catch(()=>{});
function initEncoder(){if(encoderReady)return;if(Module._cimbare_configure(68,3)<0||Module._cimbare_init_window(0,0)<0)throw Error('手机无法创建彩色码，请更新 Android System WebView');encoderReady=true;}
async function importFile(file){
 if(!ready||encoding)return;if(tab!=='send')switchTab('send');if(file.size>limit){message('loadStatus','文件最大支持 16 MB');return;}
 pauseSend();encoding=true;$('pick').disabled=true;$('createText').disabled=true;
 try{
  // A short envelope supplies entropy for tiny/highly compressible files and
  // end-to-end integrity. The receiver removes it before saving the original.
  const original=file,content=new Uint8Array(await original.arrayBuffer());
  const header=new Uint8Array(556);header.set(new TextEncoder().encode('CMBAPP01'));
  new DataView(header.buffer).setUint32(8,content.length,false);
  header.set(new Uint8Array(await crypto.subtle.digest('SHA-256',content)),12);
  crypto.getRandomValues(header.subarray(44));
  file=new File([header,content],original.name);
  const name=new TextEncoder().encode(file.name||'file.bin');
  if(name.length>480)throw Error('文件名过长，请缩短文件名后再发送');
  initEncoder();const np=Module._malloc(name.length);
  try{Module.HEAPU8.set(name,np);if(Module._cimbare_init_encode(np,name.length,-1)<0)throw Error('文件初始化失败');}finally{Module._free(np);}
  const chunkSize=Module._cimbare_encode_bufsize()*16,p=Module._malloc(chunkSize);let result=1;
  try{for(let offset=0;offset<file.size;offset+=chunkSize){const bytes=new Uint8Array(await file.slice(offset,offset+chunkSize).arrayBuffer());Module.HEAPU8.set(bytes,p);result=Module._cimbare_encode(p,bytes.length);if(result<0)throw Error('文件编码失败');message('loadStatus','正在准备 '+Math.min(100,Math.round((offset+bytes.length)/Math.max(1,file.size)*100))+'%');}
   if(result!==0)result=Module._cimbare_encode(p,0);if(result!==0)throw Error('文件编码未完成');
  }finally{Module._free(p);}
  prepared=true;sent=0;$('codeBox').hidden=false;$('playControls').hidden=false;$('textEntry').hidden=true;
  message('fileInfo',original.name+' · '+size(original.size));message('loadStatus','准备就绪。另一部手机打开“扫描”，然后开始播放。');
  renderFrame();nativeCall('report','sender ready '+Module.canvas.width+'x'+Module.canvas.height);
 }catch(e){nativeCall('report','sender error '+String(e.message||e));prepared=false;$('codeBox').hidden=true;$('playControls').hidden=true;$('textEntry').hidden=false;message('loadStatus',String(e.message||e));}
 finally{encoding=false;$('pick').disabled=false;$('createText').disabled=false;}
}
function renderFrame(){if(Module._cimbare_next_frame(false)<0||Module._cimbare_render()<0)throw Error('彩色码生成失败');sent++;}
function tick(now){requestAnimationFrame(tick);if(!playing||now-lastTick<1000/fps)return;lastTick=now-((now-lastTick)%(1000/fps));try{renderFrame();if(sent%15===0)message('sendStatus','已播放 '+sent+' 帧 · 接收完成后停止播放');}catch(e){pauseSend();message('sendStatus',e.message);}}
$('play').onclick=()=>{if(!prepared)return;if(playing)pauseSend();else{playing=true;lastTick=0;message('play','暂停播放');nativeCall('setSending',true);}};
$('fps').oninput=()=>{fps=Number($('fps').value);message('fpsLabel',fps+' 帧/秒');};
$('enlarge').onclick=()=>{document.body.classList.toggle('expanded');message('enlarge',document.body.classList.contains('expanded')?'退出放大':'放大显示');};
$('pick').onclick=()=>window.CimbarNative?nativeCall('pickFile'):$('browserFile').click();
$('browserFile').onchange=()=>{const file=$('browserFile').files[0];if(file)importFile(file);$('browserFile').value='';};
$('createText').onclick=()=>{if(!$('text').value){message('loadStatus','请先输入文本');return;}importFile(new File([$('text').value],'文本.txt'));};
window.onPickedFile=async (name,url)=>{try{const response=await fetch(url);if(!response.ok)throw Error('读取文件失败');const blob=await response.blob();await importFile(new File([blob],name));}catch(e){message('loadStatus',e.message);}};
window.onNativeError=messageText=>message(tab==='send'?'loadStatus':'receiveStatus',messageText);
window.onSaveResult=saved=>{saving=false;$('save').disabled=false;message('receiveStatus',saved?'文件已保存：'+recovered.name:'保存已取消，文件仍然保留');};
$('save').onclick=async()=>{
 if(!recovered||saving)return;saving=true;$('save').disabled=true;
 try{
  const {name,bytes}=recovered;
  if(window.CimbarNative){
   if(!nativeCall('beginSave',name,bytes.length))throw Error('无法准备保存文件');
   for(let pos=0;pos<bytes.length;pos+=49152){const chunk=bytes.subarray(pos,pos+49152);let str='';for(let i=0;i<chunk.length;i++)str+=String.fromCharCode(chunk[i]);if(!nativeCall('writeSaveChunk',btoa(str)))throw Error('保存文件失败');if(pos%393216===0)await new Promise(r=>setTimeout(r,0));}
   nativeCall('finishSave');
  }else{const url=URL.createObjectURL(new Blob([bytes]));const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);window.onSaveResult(true);}
 }catch(e){saving=false;$('save').disabled=false;message('receiveStatus',e.message);}
};
window.pauseTransfer=()=>{pauseSend();stopCamera();};document.addEventListener('visibilitychange',()=>{if(document.hidden)window.pauseTransfer();});window.addEventListener('pagehide',window.pauseTransfer);
initWorker();requestAnimationFrame(tick);
