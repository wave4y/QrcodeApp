'use strict';
// Each receiver owns one WASM instance. Image decoding, fountain recovery and
// decompression stay off the UI thread; no unbounded queue of camera images.
const buffers = new Map();
let complete = false, received = 0, first = 0;
var Module = {print:()=>{}, printErr:()=>{}, onRuntimeInitialized(){
 Module._cimbard_configure_decode(68);
 postMessage({type:'ready'});
}, onAbort(){postMessage({type:'error',message:'离线解码器启动失败，请重新识别'});}};
function alloc(name,size){
 let b=buffers.get(name);
 if(!b || b.size<size){if(b)Module._free(b.ptr);b={ptr:Module._malloc(size),size};buffers.set(name,b);}
 if(!b.ptr)throw Error('手机可用内存不足');return b.ptr;
}
function report(){const p=alloc('report',4096),n=Module._cimbard_get_report(p,4096);try{return JSON.parse(new TextDecoder().decode(Module.HEAPU8.subarray(p,p+n)));}catch(_){return [];}}
async function finish(id){
 const p=alloc('name',1024),n=Module._cimbard_get_filename(id,p,1024);
 if(n<0)throw Error('文件恢复失败，请重新识别');
 let name=n?new TextDecoder().decode(Module.HEAPU8.subarray(p,p+n)):'received.bin';
 name=name.replace(/\\/g,'/').split('/').pop().replace(/[\x00-\x1f\x7f]/g,'_')||'received.bin';
 const size=Module._cimbard_get_decompress_bufsize(),ptr=alloc('decompress',size),chunks=[];let total=0;
 for(;;){const len=Module._cimbard_decompress_read(id,ptr,size);if(len<0)throw Error('解压校验失败，请重新识别');if(!len)break;total+=len;if(total>32*1024*1024)throw Error('接收文件超过 32 MB 限制');chunks.push(Module.HEAPU8.slice(ptr,ptr+len));}
 let bytes=new Uint8Array(total);let pos=0;for(const chunk of chunks){bytes.set(chunk,pos);pos+=chunk.length;}
 let verified=false;
 if(bytes.length>=8 && new TextDecoder().decode(bytes.subarray(0,8))==='CMBAPP01'){
  if(bytes.length<556 || new DataView(bytes.buffer).getUint32(8,false)!==bytes.length-556)throw Error('文件长度校验失败，请重新识别');
  const content=bytes.slice(556),hash=new Uint8Array(await crypto.subtle.digest('SHA-256',content));
  if(!hash.every((v,i)=>v===bytes[12+i]))throw Error('文件完整性校验失败，请重新识别');
  bytes=content;verified=true;
 }
 complete=true;postMessage({type:'complete',name,bytes,verified,received,elapsed:performance.now()-first},[bytes.buffer]);
}
self.onmessage=async ({data})=>{
 if(complete){data.frame?.close();postMessage({type:'idle'});return;}
 const start=performance.now();
 try{
 let pixels=data.pixels,width=data.width,height=data.height,format=4;
 if(data.frame){const frame=data.frame;try{
  width=frame.codedWidth;height=frame.codedHeight;
  // Request tightly packed full planes explicitly; camera row strides vary.
  let opts={rect:{x:0,y:0,width,height}};
  if(frame.format==='I420' && width%2===0 && height%2===0){format=420;opts.layout=[{offset:0,stride:width},{offset:width*height,stride:width/2},{offset:width*height*5/4,stride:width/2}];}
  else if(frame.format==='NV12' && width%2===0 && height%2===0){format=12;opts.layout=[{offset:0,stride:width},{offset:width*height,stride:width}];}
  else{opts.format='RGBA';opts.layout=[{offset:0,stride:width*4}];}
  pixels=new Uint8Array(frame.allocationSize(opts));await frame.copyTo(pixels,opts);
 }finally{frame.close();}}
 if(!pixels || width*height>4096*4096)throw Error('相机图像尺寸无效');
 const ip=alloc('image',pixels.byteLength),cap=Module._cimbard_get_bufsize(),fp=alloc('fountain',cap);
 Module.HEAPU8.set(pixels,ip);
 const len=Module._cimbard_scan_extract_decode(ip,width,height,format,fp,cap);
 if(len>0){if(!first)first=performance.now();received+=len;
  const result=Module._cimbard_fountain_decode(fp,len),progress=report();
  if(result>0){await finish(Number(BigInt(result)&0xffffffffn));return;}
  if(result<0)throw Error('接收数据无法恢复，请重新识别');
  postMessage({type:'progress',progress,received,elapsed:performance.now()-first,decodeMs:performance.now()-start});
 }else postMessage({type:'idle',result:len,decodeMs:performance.now()-start});
 }catch(e){postMessage({type:'error',message:String(e.message||e)});}
};
importScripts('cimbar_js.2026-08-21T2336.js');
