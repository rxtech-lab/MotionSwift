// Deliberately small, documented worker environment; no DOM or Node emulation.
globalThis.TextEncoder = class { encode(value = '') { return new Uint8Array(__ms_encode(String(value))); } };
globalThis.TextDecoder = class {
  constructor(encoding = 'utf-8') { if(!/^utf-?8$/i.test(encoding)) throw Error('TextDecoder supports UTF-8 only'); }
  decode(value = new Uint8Array()) { return __ms_decode(Array.from(new Uint8Array(value.buffer || value, value.byteOffset || 0, value.byteLength))); }
};
globalThis.atob = value => { const result=__ms_base64(String(value),true); if(result==null) throw Error('Invalid base64'); return result; };
globalThis.btoa = value => { const result=__ms_base64(String(value),false); if(result==null) throw Error('btoa requires Latin-1 input'); return result; };
globalThis.URLSearchParams = class {
  constructor(input = '') {
    this.entriesList = typeof input === 'string' ? input.replace(/^\?/, '').split('&').filter(Boolean).map(part => {
      const at=part.indexOf('='); return [at<0?part:part.slice(0,at),at<0?'':part.slice(at+1)].map(v=>decodeURIComponent(v.replace(/\+/g,' ')));
    }) : Array.isArray(input) ? input.map(pair=>pair.map(String)) : Object.entries(input).map(([k,v])=>[k,String(v)]);
  }
  append(key,value) { this.entriesList.push([String(key),String(value)]); }
  get(key) { return this.entriesList.find(pair=>pair[0]===String(key))?.[1]??null; }
  getAll(key) { return this.entriesList.filter(pair=>pair[0]===String(key)).map(pair=>pair[1]); }
  has(key) { return this.get(key)!==null; }
  delete(key) { this.entriesList=this.entriesList.filter(pair=>pair[0]!==String(key)); }
  set(key,value) { this.delete(key); this.append(key,value); }
  *[Symbol.iterator]() { yield* this.entriesList; }
  toString() { return this.entriesList.map(pair=>pair.map(v=>encodeURIComponent(v).replace(/%20/g,'+')).join('=')).join('&'); }
};
globalThis.URL = class {
  constructor(input,base='') { const result=__ms_url(String(input),String(base)); if(result.error) throw Error(result.error); Object.assign(this,result); this.searchParams=new URLSearchParams(this.search); }
  toString() { const query=this.searchParams.toString(); return this.href.split(/[?#]/)[0]+(query?'?'+query:'')+this.hash; }
  toJSON() { return this.toString(); }
};
globalThis.Headers = class {
  constructor(input={}) { this.values=new Map(); for(const [key,value] of input instanceof Headers?input: Array.isArray(input)?input:Object.entries(input)) this.set(key,value); }
  set(key,value) { this.values.set(String(key).toLowerCase(),String(value)); }
  append(key,value) { this.set(key,this.has(key)?this.get(key)+', '+value:value); }
  get(key) { return this.values.get(String(key).toLowerCase())??null; }
  has(key) { return this.values.has(String(key).toLowerCase()); }
  delete(key) { this.values.delete(String(key).toLowerCase()); }
  [Symbol.iterator]() { return this.values.entries(); }
};
globalThis.AbortController = class {
  constructor() { this.signal={aborted:false,reason:undefined}; }
  abort(reason=Error('Request aborted')) { this.signal.aborted=true; this.signal.reason=reason; }
};
globalThis.Response = class {
  constructor(body='',options={}) { this.bytes=typeof body==='string'?new TextEncoder().encode(body):new Uint8Array(body); this.status=options.status??200; this.ok=this.status>=200&&this.status<300; this.headers=new Headers(options.headers); this.url=options.url??''; this.bodyUsed=false; }
  consume() { if(this.bodyUsed) throw Error('Response body already consumed'); this.bodyUsed=true; return this.bytes; }
  text() { return Promise.resolve().then(()=>new TextDecoder().decode(this.consume())); }
  json() { return this.text().then(JSON.parse); }
  arrayBuffer() { return Promise.resolve().then(()=>this.consume().buffer); }
};
globalThis.fetch = (input,options={}) => Promise.resolve().then(()=>{
  if(options.signal?.aborted) throw options.signal.reason;
  const result=__ms_fetch(String(input),options.method||'GET',Object.fromEntries(new Headers(options.headers)),options.body==null?'':String(options.body));
  if(result.error) throw Error(result.error);
  return new Response(result.body,result);
});
