// Host SVG is a vector island. React evaluates its subtree on every sampled frame;
// only the island root participates in Yoga/editor layout. Skia owns SVG geometry.
const elements = new Set(['svg','g','defs','path','rect','circle','ellipse','line','polyline','polygon',
  'linearGradient','radialGradient','stop','clipPath','mask']);
const attributes = new Set(['id','viewBox','preserveAspectRatio','width','height','x','y','x1','x2','y1','y2',
  'cx','cy','r','rx','ry','d','points','fill','fillRule','fillOpacity','stroke','strokeWidth','strokeOpacity',
  'strokeLinecap','strokeLinejoin','strokeMiterlimit','strokeDasharray','strokeDashoffset','opacity','transform',
  'clipPath','clipRule','clipPathUnits','mask','maskUnits','maskContentUnits','gradientUnits','gradientTransform',
  'spreadMethod','offset','stopColor','stopOpacity','fx','fy','fr']);
const aliases = {viewBox:'viewBox',preserveAspectRatio:'preserveAspectRatio',gradientUnits:'gradientUnits',
  gradientTransform:'gradientTransform',spreadMethod:'spreadMethod',clipPathUnits:'clipPathUnits',
  maskUnits:'maskUnits',maskContentUnits:'maskContentUnits'};
const escape = value => String(value).replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const enums = {
  fillRule:['nonzero','evenodd'],clipRule:['nonzero','evenodd'],strokeLinecap:['butt','round','square'],
  strokeLinejoin:['miter','round','bevel'],gradientUnits:['userSpaceOnUse','objectBoundingBox'],
  clipPathUnits:['userSpaceOnUse','objectBoundingBox'],maskUnits:['userSpaceOnUse','objectBoundingBox'],
  maskContentUnits:['userSpaceOnUse','objectBoundingBox'],spreadMethod:['pad','reflect','repeat'],
};
const numeric = new Set(['width','height','x','y','x1','x2','y1','y2','cx','cy','r','rx','ry','fx','fy','fr',
  'strokeWidth','strokeDashoffset','strokeMiterlimit','offset']);
