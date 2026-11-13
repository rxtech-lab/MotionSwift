// The portable compiler and source-edit service. Bundled into one script that runs inside
// JavaScriptCore on macOS, iOS and iPadOS (no JIT required, no Node at device time).
//
// - compile: TS/TSX → CommonJS modules with resolved dependency maps (Sucrase), after subset
//   inspection and editor source stamps (Babel parser).
// - styles/edit: classify and rewrite inline style properties of a stamped element. Every edit
//   returns its exact inverse, so undo restores the original bytes.
import {parse} from '@babel/parser';
import {transform} from 'sucrase';
import {inspect} from '../compiler/inspect.mjs';

const SOURCE = /\.(tsx|ts|jsx|js|mts|mjs|cts|cjs)$/;
const DECLARATION = /\.d\.(ts|mts|cts)$/;
const STAMPED_COMPONENTS = new Set(['AbsoluteFill', 'Img', 'Video', 'OffthreadVideo']);

function parseSource(source, file) {
  try {
    return parse(source, {sourceType: 'unambiguous', plugins: ['typescript', 'jsx'], createImportExpressions: true});
  } catch (error) {
    const loc = error.loc ? ` (${error.loc.line}:${error.loc.column + 1})` : '';
    throw Error(`${file}: ${error.message.replace(/ \(\d+:\d+\)$/, '')}${loc}`);
  }
}

function walk(node, visit) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { node.forEach(child => walk(child, visit)); return; }
  if (typeof node.type === 'string' && visit(node) === false) return;
  for (const [key, value] of Object.entries(node)) {
    if (key !== 'loc' && value && typeof value === 'object') walk(value, visit);
  }
}

const elementName = node => node.name?.type === 'JSXIdentifier' ? node.name.name : null;
const isStamped = (name, node) => !!name && (name[0] === name[0].toLowerCase() || STAMPED_COMPONENTS.has(name) ||
  node?.attributes.some(a => a.name?.name === 'data-ms-editable'));
const stampOf = (file, node) => `${file}:${node.loc.start.line}:${node.loc.start.column + 1}`;

/** Adds `data-ms-src="file:line:col"` to host elements; columns refer to the original source. */
export function stamp(source, file) {
  const inserts = [];
  walk(parseSource(source, file), node => {
    if (node.type !== 'JSXOpeningElement' || !isStamped(elementName(node), node)) return;
    if (node.attributes.some(attr => attr.name?.name === 'data-ms-src')) return;
    inserts.push([node.name.end, ` data-ms-src=${JSON.stringify(stampOf(file, node))}`]);
  });
  let output = source;
  for (const [offset, text] of inserts.sort((a, b) => b[0] - a[0])) {
    output = output.slice(0, offset) + text + output.slice(offset);
  }
  return output;
}

function normalize(path) {
  const parts = [];
  for (const part of path.split('/')) {
    if (part === '' || part === '.') continue;
    if (part === '..') { if (!parts.length) throw Error(`Import escapes the project: ${path}`); parts.pop(); } else parts.push(part);
  }
  return parts.join('/');
}

function resolve(from, specifier, files, vendor) {
  if (!specifier.startsWith('.') && !specifier.startsWith('/')) {
    if (vendor.includes(specifier)) return `vendor:${specifier}`;
    throw Error(`ms/unsupported-package: ${specifier} (imported by ${from}) is not in the precompiled vendor graph. ` +
      'Sync this project\'s module graph from a Mac (motionswift graph) or the cloud.');
  }
  const directory = from.split('/').slice(0, -1).join('/');
  const base = normalize(specifier.startsWith('/') ? specifier : `${directory}/${specifier}`);
  const candidates = [base, ...['.tsx', '.ts', '.jsx', '.js', '.mjs', '.cjs', '.json'].map(ext => base + ext),
    ...['index.tsx', 'index.ts', 'index.jsx', 'index.js'].map(name => `${base}/${name}`)];
  // TypeScript ESM style: './Scene.js' may name './Scene.tsx'.
  if (/\.(m|c)?js$/.test(base)) candidates.push(...['.tsx', '.ts'].map(ext => base.replace(/\.(m|c)?js$/, ext)));
  const found = candidates.find(candidate => Object.hasOwn(files, candidate) && !DECLARATION.test(candidate));
  if (!found) throw Error(`Cannot resolve ${specifier} from ${from}`);
  return found;
}

