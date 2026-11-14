// One worker owns this context. Only vendor code and the committed host tree survive a sample.
globalThis.process = {env: {NODE_ENV: 'production'}};
globalThis.console = {log() {}, warn() {}, error() {}};
const RealDate = Date;
let clock = 0, seed = 1, taskID = 0, handleID = 0;
let tasks = new Map(), handles = new Map(), failure = null, rejected = new Map();
let sample = 'catalog';
const fail = error => { failure = error instanceof Error ? error : Error(String(error)); };
const NativePromise = Promise;
// Observe rejected promises without swallowing errors or reporting caught rejections.
class RuntimePromise extends NativePromise {
  constructor(executor) {
    let resolveValue, rejectValue;
    super((resolve, reject) => { resolveValue = resolve; rejectValue = reject; });
    this.handled = false;
    NativePromise.prototype.then.call(this, undefined, error => { rejected.set(this, error); });
    try { executor(resolveValue, rejectValue); } catch (error) { rejectValue(error); }
  }
  static get [Symbol.species]() { return NativePromise; }
  then(resolve, reject) { this.handled = true; return new RuntimePromise((yes, no) => {
    NativePromise.prototype.then.call(this, resolve, reject).then(yes, no);
  }); }
}
globalThis.Promise = RuntimePromise;
globalThis.setTimeout = (callback, delay = 0, ...args) => {
  if (typeof callback !== 'function') throw Error('setTimeout requires a function');
  const id = ++taskID;
  tasks.set(id, {callback: () => callback(...args), due: clock + Math.max(0, Number(delay) || 0)});
  return id;
};
globalThis.clearTimeout = id => tasks.delete(id);
globalThis.setInterval = (callback, delay = 0, ...args) => {
  const id = ++taskID, interval = Math.max(1, Number(delay) || 0);
  tasks.set(id, {callback: () => callback(...args), due: clock + interval, interval});
  return id;
};
globalThis.clearInterval = clearTimeout;
globalThis.queueMicrotask = callback => NativePromise.resolve().then(() => {
  try { callback(); } catch (error) { fail(error); }
});
globalThis.performance = {now: () => 0};
Math.random = () => { seed = (Math.imul(seed,1664525)+1013904223)|0; return (seed>>>0)/4294967296; };
globalThis.Date = class extends RealDate {
  constructor(...args) { super(...(args.length ? args : [0])); }
  static now() { return 0; }
};
globalThis.structuredClone = value => JSON.parse(JSON.stringify(value));
globalThis.__ms_delayRender = (label = 'unlabelled', options = {}) => {
  const timeout = options.timeoutInMilliseconds ?? globalThis.__ms_timeout;
  if (!(timeout > 0 && Number.isFinite(timeout))) throw Error('delayRender timeout must be positive and finite');
  const id = ++handleID;
  handles.set(id, {label, deadline: clock + timeout, stack: new Error().stack});
  return id;
};
globalThis.__ms_continueRender = id => {
  if (!handles.delete(id)) throw Error('continueRender: unknown or already completed handle ' + id + ' (' + sample + ')');
};
globalThis.__ms_cancelRender = fail;
function resetLifecycle() {
  tasks.clear(); handles.clear(); rejected.clear(); failure = null; clock = 0; seed = 1;
}
function step() {
  for (const [promise, error] of rejected) if (!promise.handled) fail(error);
  if (failure) throw Error(sample + ': ' + failure.message + '\n' + (failure.stack || ''));
  const pending = [...handles.values()].sort((a,b) => a.deadline-b.deadline)[0];
  const next = [...tasks.entries()].sort((a,b) => a[1].due-b[1].due || a[0]-b[0])[0];
  if (pending && (!next || next[1].due >= pending.deadline)) {
    throw Error(sample + ': delayRender timed out: "' + pending.label + '" at ' + pending.deadline + 'ms. Call continueRender(handle) after loading, or cancelRender(error).\n' + pending.stack);
  }
  if (next) {
    const [id, task] = next; clock = task.due;
    if (task.interval) task.due += task.interval; else tasks.delete(id);
    try { task.callback(); } catch (error) { fail(error); }
    return false;
  }
  return handles.size === 0;
}
globalThis.__ms_start = function() {
  const React = __ms_require(__ms_ids.react);
  const Reconciler = __ms_require(__ms_ids.reconciler);
  const shim = __ms_require(__ms_ids.shim);
  const append = (parent,child) => { const i=parent.children.indexOf(child); if(i>=0)parent.children.splice(i,1); parent.children.push(child); };
  const remove = (parent,child) => { const i=parent.children.indexOf(child); if(i>=0)parent.children.splice(i,1); };
  const insert = (parent,child,before) => { remove(parent,child); parent.children.splice(parent.children.indexOf(before),0,child); };
  const reconciler = Reconciler({
    now: () => 0, supportsMutation: true, isPrimaryRenderer: true,
    getRootHostContext: () => ({}), getChildHostContext: () => ({}),
    getPublicInstance: x=>x, prepareForCommit: () => null, resetAfterCommit() {},
    shouldSetTextContent: () => false,
    createInstance: (type,props) => ({type,props,children: []}),
    createTextInstance: text => ({type: '#text',text,props: {},children: []}),
    appendInitialChild: append, appendChild: append, appendChildToContainer: append,
    removeChild: remove, removeChildFromContainer: remove,
    insertBefore: insert, insertInContainerBefore: insert,
    finalizeInitialChildren: () => false, prepareUpdate: () => true,
    commitUpdate: (node,payload,type,oldProps,props) => { node.props=props; },
    commitTextUpdate: (node,oldText,text) => { node.text=text; },
    clearContainer: node => { node.children=[]; }, detachDeletedInstance() {},
    scheduleTimeout: setTimeout, cancelTimeout: clearTimeout, noTimeout: -1,
  });
  let root, container, catalog = [], retained = new Map();
  const render = element => {
    container={type:'div',props:{},children: []};
    root=reconciler.createContainer(container,0,null,false,null,'',fail,null);
    reconciler.flushSync(()=>reconciler.updateContainer(element,root,null,null));
    reconciler.flushPassiveEffects();
    return container;
  };
  const loadCatalog = () => {
    __ms_require(__ms_ids.entry);
    if (!globalThis.__ms_root) throw Error('Entry must call registerRoot');
    catalog=[];
    const visit = node => {
      if(node.type==='ms-composition') catalog.push(node.props);
      else node.children.forEach(visit);
    };
    render(React.createElement(__ms_root)).children.forEach(visit);
    reconciler.flushSync(()=>reconciler.updateContainer(null,root,null,null));
    reconciler.flushPassiveEffects(); root=null;
  };
  loadCatalog();
  globalThis.__ms_catalog = () => JSON.stringify(catalog.map(({id,width,height,fps,durationInFrames})=>({id,width,height,fps,durationInFrames})));
  globalThis.__ms_begin = (id,frame,props) => {
    if (root) {
      reconciler.flushSync(()=>reconciler.updateContainer(null,root,null,null));
      reconciler.flushPassiveEffects(); root=null;
    }
    resetLifecycle(); sample = 'Composition "' + id + '", frame ' + frame;
    // User modules and React state reset on every sample; vendor code is immutable and retained.
    __ms_resetModules(); loadCatalog();
    const comp=catalog.find(item=>item.id===id);
    if(!comp) throw Error('Unknown composition: '+id);
    if(comp.calculateMetadata) throw Error('calculateMetadata is not supported');
    render(React.createElement(shim.__Config.Provider,{value:comp},
      React.createElement(shim.__Frame.Provider,{value:frame},React.createElement(comp.component,{...comp.defaultProps,...JSON.parse(props)}))));
  };
  globalThis.__ms_step = () => {
    reconciler.flushPassiveEffects();
    return step();
  };
  globalThis.__ms_pending = () => [...handles.values()].map(h => h.label + '\n' + h.stack).join('\n');
  globalThis.__ms_invalidate = () => { retained.clear(); };
  globalThis.__ms_commit = () => {
    const next = new Map(), ops = [];
    const visit = (node, path) => {
      // A <ThreeCanvas> commits its R3F subtree as one scene description instead of layout children.
      const scene = typeof node.props.__msScene === 'function' ? node.props.__msScene(node) : null;
      const svg = node.type === "svg" ? shim.__svgHost(node) : null;
      const children = scene !== null || svg !== null ? [] : node.children.map((child,index) => { const id=path+'.'+index; visit(child,id); return id; });
      const data = {type:svg ? "ms-svg" : node.type,style:svg ? svg.style : node.props.style||{},text:node.text??null,src:svg ? svg.src : node.props.src??null,source:node.props['data-ms-src']??null,media:node.props['data-ms-media']??null,scene,editor:typeof node.props['data-ms-editor']==='string'?node.props['data-ms-editor']:null};
      const old = retained.get(path);
      // Copy values: style objects may be mutated by user code on a subsequent render.
      const copy = JSON.parse(JSON.stringify(data));
      if (!old || old.data.type !== copy.type) ops.push(['create',path,copy]);
      else {
        const patch={};
        for (const key of ['text','src','source','media','scene','editor']) if(JSON.stringify(old.data[key])!==JSON.stringify(copy[key])) patch[key]=copy[key];
        const style={};
        for(const key of [...new Set([...Object.keys(old.data.style),...Object.keys(copy.style)])].sort()) {
          if(JSON.stringify(old.data.style[key])!==JSON.stringify(copy.style[key])) style[key]=copy.style[key]??null;
        }
        if(Object.keys(style).length) patch.style=style;
        if(Object.keys(patch).length) ops.push(['patch',path,patch]);
      }
      if(!old || old.data.type!==copy.type || JSON.stringify(old.children)!==JSON.stringify(children)) ops.push(['children',path,children]);
      next.set(path,{data:copy,children});
    };
    visit(container,'0');
    for(const path of retained.keys()) if(!next.has(path)) ops.push(['delete',path]);
    retained=next;
    return ops;
  };
};