const namedColors = new Set("transparent aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen".split(" "));
const alpha = new Set(['opacity','fillOpacity','strokeOpacity','stopOpacity']);
const finite = value => Number.isFinite(value) && Math.abs(value) <= 3.402823e38;
function pathData(text) {
  const tokens=text.match(/[a-df-zA-DF-Z]|[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/g)||[];
  if(tokens.join('')!==text.replace(/[\s,]/g,'') || !/^[mM]$/.test(tokens[0]||'')) throw Error('ms/unsupported-svg-value: path data');
  const arity={m:2,l:2,h:1,v:1,c:6,s:4,q:4,t:2,a:7,z:0};
  for(let i=0;i<tokens.length;) {
    const command=tokens[i++].toLowerCase(), count=arity[command];
    if(count===undefined) throw Error('ms/unsupported-svg-value: path command');
    const start=i;
    while(i<tokens.length && !/^[a-z]$/i.test(tokens[i])) i++;
    const values=tokens.slice(start,i).map(Number);
    if(values.some(n=>!Number.isFinite(n)||Math.abs(n)>3.402823e38) ||
       (count===0 ? values.length!==0 : !values.length || values.length%count!==0)) throw Error('ms/unsupported-svg-value: path arguments');
    if(command==='a') for(let j=0;j<values.length;j+=7) {
      if(values[j]<0 || values[j+1]<0 || ![0,1].includes(values[j+3]) || ![0,1].includes(values[j+4])) throw Error('ms/unsupported-svg-value: arc arguments');
    }
  }
}
function svgTransform(text) {
  let consumed='';
  for(const match of text.matchAll(/([a-zA-Z]+)\(([^()]*)\)/g)) {
    consumed+=match[0];
    const values=match[2].trim().split(/[ ,]+/).map(Number);
    const counts={matrix:[6],translate:[1,2],scale:[1,2],rotate:[1,3],skewX:[1],skewY:[1]};
    if(!counts[match[1]]?.includes(values.length)||values.some(n=>!finite(n))) throw Error('ms/unsupported-svg-value: SVG transform');
  }
  if(!consumed || consumed.replace(/\s/g,'')!==text.replace(/\s/g,'')) throw Error('ms/unsupported-svg-value: SVG transform');
}
function validate(key,value) {
  const text=String(value);
  if (key==='d') pathData(text);
  if (['transform','gradientTransform'].includes(key)) svgTransform(text);
  if (enums[key] && !enums[key].includes(text)) throw Error('ms/unsupported-svg-value: '+key);
  if (numeric.has(key) && !/^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?(?:px|%)?$/.test(text))
    throw Error('ms/unsupported-svg-value: '+key+' requires a number, px or %');
  if (numeric.has(key) && (!finite(parseFloat(text)) ||
      (['width','height','r','rx','ry','fr','strokeWidth','strokeMiterlimit'].includes(key) && parseFloat(text)<0)))
    throw Error('ms/unsupported-svg-value: '+key+' outside supported numeric range');
  if (alpha.has(key) && (!Number.isFinite(Number(value)) || Number(value)<0 || Number(value)>1))
    throw Error('ms/unsupported-svg-value: '+key+' requires 0...1');
  if (['fill','stroke','stopColor'].includes(key) && !/^#(?:[\da-fA-F]{3}|[\da-fA-F]{4}|[\da-fA-F]{6}|[\da-fA-F]{8})$/.test(text) &&
      !namedColors.has(text.toLowerCase()) && text!=='none' && text!=='currentColor' && !/^url\(#[\w.-]+\)$/.test(text))
    throw Error('ms/unsupported-svg-value: use hex/named colors or a local paint reference');
  if (['clipPath','mask'].includes(key) && text!=='none' && !/^url\(#[\w.-]+\)$/.test(text))
    throw Error('ms/unsupported-svg-value: '+key+' requires a local fragment');
  if (key==='viewBox') {
    const parts=text.trim().split(/[ ,]+/).map(Number);
    if(parts.length!==4 || parts.some(n=>!finite(n)) || parts[2]<=0 || parts[3]<=0)
      throw Error('ms/unsupported-svg-value: viewBox');
  }
  if (key==='preserveAspectRatio' && !/^(none|x(Min|Mid|Max)Y(Min|Mid|Max)( (meet|slice))?)$/.test(text))
    throw Error('ms/unsupported-svg-value: preserveAspectRatio');
  if (['points','strokeDasharray'].includes(key)) {
    const parts=text.trim().split(/[ ,]+/).map(Number);
    if(!parts.length || parts.some(n=>!finite(n)) || (key==='points' && parts.length%2) ||
       (key==='strokeDasharray' && parts.some(n=>n<0)))
      throw Error('ms/unsupported-svg-value: '+key);
  }
}
function serialize(node, root = true) {
  if (!elements.has(node.type)) throw Error('ms/unsupported-element: inline SVG ' + node.type + '; SVG text requires a separate text contract');
  let xml = '<' + node.type + (root ? ' xmlns="http://www.w3.org/2000/svg"' : '');
  const props = {...node.props};
  if (props.style && !root) {
    for (const [key,value] of Object.entries(props.style)) {
      if (!attributes.has(key)) throw Error('ms/unsupported-css-property: SVG ' + key);
      props[key] = value;
    }
  }
  for (const [key,value] of Object.entries(props)) {
    if (['children','style','key','ref'].includes(key) || key.startsWith('data-ms-')) continue;
    if (!attributes.has(key)) throw Error('ms/unsupported-svg-attribute: ' + key);
    if (value == null) continue;
    if (!['string','number'].includes(typeof value) || (typeof value === 'number' && !Number.isFinite(value)))
      throw Error('ms/unsupported-svg-value: ' + key);
    // Resource references are local fragments only. No external images, CSS, scripts or fonts.
    if (/url\(/i.test(String(value)) && !/^url\(#[\w.-]+\)$/.test(String(value)))
      throw Error('ms/unsupported-svg-value: external SVG resource');
    validate(key,value);
    const name = aliases[key] || key.replace(/[A-Z]/g, c => '-' + c.toLowerCase());
    xml += ` ${name}="${escape(value)}"`;
  }
  return xml + '>' + node.children.map(child => serialize(child,false)).join('') + '</' + node.type + '>';
}
function host(node) {
  const src = serialize(node);
  const style = {...node.props.style};
  for (const key of ['width','height']) {
    if (style[key] == null && node.props[key] != null) {
      const raw = node.props[key];
      style[key] = typeof raw === 'string' && !raw.endsWith('px') && !raw.endsWith('%') ? Number(raw) : raw;
    }
  }
  if (style.width == null) style.width = 300;
  if (style.height == null) style.height = 150;
  return {src,style};
}
module.exports = {host, serialize};