/**
 * input: {files: {path: source}, entry, stamp, vendor: [specifier]}
 * output: {modules: {path: {code, dependencies: {specifier: path | 'vendor:name'}}}}
 */
export function compile(inputJSON) {
  const {files, entry, stamp: stamps = false, vendor} = JSON.parse(inputJSON);
  if (!Object.hasOwn(files, entry)) throw Error(`Entry not found: ${entry}`);
  const modules = {};
  const pending = [entry];
  while (pending.length) {
    const path = pending.pop();
    if (modules[path]) continue;
    let code;
    if (path.endsWith('.json')) {
      code = `module.exports = ${JSON.stringify(JSON.parse(files[path]))};`;
    } else if (SOURCE.test(path)) {
      const source = files[path];
      parseSource(source, path); // Located syntax errors before subset inspection.
      const diagnostics = JSON.parse(inspect(source, path, true));
      if (diagnostics.length) throw Error(JSON.stringify(diagnostics));
      const typescript = /\.(tsx?|mts|cts)$/.test(path);
      const transforms = [...(typescript ? ['typescript'] : []), ...(/\.(ts|mts|cts)$/.test(path) ? [] : ['jsx']), 'imports'];
      code = transform(stamps ? stamp(source, path) : source, {
        transforms, jsxRuntime: 'automatic', jsxImportSource: '@motionswift/remotion', production: true,
        filePath: path, disableESTransforms: true,
      }).code;
    } else {
      throw Error(`Unsupported module type: ${path}`);
    }
    const dependencies = {};
    for (const match of code.matchAll(/\brequire\((['"])([^'"]+)\1\)/g)) {
      const specifier = match[2];
      if (Object.hasOwn(dependencies, specifier)) continue;
      dependencies[specifier] = resolve(path, specifier, files, vendor);
      if (!dependencies[specifier].startsWith('vendor:')) pending.push(dependencies[specifier]);
    }
    modules[path] = {code, dependencies};
  }
  return JSON.stringify({modules});
}

// MARK: Source edits

function findElement(source, src) {
  const match = /^(.*):(\d+):(\d+)$/.exec(src);
  if (!match) throw Error(`Invalid source stamp: ${src}`);
  const [, file, line, column] = match;
  let found = null;
  walk(parseSource(source, file), node => {
    if (found) return false;
    if (node.type === 'JSXOpeningElement' && node.loc.start.line === Number(line) &&
        node.loc.start.column + 1 === Number(column)) found = node;
  });
  if (!found) throw Error(`stale-source: ${src} no longer names an element; reselect it`);
  return found;
}

function styleObject(element) {
  const attribute = element.attributes.find(attr => attr.type === 'JSXAttribute' && attr.name?.name === 'style');
  if (!attribute) return null;
  const expression = attribute.value?.type === 'JSXExpressionContainer' ? attribute.value.expression : null;
  return expression?.type === 'ObjectExpression' ? expression : undefined;
}

const keyOf = property => property.type === 'ObjectProperty' && !property.computed
  ? (property.key.type === 'Identifier' ? property.key.name : property.key.type === 'StringLiteral' ? property.key.value : null)
  : null;

const ANIMATORS = new Set(['interpolate', 'spring', 'interpolateColors']);

function classify(value, source) {
  const raw = source.slice(value.start, value.end);
  switch (value.type) {
  case 'NumericLiteral': return {kind: 'static', value: value.value, raw};
  case 'StringLiteral': return {kind: 'static', value: value.value, raw};
  case 'UnaryExpression':
    if (value.operator === '-' && value.argument.type === 'NumericLiteral') return {kind: 'static', value: -value.argument.value, raw};
    break;
  case 'TemplateLiteral':
    if (!value.expressions.length) return {kind: 'static', value: value.quasis[0].value.cooked, raw};
    break;
  case 'Identifier': return {kind: 'bound', raw};
  default: break;
  }
  let animated = false;
  walk(value, node => {
    if (node.type === 'CallExpression' && ANIMATORS.has(node.callee?.name ?? node.callee?.property?.name)) animated = true;
  });
  return {kind: animated ? 'animated' : 'computed', raw};
}

// Timeline metadata stays on the original opening tag, so source stamps do not move.
const TIMELINE = 'data-ms-timeline';
function timelineAttribute(element) {
  return element.attributes.find(a => a.type === 'JSXAttribute' && a.name?.name === TIMELINE);
}
function timelineData(source, element) {
  const attr = timelineAttribute(element);
  if (!attr) return {from: 0, duration: null, keyframes: {}};
  try {
    const value = JSON.parse(source.slice(attr.value.expression.start, attr.value.expression.end));
    validateTimeline(value);
    return value;
  } catch { throw Error('refused: timeline metadata is computed or invalid; edit it in code'); }
}
function validateTimeline(value) {
  if (!Number.isInteger(value.from) || value.from < 0 ||
      (value.duration !== null && (!Number.isInteger(value.duration) || value.duration < 1)) ||
      !value.keyframes || typeof value.keyframes !== 'object' || Array.isArray(value.keyframes)) throw Error('Invalid timeline');
  for (const [key, points] of Object.entries(value.keyframes)) {
    if (!/^[A-Za-z][A-Za-z0-9]*$/.test(key) || !Array.isArray(points) || !points.length) throw Error('Invalid keyframes');
    let previous = -1;
    for (const point of points) {
      if (!Number.isInteger(point.frame) || point.frame <= previous || !Number.isFinite(point.value) ||
          !['linear', 'hold'].includes(point.easing)) throw Error('Invalid keyframe');
      previous = point.frame;
    }
  }
}

/** Source-backed object tracks. Sequence offsets are resolved only for literal sequences. */
export function timeline(source, file) {
  const tracks = [];
  const numberAttribute = (node, key, fallback) => {
    const a = node.attributes.find(a => a.name?.name === key);
    if (!a) return fallback;
    const e = a.value?.expression;
    return e?.type === 'NumericLiteral' ? e.value : undefined;
  };
  function visit(node, offset = 0, limit = null, reason = null, parentTimed = false, owner = null) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(n => visit(n, offset, limit, reason, parentTimed, owner)); return; }
    if (node.type === 'VariableDeclarator' && node.id?.type === 'Identifier') owner = node.id.name;
    if (node.type === 'FunctionDeclaration' && node.id) owner = node.id.name;
    if (node.type === 'JSXElement') {
      const opening = node.openingElement, name = elementName(opening);
      if (name === 'Sequence') {
        const from = numberAttribute(opening, 'from', 0), duration = numberAttribute(opening, 'durationInFrames', null);
        if (from === undefined || duration === undefined) reason = 'Computed Sequence timing; edit in code';
        offset += from ?? 0;
        if (duration != null) limit = Math.min(limit ?? Infinity, offset + duration);
      } else if (['Loop', 'Freeze'].includes(name) || opening.name.type === 'JSXMemberExpression') {
        reason = 'Loop, Freeze or compound component timing; edit in code';
      }
      if (isStamped(name, opening)) {
        let data, error = reason;
        try { data = timelineData(source, opening); } catch (e) { error = e.message; data = {from: 0, duration: null, keyframes: {}}; }
        if (parentTimed) error = 'Timing is controlled by an ancestor object; edit the ancestor first';
        tracks.push({src: stampOf(file, opening), label: opening.attributes.find(a => a.name?.name === 'data-ms-label')?.value?.value ?? name, owner, offset, limit, reason: error, ...data});
        parentTimed ||= !!timelineAttribute(opening);
      }
      node.children.forEach(n => visit(n, offset, limit, reason, parentTimed, owner));
      return;
    }
    for (const [key, child] of Object.entries(node)) if (key !== 'loc' && child && typeof child === 'object') {
      visit(child, offset, limit, reason, parentTimed, owner);
    }
  }
  visit(parseSource(source, file));
  return JSON.stringify(tracks);
}

function editTimeline(source, request) {
  const {src} = request, element = findElement(source, src), attr = timelineAttribute(element);
  const old = attr ? source.slice(attr.start, attr.end) : '';
  const data = request.value;
  if (data) {
    validateTimeline(data);
    const object = styleObject(element);
    for (const key of Object.keys(data.keyframes)) {
      const property = object?.properties.find(p => keyOf(p) === key);
      if (!object || object.properties.some(p => keyOf(p) === null) || !property ||
          property.shorthand || classify(property.value, source).kind !== 'static' ||
          typeof classify(property.value, source).value !== 'number') {
        throw Error(`refused: ${key} must be an explicit static numeric style to animate`);
      }
    }
  }
  // raw is used only by byte-exact inverse operations.
  const text = request.raw ?? (data ? `${TIMELINE}={${JSON.stringify(data)}}` : '');
  let start = attr?.start ?? element.name.end, end = attr?.end ?? start;
  let replacement = text;
  if (!attr && text) replacement = ' ' + text;
  if (attr && !text && source[start - 1] === ' ') start--;
  return JSON.stringify({source: splice(source, start, end, replacement),
    inverse: {op: 'setTimeline', src, key: 'timeline', raw: old}});
}

/** Inline style properties of the element at `src`, classified for editing. */
export function styles(source, src) {
  const element = findElement(source, src);
  const object = styleObject(element);
  // Declarations are editor metadata, never evaluated as code or applied as styles.
  const attribute = element.attributes.find(attr => attr.name?.name === 'data-ms-properties');
  const declarations = [];
  const definition = attribute?.value?.expression;
  if (definition?.type === 'ObjectExpression') {
    for (const property of definition.properties) {
      const key = keyOf(property);
      if (!key || property.value?.type !== 'ObjectExpression') continue;
      const descriptor = {key};
      for (const field of property.value.properties) {
        if (['label', 'group'].includes(keyOf(field)) && field.value?.type === 'StringLiteral')
          descriptor[keyOf(field)] = field.value.value;
      }
      declarations.push(descriptor);
    }
  }
  if (!object) return JSON.stringify({editable: object === null, properties: [], declarations});
  const properties = object.properties.map((property, index) => {
    const key = keyOf(property);
    if (key === null) return {key: source.slice(property.start, property.end), kind: 'computed'};
    if (object.properties.slice(index + 1).some(p => keyOf(p) === null) ||
        object.properties.slice(0, index).some(p => keyOf(p) === key))
      return {key, kind: 'computed', raw: source.slice(property.value.start, property.value.end)};
    if (property.shorthand) return {key, kind: 'bound', raw: key};
    return {key, ...classify(property.value, source)};
  });
  // A duplicate key has the value of its final occurrence.
  return JSON.stringify({editable: true, properties: properties.filter((p, i) =>
    !properties.slice(i + 1).some(next => next.key === p.key)), declarations});
}

function literal(value, source, previous) {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw Error('Style numbers must be finite');
    return String(Number(value.toFixed(3)));
  }
  if (typeof value !== 'string') throw Error('Style values must be numbers or strings');
  const quote = previous?.[0] === '"' || previous?.[0] === '\''
    ? previous[0]
    : (source.split('"').length > source.split('\'').length ? '"' : '\'');
  return quote + value.replaceAll('\\', '\\\\').replaceAll(quote, `\\${quote}`).replaceAll('\n', '\\n') + quote;
}

/** Where and how to add a property, following the object's existing layout. Returns [offset, text, lead]. */
function insertion(source, object, property) {
  const last = object.properties.at(-1);
  if (!last) {
    const inner = source.slice(object.start + 1, object.end - 1);
    if (/^[ \t]+$/.test(inner)) return [object.end - 1, `${property} `, 0];
    return [object.start + 1, property, 0];
  }
  const tail = source.slice(last.end, object.end - 1);
  if (!tail.includes('\n')) return [last.end, `, ${property}`, 2];
  const lineStart = source.lastIndexOf('\n', last.start) + 1;
  const indent = /^[ \t]*/.exec(source.slice(lineStart))[0];
  if (/^\s*,/.test(tail)) {
    // Trailing comma: add a new line after the last property's line, keeping its comment there.
    const lineEnd = source.indexOf('\n', last.end);
    return [lineEnd, `\n${indent}${property},`, 1 + indent.length];
  }
  return [last.end, `,\n${indent}${property}`, 2 + indent.length];
}

const splice = (source, start, end, text) => source.slice(0, start) + text + source.slice(end);

/**
 * request: {op: 'setStyle', src, key, value | raw} | {op: 'removeStyle', src, key}
 *   | {op: 'insertStyle', src, key, index, text, offset} (the inverse of removeStyle)
 * result: {source, inverse}
 */
export function edit(source, requestJSON) {
  const request = JSON.parse(requestJSON);
  const {op, src, key} = request;
  if (op === 'setTimeline') return editTimeline(source, request);
  if (!src || typeof key !== 'string' || !/^[A-Za-z][A-Za-z0-9]*$/.test(key)) throw Error('Invalid edit request');
  const object = styleObject(findElement(source, src));
  if (!object) {
    throw Error(object === null ? `refused: ${src} has no style object; add style={{}} in code first`
      : `refused: the style of ${src} is computed; edit it in code`);
  }
  const index = object.properties.findIndex(property => keyOf(property) === key);
  const property = object.properties[index];
  if (property && object.properties.slice(index + 1).some(p => keyOf(p) === key || keyOf(p) === null))
    throw Error(`refused: ${key} may be overridden by a later style property; edit it in code`);
  if (!property && object.properties.some(p => keyOf(p) === null) && op === 'setStyle')
    throw Error(`refused: ${key} may be supplied by a spread or computed property; edit it in code`);
  if (op === 'setStyle') {
    if (property) {
      if (property.shorthand) throw Error(`refused: ${key} is bound to a variable; edit its definition`);
      const current = classify(property.value, source);
      if (current.kind !== 'static') {
        throw Error(`refused: ${key} is ${current.kind}${current.kind === 'animated' ? '; edit its keyframes on the timeline' : '; edit it in code'}`);
      }
      const text = request.raw ?? literal(request.value, source, current.raw);
      return JSON.stringify({source: splice(source, property.value.start, property.value.end, text),
        inverse: {op: 'setStyle', src, key, raw: current.raw}});
    }
    const [position, text, lead] = insertion(source, object, `${key}: ${request.raw ?? literal(request.value, source)}`);
    return JSON.stringify({source: splice(source, position, position, text), inverse: {op: 'removeStyle', src, key, text, lead}});
  }
  if (op === 'removeStyle') {
    if (!property) throw Error(`${key} is not set on ${src}`);
    if (request.text !== undefined) {
      // The inverse of an insertion: remove exactly the inserted text.
      const start = property.start - request.lead;
      if (source.slice(start, start + request.text.length) !== request.text) throw Error(`stale-source: ${src} changed; reselect it`);
      return JSON.stringify({source: splice(source, start, start + request.text.length, ''),
        inverse: {op: 'insertStyle', src, key, index, text: request.text, offset: start - object.start}});
    }
    const raw = source.slice(property.value.start, property.value.end);
    const previous = object.properties[index - 1];
    const next = object.properties[index + 1];
    // Remove the separator that an insertion added, so remove ∘ insert is byte-exact.
    const lone = source[property.start - 1] === ' ' && source[property.end] === ' ' ? 1 : 0;
    const [start, end] = previous ? [previous.end, property.end] : next ? [property.start, next.start] : [property.start, property.end + lone];
    return JSON.stringify({source: splice(source, start, end, ''),
      inverse: {op: 'insertStyle', src, key, index, text: source.slice(start, end), offset: start - object.start}});
  }
  if (op === 'insertStyle') {
    // The exact inverse of removeStyle: puts the removed text back where it was.
    if (property) throw Error(`${key} is already set on ${src}`);
    const {index: at, text, offset} = request;
    const previous = object.properties[at - 1];
    const next = object.properties[at];
    const position = previous ? previous.end : next ? next.start : object.start + offset;
    return JSON.stringify({source: splice(source, position, position, text), inverse: {op: 'removeStyle', src, key}});
  }
  throw Error(`Unsupported edit operation: ${op}`);
}
