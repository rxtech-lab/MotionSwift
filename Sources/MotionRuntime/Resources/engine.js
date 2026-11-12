// A fresh VM per sampled frame prevents state and random values leaking between frames.
globalThis.process = {env: {NODE_ENV: 'production'}};
globalThis.console = {log() {}, warn() {}, error() {}};
const tasks = new Map();
let taskID = 0;
globalThis.setTimeout = (callback, delay = 0) => {
  if (delay > 0) throw Error('Delayed timers are not supported by the Phase 0 runtime');
  const id = ++taskID; tasks.set(id, callback); return id;
};
globalThis.clearTimeout = id => tasks.delete(id);
function drainTasks() {
  let count = 0;
  while (tasks.size) {
    if (++count > 1000) throw Error('React did not settle after 1000 tasks');
    const [id, callback] = tasks.entries().next().value;
    tasks.delete(id); callback();
  }
}
globalThis.performance = {now: () => 0};
let seed = 1;
Math.random = () => { seed = (Math.imul(seed,1664525)+1013904223)|0; return (seed>>>0)/4294967296; };
const RealDate = Date;
globalThis.Date = class extends RealDate {
  constructor(...args) { super(...(args.length ? args : [0])); }
  static now() { return 0; }
};
globalThis.__ms_start = function() {
  const React = __ms_require(__ms_ids.react);
  const Reconciler = __ms_require(__ms_ids.reconciler);
  const shim = __ms_require(__ms_ids.shim);
  const append = (parent,child) => { const i=parent.children.indexOf(child); if(i>=0)parent.children.splice(i,1); parent.children.push(child); };
  const remove = (parent,child) => { const i=parent.children.indexOf(child); if(i>=0)parent.children.splice(i,1); };
  const reconciler = Reconciler({
    now: () => 0, supportsMutation: true, isPrimaryRenderer: true,
    getRootHostContext: () => ({}), getChildHostContext: () => ({}),
    getPublicInstance: x=>x, prepareForCommit: () => null, resetAfterCommit() {},
    shouldSetTextContent: () => false,
    createInstance: (type,props) => ({type,props,children: []}),
    createTextInstance: text => ({type: '#text',text,props: {},children: []}),
    appendInitialChild: append, appendChild: append, appendChildToContainer: append,
    removeChild: remove, removeChildFromContainer: remove,
    insertBefore(parent,child,before) { remove(parent,child); parent.children.splice(parent.children.indexOf(before),0,child); },
    insertInContainerBefore(parent,child,before) { this.insertBefore(parent,child,before); },
    finalizeInitialChildren: () => false, prepareUpdate: () => true,
    commitUpdate: (node,payload,type,oldProps,props) => { node.props=props; },
    commitTextUpdate: (node,oldText,text) => { node.text=text; },
    clearContainer: node => { node.children=[]; }, detachDeletedInstance() {},
    scheduleTimeout: setTimeout, cancelTimeout: clearTimeout, noTimeout: -1,
  });
  const render = element => {
    const container={children: []};
    const root=reconciler.createContainer(container,0,null,false,null,'',e=>{throw e;},null);
    reconciler.flushSync(()=>reconciler.updateContainer(element,root,null,null));
    drainTasks();
    return container;
  };
  __ms_require(__ms_ids.entry);
  if (!globalThis.__ms_root) throw Error('Entry must call registerRoot');
  const catalog=[];
  const visit = node => {
    if(node.type==='ms-composition') catalog.push(node.props);
    else node.children.forEach(visit);
  };
  render(React.createElement(__ms_root)).children.forEach(visit);
  globalThis.__ms_catalog = () => JSON.stringify(catalog.map(({id,width,height,fps,durationInFrames})=>({id,width,height,fps,durationInFrames})));
  globalThis.__ms_frame = (id,frame,props) => {
    const comp=catalog.find(item=>item.id===id);
    if(!comp) throw Error('Unknown composition: '+id);
    if(comp.calculateMetadata) throw Error('calculateMetadata is not supported in Phase 0');
    const element=React.createElement(shim.__Config.Provider,{value:comp},
      React.createElement(shim.__Frame.Provider,{value:frame},React.createElement(comp.component,{...comp.defaultProps,...JSON.parse(props)})));
    const serialize = node => ({type:node.type,style:node.props.style||{},text:node.text||null,children:node.children.map(serialize)});
    return JSON.stringify({type:'div',style:{},text:null,children:render(element).children.map(serialize)});
  };
};
