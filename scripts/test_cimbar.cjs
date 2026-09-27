// Real bundled WASM round-trip (camera optics excluded). Run with NODE_PATH
// pointing to a directory containing Playwright and an installed Chrome.
const { chromium } = require('playwright');
const http = require('http'),fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'../android/app/src/main/assets/cimbar');
const server=http.createServer((req,res)=>{const p=path.join(root,decodeURIComponent(req.url.split('?')[0]));if(!p.startsWith(root+path.sep)||!fs.existsSync(p)){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',p.endsWith('.wasm')?'application/wasm':p.endsWith('.js')?'application/javascript':p.endsWith('.css')?'text/css':'text/html');fs.createReadStream(p).pipe(res);});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({headless:true,channel:'chrome',args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try{
 const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:3});const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);await page.waitForFunction(()=>ready&&workerReady,null,{timeout:30000});
 await page.click('#sendTab');
 const result=await page.evaluate(async()=>{
  const bytes=new Uint8Array(256*1024);let seed=6330;for(let i=0;i<bytes.length;i++){seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;bytes[i]=seed&255;}
  await importFile(new File([bytes],'中文-😀.bin'));
  const gl=Module.canvas.getContext('webgl2')||Module.canvas.getContext('webgl');
  const w=Module.canvas.width,h=Module.canvas.height;
  const shot=document.createElement('canvas');shot.width=w;shot.height=h;const ctx=shot.getContext('2d');
  let frames=0,decoded=0,failures=[];const start=performance.now();
  const original=worker.onmessage;worker.onmessage=e=>{if(e.data.type==='error')failures.push(e.data.message);original(e);};
  for(;frames<200&&!recovered;frames++){
   renderFrame();
   if(frames%3===0)continue; // 33% camera erasures
   const raw=new Uint8Array(w*h*4);gl.readPixels(0,0,w,h,gl.RGBA,gl.UNSIGNED_BYTE,raw);
   const pixels=new Uint8ClampedArray(raw.length);for(let y=0;y<h;y++)pixels.set(raw.subarray((h-1-y)*w*4,(h-y)*w*4),y*w*4);
   // Use the same VideoFrame transfer/copy/decoder path as the Android camera.
   ctx.putImageData(new ImageData(pixels,w,h),0,0);
   const frame=new VideoFrame(shot,{timestamp:frames*66667});inFlight=true;worker.postMessage({frame},[frame]);
   await new Promise((resolve,reject)=>{const begin=performance.now();const poll=()=>{if(!inFlight)resolve();else if(performance.now()-begin>10000)reject(Error('Decoder timeout'));else setTimeout(poll,5);};poll();});decoded++;
  }
  const same=!!recovered&&bytes.length===recovered.bytes.length&&bytes.every((v,i)=>v===recovered.bytes[i]);
  return {same,verified:recovered?.verified,name:recovered?.name,frames,decoded,elapsedMs:Math.round(performance.now()-start),failures,canvas:[w,h]};
 });console.log('Round trip with 33% frame loss:',result);assert(result.same,'Recovered bytes differ');assert(result.verified,'SHA-256 verification missing');assert.equal(result.name,'中文-😀.bin');assert.deepEqual(result.failures,[]);
 await page.screenshot({path:'/tmp/cimbar-send.png'});
 await page.click('#play');await page.waitForTimeout(500);await page.click('#play');const sentBefore=await page.evaluate(()=>sent);await page.waitForTimeout(300);assert.equal(await page.evaluate(()=>sent),sentBefore,'Pause must remain paused');
 await page.click('#enlarge');await page.screenshot({path:'/tmp/cimbar-expanded.png'});
 await page.setViewportSize({width:844,height:390});await page.screenshot({path:'/tmp/cimbar-landscape.png'});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Horizontal overflow');
 await page.click('#enlarge');await page.click('#receiveTab');assert.equal(await page.locator('#save').isVisible(),true,'Switching tabs must retain received file');
 await page.click('#reset');await page.waitForFunction(()=>workerReady&&!recovered);assert.equal(await page.locator('#save').isVisible(),false,'Reset must clear recovered file');
 const small=await page.evaluate(async()=>{
  const results=[];switchTab('send');
  for(const length of [0,1,500,16384,16385]){
   initWorker();const observations=[];const receiveMessage=worker.onmessage;worker.onmessage=e=>{observations.push(e.data.type+':'+(e.data.result??e.data.message??''));receiveMessage(e);};await new Promise(r=>{const poll=()=>workerReady?r():setTimeout(poll,10);poll();});
   const input=new Uint8Array(length).fill(42);await importFile(new File([input],'small-'+length+'.bin'));
   const gl=Module.canvas.getContext('webgl2')||Module.canvas.getContext('webgl'),w=Module.canvas.width,h=Module.canvas.height;
   for(let i=0;i<40&&!recovered;i++){
    renderFrame();const raw=new Uint8Array(w*h*4);gl.readPixels(0,0,w,h,gl.RGBA,gl.UNSIGNED_BYTE,raw);
    const pixels=new Uint8Array(raw.length);for(let y=0;y<h;y++)pixels.set(raw.subarray((h-1-y)*w*4,(h-y)*w*4),y*w*4);
    inFlight=true;worker.postMessage({pixels,width:w,height:h},[pixels.buffer]);
    await new Promise((r,j)=>{const start=performance.now();const poll=()=>!inFlight?r():performance.now()-start>10000?j(Error('Small-file timeout')):setTimeout(poll,5);poll();});
   }
   results.push({length,observations:observations.slice(0,8),status:$('receiveStatus').textContent,recoveredLength:recovered?.bytes.length,exact:!!recovered&&recovered.bytes.length===length&&recovered.bytes.every(x=>x===42)});
  }return results;
 });console.log('Empty/tiny/compression boundaries:',small);assert(small.every(x=>x.exact));
 assert.deepEqual(errors,[]);console.log('PASS WASM encode, camera-frame decode, fountain recovery, filename, exact bytes, pause, reset, portrait/landscape layouts');
}finally{await browser.close();server.close();}})().catch(e=>{console.error(e);process.exitCode=1;server.close();});
