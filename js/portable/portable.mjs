// The portable compiler and source-edit service. Bundled into one script that runs inside
// JavaScriptCore on macOS, iOS and iPadOS (no JIT required, no Node at device time).
//
// - compile: TS/TSX → CommonJS modules with resolved dependency maps (Sucrase), after subset
//   inspection and editor source stamps (Babel parser).
// - styles/edit: classify and rewrite inline style properties of a stamped element. Every edit
//   returns its exact inverse, so undo restores the original bytes.
import {parse} from '@babel/parser';
import {transform} from 'sucrase';
import {decode, encode} from '@jridgewell/sourcemap-codec';
import {inspect} from '../compiler/inspect.mjs';
import threeEdit from '../remotion-shim/three-edit.js';
import mapEdit from '../remotion-shim/map-edit.js';

// Prop domains edit component props (never CSS) through a shared field table.
const DOMAINS = {three: threeEdit, map: mapEdit};
const domainOf = type => threeEdit.isThree(type) ? 'three' : mapEdit.isMap(type) ? 'map' : null;

const SOURCE = /\.(tsx|ts|jsx|js|mts|mjs|cts|cjs)$/;
const DECLARATION = /\.d\.(ts|mts|cts)$/;
const STAMPED_COMPONENTS = new Set(['AbsoluteFill', 'Img', 'Video', 'OffthreadVideo', 'ThreeCanvas',
  'MapView', 'MapRoute', 'MapMarker']);

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
function stampEdits(source, file) {
  const inserts = [];
  walk(parseSource(source, file), node => {
    if (node.type !== 'JSXOpeningElement' || !isStamped(elementName(node), node)) return;
    if (node.attributes.some(attr => attr.name?.name === 'data-ms-src')) return;
    inserts.push([node.name.end, ` data-ms-src=${JSON.stringify(stampOf(file, node))}`]);
  });
  return inserts;
}

export function stamp(source, file) {
  let output = source;
  for (const [offset, text] of stampEdits(source, file).sort((a, b) => b[0] - a[0])) {
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

// Parse JSONC without evaluating project code. Comments and trailing commas are allowed.
function jsonConfig(text) {
  let clean = '', string = false, escape = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i], next = text[i + 1];
    if (string) { clean += c; if (escape) escape = false; else if (c === '\\') escape = true; else if (c === '"') string = false; }
    else if (c === '"') { string = true; clean += c; }
    else if (c === '/' && next === '/') { while (i < text.length && text[i] !== '\n') i++; clean += '\n'; }
    else if (c === '/' && next === '*') { i += 2; while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++; i++; clean += ' '; }
    else clean += c;
  }
  // Remove trailing commas only after comments have been removed, and never inside strings.
  let output = ''; string = false; escape = false;
  for (let i = 0; i < clean.length; i++) {
    const c = clean[i];
    if (string) { output += c; if (escape) escape = false; else if (c === '\\') escape = true; else if (c === '"') string = false; }
    else if (c === '"') { string = true; output += c; }
    else if (c !== ',' || !/^\s*[}\]]/.test(clean.slice(i + 1))) output += c;
  }
  return JSON.parse(output);
}

export function configuration(inputJSON) {
  const files = JSON.parse(inputJSON);
  function read(path, seen = new Set()) {
    if (seen.has(path)) throw Error(`Circular tsconfig extends: ${path}`);
    seen.add(path);
    const config = jsonConfig(files[path] ?? '{}'), dir = path.split('/').slice(0, -1).join('/');
    let parent = {};
    if (config.extends && config.extends !== '@motionswift/tsconfig') {
      if (!config.extends.startsWith('.')) throw Error(`${path}: unsupported package tsconfig extends ${config.extends}; use a project-relative config`);
      let base = normalize(`${dir}/${config.extends}`);
      if (!Object.hasOwn(files, base)) base += '.json';
      if (!Object.hasOwn(files, base)) throw Error(`${path}: cannot resolve extends ${config.extends}`);
      parent = read(base, seen);
    }
    const own = config.compilerOptions ?? {}, result = {...parent};
    if (own.baseUrl != null) result.baseUrl = normalize(`${dir}/${own.baseUrl}`);
    if (own.paths) {
      result.paths = Object.fromEntries(Object.entries(own.paths).map(([key, values]) =>
        [key, values.map(value => normalize(`${result.baseUrl ?? dir}/${value}`))]));
    }
    return result;
  }
  return JSON.stringify(read('tsconfig.json'));
}

function resolve(from, specifier, files, vendor, options) {
  const exists = path => Object.hasOwn(files, path) && !DECLARATION.test(path);
  function probe(base) {
    // TypeScript extension substitution precedes the literal JavaScript file.
    const substitutions = base.endsWith('.mjs') ? ['.mts'] : base.endsWith('.cjs') ? ['.cts']
      : base.endsWith('.js') ? ['.ts', '.tsx', '.jsx'] : [];
    const candidates = [...substitutions.map(ext => base.replace(/\.(m|c)?js$/, ext)), base,
      ...['.ts', '.tsx', '.mts', '.cts', '.js', '.jsx', '.mjs', '.cjs', '.json'].map(ext => base + ext),
      ...['index.ts', 'index.tsx', 'index.js', 'index.jsx', 'index.mts', 'index.cts', 'index.mjs', 'index.cjs'].map(name => `${base}/${name}`)];
    return candidates.find(exists);
  }
  if (!specifier.startsWith('.') && !specifier.startsWith('/')) {
    // Vendor identities cannot be replaced by user aliases.
    if (vendor.includes(specifier)) return `vendor:${specifier}`;
    const paths = options.paths ?? {};
    const keys = Object.keys(paths).filter(key => key === specifier || (key.includes('*') &&
      specifier.length >= key.length - 1 && specifier.startsWith(key.split('*')[0]) && specifier.endsWith(key.split('*')[1])))
      .sort((a, b) => (a === specifier ? -1 : b === specifier ? 1 :
        b.split('*')[0].length - a.split('*')[0].length || b.length - a.length || a.localeCompare(b)));
    if (keys.length) {
      const key = keys[0], wildcard = key.includes('*') ? specifier.slice(key.split('*')[0].length,
        specifier.length - key.split('*')[1].length) : '';
      for (const target of paths[key]) { const found = probe(normalize(target.replace('*', wildcard))); if (found) return found; }
    }
    if (options.baseUrl != null) { const found = probe(normalize(`${options.baseUrl}/${specifier}`)); if (found) return found; }
    throw Error(`ms/unsupported-package: ${specifier} (imported by ${from}) is not in the precompiled vendor graph. ` +
      'Sync this project\'s module graph from a Mac (motionswift graph) or the cloud.');
  }
  const directory = from.split('/').slice(0, -1).join('/');
  const found = probe(normalize(specifier.startsWith('/') ? specifier : `${directory}/${specifier}`));
  if (!found) throw Error(`Cannot resolve ${specifier} from ${from}`);
  return found;
}

export function importLocations(inputJSON) {
  const locations = [];
  for (const [file, source] of Object.entries(JSON.parse(inputJSON))) {
    if (!SOURCE.test(file) || DECLARATION.test(file)) continue;
    walk(parseSource(source, file), node => {
      const literal = ['ImportDeclaration', 'ExportNamedDeclaration', 'ExportAllDeclaration'].includes(node.type)
        ? node.source : node.type === 'CallExpression' && node.callee?.name === 'require' ? node.arguments[0] : null;
      if (literal?.type === 'StringLiteral') locations.push({file, specifier: literal.value,
        line: literal.loc.start.line, col: literal.loc.start.column + 1});
    });
  }
  return JSON.stringify(locations);
}

const transformCache = new Map();
export function clearCache() { transformCache.clear(); return '{}'; }

/** SHA-256 keys are supplied by the Swift host; cached transforms never contain resolved edges. */
export function compile(inputJSON) {
  const {files, hashes = {}, version = '', entry, stamp: stamps = false, vendor} = JSON.parse(inputJSON);
  const options = JSON.parse(configuration(JSON.stringify(files)));
  if (!Object.hasOwn(files, entry)) throw Error(`Entry not found: ${entry}`);
  const modules = {}, pending = [entry];
  let hits = 0, misses = 0;
  while (pending.length) {
    const path = pending.pop();
    if (modules[path]) continue;
    const source = files[path], key = JSON.stringify([path, hashes[path] ?? source, stamps, version, options]);
    let output = transformCache.get(key);
    if (output) hits++;
    else {
      misses++;
      if (path.endsWith('.json')) output = {code: `module.exports = ${JSON.stringify(JSON.parse(source))};`};
      else if (SOURCE.test(path)) {
        const ast = parseSource(source, path);
        const diagnostics = JSON.parse(inspect(source, path, true));
        if (diagnostics.length) throw Error(JSON.stringify(diagnostics));
        const typescript = /\.(tsx?|mts|cts)$/.test(path);
        const transforms = [...(typescript ? ['typescript'] : []), ...(/\.(ts|mts|cts)$/.test(path) ? [] : ['jsx']), 'imports'];
        const input = stamps ? stamp(source, path) : source;
        const result = transform(input, {
          transforms, jsxRuntime: 'automatic', jsxImportSource: '@motionswift/remotion', production: true,
          filePath: path, disableESTransforms: true, sourceMapOptions: {compiledFilename: path + '.js'},
        });
        const map = result.sourceMap;
        // Stamps only insert bytes on the same line. Undo those column shifts in every segment.
        const edits = stamps ? stampEdits(source, path).map(([offset, text]) => {
          const before = source.slice(0, offset).split('\n');
          return {line: before.length - 1, column: before.at(-1).length, length: text.length};
        }) : [];
        const mappings = decode(map.mappings);
        for (const line of mappings) for (const segment of line) if (segment.length >= 4) {
          let added = 0;
          for (const edit of edits.filter(e => e.line === segment[2]).sort((a, b) => a.column - b.column)) {
            if (segment[3] >= edit.column + added) added += Math.min(edit.length, segment[3] - edit.column - added);
          }
          segment[3] -= added;
        }
        map.mappings = encode(mappings); map.sourcesContent = [source];
        const locations = {};
        walk(ast, node => {
          if (['ImportDeclaration', 'ExportNamedDeclaration', 'ExportAllDeclaration'].includes(node.type) && node.source)
            locations[node.source.value] = {line: node.source.loc.start.line, col: node.source.loc.start.column + 1};
          if (node.type === 'CallExpression' && node.callee?.name === 'require' && node.arguments[0]?.type === 'StringLiteral')
            locations[node.arguments[0].value] = {line: node.arguments[0].loc.start.line, col: node.arguments[0].loc.start.column + 1};
        });
        output = {code: result.code, sourceMap: JSON.stringify(map), locations};
      } else throw Error(`Unsupported module type: ${path}`);
      transformCache.set(key, output);
      if (transformCache.size > 256) transformCache.delete(transformCache.keys().next().value);
    }
    const dependencies = {};
    // Parse transformed requires, avoiding false imports inside comments and strings.
    walk(parseSource(output.code, path), node => {
      if (node.type !== 'CallExpression' || node.callee?.name !== 'require' || node.arguments[0]?.type !== 'StringLiteral') return;
      const specifier = node.arguments[0].value;
      if (Object.hasOwn(dependencies, specifier)) return;
      try { dependencies[specifier] = resolve(path, specifier, files, vendor, options); }
      catch (error) {
        const loc = output.locations?.[specifier] ?? {line: 1, col: 1};
        throw Error(`${path}:${loc.line}:${loc.col}: ${error.message}`);
      }
      if (!dependencies[specifier].startsWith('vendor:')) pending.push(dependencies[specifier]);
    });
    modules[path] = {code: output.code, sourceMap: output.sourceMap, dependencies};
  }
  return JSON.stringify({modules, hits, misses});
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

// Source-owned lettering images keep their text in the first helper argument.
// Rewrite that argument only; dimensions, colors, timing and the helper stay intact.
function letteringText(opening, source) {
  if (opening.name.type !== 'JSXIdentifier' || !['Img', 'img'].includes(opening.name.name)) return null;
  const index = opening.attributes.findLastIndex(attribute => attribute.type === 'JSXAttribute' && attribute.name?.name === 'src');
  if (index < 0) return null;
  const expression = opening.attributes[index].value?.expression;
  if (expression?.type !== 'CallExpression' || expression.callee.type !== 'Identifier' ||
      expression.callee.name !== 'lettering') return null;
  if (opening.attributes.slice(index + 1).some(attribute => attribute.type === 'JSXSpreadAttribute')) {
    return {editable: false, value: null, reason: 'A later spread may replace this lettering image. Edit it in code.'};
  }
  const argument = expression.arguments[0];
  if (!argument) return {editable: false, value: null, reason: 'This lettering has no text argument.'};
  const current = classify(argument, source);
  if (current.kind !== 'static' || typeof current.value !== 'string') {
    return {editable: false, value: null, reason: 'This lettering text is generated by code. Edit its variable or expression in source.'};
  }
  return {editable: true, value: current.value, reason: null, start: argument.start, end: argument.end, lettering: true};
}

// Only literal children can be replaced without deleting markup or changing code bindings.
function textContent(source, src) {
  const opening = findElement(source, src);
  const lettering = letteringText(opening, source);
  if (lettering) return lettering;
  // The showcase SVG adapter exposes text through its source-owned content style.
  // Other self-closing elements (images, media, arbitrary components) stay protected.
  if (opening.name.type === 'JSXIdentifier' && opening.name.name === 'EditableLayer') {
    const object = styleObject(opening);
    const property = object?.properties.find(property => keyOf(property) === 'content');
    if (property) {
      const current = classify(property.value, source);
      return {editable: current.kind === 'static' && typeof current.value === 'string',
        value: current.value ?? null, styleContent: true,
        reason: current.kind === 'static' ? null : 'This text is generated by code.'};
    }
    return {editable: !!object, value: null, reason: null, styleContent: true};
  }
  let element;
  const file = /^(.*):\d+:\d+$/.exec(src)[1];
  walk(parseSource(source, file), node => {
    if (node.type === 'JSXElement' && node.openingElement.start === opening.start) element = node;
  });
  if (!element?.closingElement) return {editable: false, value: null, reason: null};
  let value = '', hasText = false;
  for (const child of element.children) {
    if (child.type === 'JSXText') {
      // React's JSX whitespace normalization (entities are already decoded by Babel).
      const lines = child.value.replace(/\r\n?/g, '\n').split('\n');
      const last = lines.findLastIndex(line => /[^ \t]/.test(line));
      value += lines.map((line, index) => {
        let part = line.replace(/\t/g, ' ');
        if (index !== 0) part = part.replace(/^ +/, '');
        if (index !== lines.length - 1) part = part.replace(/ +$/, '');
        return part && index < last ? part + ' ' : part;
      }).join('');
      hasText ||= child.value.trim().length > 0;
    } else if (child.type === 'JSXExpressionContainer' && child.expression.type === 'JSXEmptyExpression') {
      return {editable: false, value: null, reason: 'This text contains comments. Edit it in code.'};
    } else if (child.type === 'JSXExpressionContainer' && classify(child.expression, source).kind === 'static' &&
        typeof classify(child.expression, source).value === 'string') {
      value += classify(child.expression, source).value;
      hasText = true;
    } else {
      return {editable: false, value: null, reason: child.type === 'JSXElement' || child.type === 'JSXFragment'
        ? 'Select the text element inside this container to edit its content.'
        : 'This text is generated by code. Edit its variable or expression in source.'};
    }
  }
  return {editable: hasText || element.children.some(child => child.type === 'JSXExpressionContainer'),
    value: hasText || value.length ? value : null, reason: null,
    start: opening.end, end: element.closingElement.start};
}

export function text(source, src) {
  const {editable, value, reason, styleContent} = textContent(source, src);
  return JSON.stringify({editable, value, reason, styleContent});
}

function editText(source, request) {
  const content = textContent(source, request.src);
  const opening = findElement(source, request.src);
  if (opening.name.type === 'JSXIdentifier' && opening.name.name === 'EditableLayer') {
    if (request.raw === undefined && typeof request.value !== 'string') throw Error('Invalid text edit');
    if (request.value === '') throw Error('refused: Film text cannot be empty.');
    return edit(source, JSON.stringify({...request, op: 'setStyle', key: 'content'}));
  }
  if (!content.editable) throw Error('refused: ' + (content.reason ?? 'Select an element with literal text.'));
  if (request.raw === undefined && typeof request.value !== 'string') throw Error('Invalid text edit');
  if (content.lettering) {
    const replacement = request.raw ?? literal(request.value, source, source.slice(content.start, content.end));
    return JSON.stringify({source: splice(source, content.start, content.end, replacement),
      inverse: {op: 'setText', src: request.src, key: 'children', raw: source.slice(content.start, content.end)}});
  }
  // String expressions escape braces, tags, entities, quotes and newlines without injecting JSX.
  const replacement = request.raw ?? '{' + JSON.stringify(request.value).replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029') + '}';
  return JSON.stringify({source: splice(source, content.start, content.end, replacement),
    inverse: {op: 'setText', src: request.src, key: 'children', raw: source.slice(content.start, content.end)}});
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
      if (isStamped(name, opening) && !/Geometry$|^(color|fog|fogExp2)$/.test(name)) {
        let data, error = reason;
        try { data = timelineData(source, opening); } catch (e) { error = e.message; data = {from: 0, duration: null, keyframes: {}}; }
        if (parentTimed) error = 'Timing is controlled by an ancestor object; edit the ancestor first';
        tracks.push({src: stampOf(file, opening), label: opening.attributes.find(a => a.name?.name === 'data-ms-label')?.value?.value ?? name, owner, offset, limit, reason: error, ...data});
        parentTimed ||= !!timelineAttribute(opening) && (data.from !== 0 || data.duration !== null);
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
    const three = threeSummary(source, element);
    for (const key of Object.keys(data.keyframes)) {
      if (three) {
        if (three.domain === 'map') {
          const field = DOMAINS.map.fields(three.type).find(f => f.key === key);
          if (typeof field?.fallback !== 'number')
            throw Error(`refused: ${key} must be a numeric map property to animate`);
          continue;
        }
        const property = three.properties.find(p => p.key === key);
        if (property?.kind !== 'static' || typeof property.value !== 'number')
          throw Error(`refused: ${key} must be an explicit static numeric 3D property to animate`);
        continue;
      }
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

// Resolve one field without evaluating project expressions. A spread or an args constructor
// can supply defaults, so those fields stay protected until explicitly authored after it.
function threeField(source, element, field, domain = 'three') {
  const [name, ...path] = field.path;
  const pierced = domain === 'three' && path.length === 1 && typeof path[0] === 'number' ? name + '-' + 'xyz'[path[0]] : null;
  const attrs = element.attributes;
  if (name === 'rotation' && attrs.some(a => a.name?.name === 'quaternion')) return {kind: 'computed'};
  const candidates = attrs.filter(a => [name, pierced].includes(a.name?.name));
  const attr = candidates.at(-1);
  const spread = attrs.findLastIndex(a => a.type === 'JSXSpreadAttribute');
  if (spread >= (attr ? attrs.indexOf(attr) : 0) || candidates.filter(a => a.name.name === attr?.name.name).length > 1)
    return {kind: 'computed'};
  if (!attr) {
    if (attrs.some(a => a.name?.name === 'args') || name === 'camera') return {kind: 'computed'};
    return {kind: 'static', value: field.fallback};
  }
  let node = attr.value?.expression ?? attr.value;
  const remaining = attr.name.name === pierced ? [] : path;
  for (const part of remaining) {
    if (!node) break;
    if (typeof part === 'number') {
      if (node?.type === 'NumericLiteral' || node?.type === 'UnaryExpression' && classify(node, source).kind === 'static') continue;
      if (node?.type !== 'ArrayExpression' || node.elements.length <= part ||
          node.elements.some(n => !n || n.type === 'SpreadElement')) return classify(node, source);
      node = node.elements[part];
    } else {
      if (node?.type !== 'ObjectExpression' || node.properties.some(p => keyOf(p) === null)) return {kind: 'computed'};
      const matches = node.properties.filter(p => keyOf(p) === part);
      if (matches.length > 1 || matches[0]?.shorthand) return {kind: 'computed'};
      node = matches[0]?.value;
    }
  }
  return node ? {...classify(node, source), node, attr} : name === 'camera' ? {kind: 'computed'} :
    {kind: 'static', value: field.fallback};
}

function threeSummary(source, element) {
  const type = elementName(element), domain = domainOf(type);
  if (!domain) return null;
  return {editable: true, domain, type, properties: DOMAINS[domain].fields(type).map(field => {
    const {node, attr, ...property} = threeField(source, element, field, domain);
    // Numeric Three colors need conversion before a color picker can edit them safely.
    if (field.key === 'color' && typeof property.value !== 'string') property.kind = 'computed';
    return {key: field.key, ...property};
  })};
}

function editThree(source, request) {
  const element = findElement(source, request.src);
  const type = elementName(element), domain = domainOf(type);
  const field = domain && DOMAINS[domain].fields(type).find(f => f.key === request.key);
  if (!field) throw Error(`refused: unsupported ${domain === 'map' ? 'map' : '3D'} property`);
  const current = threeField(source, element, field, domain);
  // Maps remain controllable even when props are computed in code; 3D keeps code protection.
  if (request.raw === undefined && domain !== 'map' && current.kind !== 'static')
    throw Error('refused: this 3D property is controlled by code');
  if (domain === 'map' && request.raw === undefined) {
    const problem = mapEdit.invalid(type, request.key, request.value);
    if (problem) throw Error(`refused: ${problem}`);
  }
  const root = field.path[0];
  // Existing vectors and camera objects are edited in place to preserve other components.
  const attribute = element.attributes.findLast(a => a.name?.name === (current.attr?.name.name ?? root));
  const spread = element.attributes.findLastIndex(a => a.type === 'JSXSpreadAttribute');
  if (request.raw === undefined && domain === 'map' && attribute && spread > element.attributes.indexOf(attribute))
    throw Error(`refused: move {...spread} before ${root} so map controls can override it`);
  const old = attribute ? source.slice(attribute.start, attribute.end) : '';
  let replacement = request.raw;
  if (replacement === undefined) {
    if (typeof field.fallback === 'number' && (typeof request.value !== 'number' || !Number.isFinite(request.value)))
      throw Error(`refused: a finite numeric ${domain === 'map' ? 'map' : '3D'} value is required`);
    if (typeof field.fallback === 'string' && typeof request.value !== 'string')
      throw Error('refused: a string value is required');
    if (['opacity', 'roughness', 'metalness', 'penumbra'].includes(field.key) && (request.value < 0 || request.value > 1) ||
        ['intensity', 'distance', 'decay', 'shininess'].includes(field.key) && request.value < 0 ||
        field.key === 'cameraFov' && (request.value <= 0 || request.value >= 180) ||
        ['cameraZoom', 'ior'].includes(field.key) && request.value <= 0)
      throw Error('refused: 3D property is outside its supported range');
    // Map coordinates need about 10 cm precision (6 decimals); other values keep 3.
    const precision = domain === 'map' ? 6 : 3;
    let text = literal(request.value, source, current.kind === 'static' ? current.raw : undefined, precision);
    // A JSX attribute string (`label="…"`) has no escapes: use an expression when needed.
    const jsxString = typeof request.value === 'string' && (!current.node || current.node === attribute?.value);
    if (jsxString) text = /["\\{}<>\n]/.test(request.value) ? `{${JSON.stringify(request.value)}}` : `"${request.value}"`;
    if (current.node && attribute) {
      // A scalar scale supplies all axes. Expand it before changing a single component.
      const expression = attribute.value?.expression;
      if (domain === 'three' && field.path.length === 2 && expression === current.node && attribute.name.name === root) {
        const values = [current.value, current.value, current.value];
        values[field.path[1]] = request.value;
        replacement = `${root}={${JSON.stringify(values)}}`;
      } else if (current.node === attribute.value && typeof request.value === 'number') {
        replacement = `${root}={${text}}`;
      } else {
        replacement = splice(old, current.node.start - attribute.start, current.node.end - attribute.start, text);
      }
    } else if (domain === 'map' && attribute && field.path.length === 1) {
      // Boolean shorthand (`<MapView zoom />`) or spread-shadowed single attribute.
      replacement = jsxString ? `${root}=${text}` : `${root}={${text}}`;
    } else if (field.path.length === 2) {
      const siblings = DOMAINS[domain].fields(type).filter(f => f.path[0] === root);
      const values = siblings.map((_, i) => {
        const def = siblings.find(f => f.path[1] === i);
        const existing = def && threeField(source, element, def, domain);
        if (existing?.kind === 'static' && typeof existing.value === 'number') return existing.value;
        return root === 'scale' ? 1 : def?.fallback ?? 0;
      });
      values[field.path[1]] = Number(request.value.toFixed(precision));
      replacement = `${root}={${JSON.stringify(values)}}`;
    } else if (field.path.length > 1) throw Error('refused: add the camera property explicitly in code first');
    else replacement = jsxString ? `${root}=${text}` : `${root}={${text}}`;
  }
  // New map attributes are placed after any leading `{...spread}` so explicit edits win.
  const insertAt = domain === 'map' ? (element.attributes.at(-1)?.end ?? element.name.end) : element.name.end;
  let start = attribute?.start ?? insertAt, end = attribute?.end ?? start;
  if (!attribute && replacement) replacement = ' ' + replacement;
  if (attribute && !replacement && source[start - 1] === ' ') start--;
  return JSON.stringify({source: splice(source, start, end, replacement),
    inverse: {op: domain === 'map' ? 'setMapProperty' : 'setThreeProperty', src: request.src, key: request.key, raw: old}});
}

// MARK: Camera rigs
// A camera rig is any element with a `keys` prop that resolves to a literal array of camera keys:
// {frame, position: [x, y, z], target: [x, y, z], fov, roll?}, inline or in a `const` of the same
// file. The rig's code stays the source of truth; the editor rewrites those literals in place.
const unwrapExpression = node => {
  while (node && ['TSAsExpression', 'TSSatisfiesExpression', 'TSTypeAssertion', 'TSNonNullExpression',
    'ParenthesizedExpression'].includes(node.type)) node = node.expression;
  return node;
};

function rigKey(node, source) {
  if (node?.type !== 'ObjectExpression' || node.properties.some(p => keyOf(p) === null || p.shorthand)) return null;
  const props = Object.fromEntries(node.properties.map(p => [keyOf(p), p]));
  const number = name => {
    const value = props[name] && classify(props[name].value, source);
    return value?.kind === 'static' && typeof value.value === 'number' ? value.value : null;
  };
  const vector = name => {
    const value = props[name]?.value;
    if (value?.type !== 'ArrayExpression' || value.elements.length !== 3) return null;
    const numbers = value.elements.map(n => n && classify(n, source)).map(v => v?.kind === 'static' ? v.value : null);
    return numbers.every(v => typeof v === 'number') ? numbers : null;
  };
  const key = {frame: number('frame'), position: vector('position'), target: vector('target'), fov: number('fov')};
  if (Object.values(key).some(v => v === null)) return null;
  if (props.roll) { key.roll = number('roll'); if (key.roll === null) return null; }
  const known = new Set(['frame', 'position', 'target', 'fov', 'roll']);
  if (Object.keys(props).some(name => !known.has(name))) return null;
  return key;
}

function rigArrays(ast, source, file) {
  const constants = new Map();
  walk(ast, node => {
    if (node.type === 'VariableDeclaration' && node.kind === 'const') {
      for (const declarator of node.declarations) {
        if (declarator.id.type === 'Identifier') constants.set(declarator.id.name, unwrapExpression(declarator.init));
      }
    }
  });
  const rigs = [];
  walk(ast, node => {
    if (node.type !== 'JSXOpeningElement') return;
    const attribute = node.attributes.find(a => a.name?.name === 'keys');
    let array = unwrapExpression(attribute?.value?.expression);
    if (array?.type === 'Identifier') array = constants.get(array.name);
    if (array?.type !== 'ArrayExpression' || !array.elements.length) return;
    const keys = array.elements.map(element => rigKey(element, source));
    if (keys.some(key => !key) || keys.some((key, i) => i > 0 && key.frame <= keys[i - 1].frame)) return;
    rigs.push({src: stampOf(file, array), element: stampOf(file, node), name: elementName(node), keys});
  });
  return rigs;
}

/** Camera rigs with literal keys in `source`, for editing a code-driven camera in place. */
export function cameraRigs(source, file) {
  return JSON.stringify(rigArrays(parseSource(source, file), source, file));
}

const rigNumber = value => String(Number(value.toFixed(3)));
const rigVector = values => `[${values.map(rigNumber).join(', ')}]`;

function editCameraRig(source, request) {
  const match = /^(.*):(\d+):(\d+)$/.exec(request.src);
  if (!match) throw Error(`Invalid source stamp: ${request.src}`);
  const rig = rigArrays(parseSource(source, match[1]), source, match[1]).find(r => r.src === request.src);
  let array = null;
  walk(parseSource(source, match[1]), node => {
    if (array) return false;
    if (node.type === 'ArrayExpression' && stampOf(match[1], node) === request.src) array = node;
  });
  if (!array) throw Error(`stale-source: ${request.src} no longer names camera keys; reopen the scene`);
  const old = source.slice(array.start, array.end);
  const inverse = {op: 'setCameraRigKey', src: request.src, key: 'cameraRig', raw: old};
  if (request.raw !== undefined) {
    return JSON.stringify({source: splice(source, array.start, array.end, request.raw), inverse});
  }
  if (!rig) throw Error('refused: the camera keys are no longer plain literals; edit them in code');
  const value = request.value;
  const index = rig.keys.findIndex(key => key.frame === value?.frame);
  if (!value || !Number.isInteger(value.frame)) throw Error('refused: a camera key needs an integer frame');
  if (value.delete) {
    if (index < 0) throw Error('refused: there is no camera key at this frame');
    if (rig.keys.length <= 2) throw Error('refused: a camera rig needs at least two keys');
    const elements = array.elements;
    const [start, end] = index > 0 ? [elements[index - 1].end, elements[index].end] : [elements[0].start, elements[1].start];
    return JSON.stringify({source: splice(source, start, end, ''), inverse});
  }
  for (const name of ['position', 'target']) {
    if (!Array.isArray(value[name]) || value[name].length !== 3 || !value[name].every(Number.isFinite))
      throw Error(`refused: camera ${name} must be three finite numbers`);
  }
  if (!(value.fov > 0 && value.fov < 180)) throw Error('refused: camera fov must be between 0 and 180');
  if (value.roll !== undefined && !Number.isFinite(value.roll)) throw Error('refused: camera roll must be finite');
  if (index >= 0) {
    // Rewrite the key's values in place, last first so offsets stay valid.
    const element = array.elements[index];
    const props = Object.fromEntries(element.properties.map(p => [keyOf(p), p]));
    const changes = [['position', rigVector(value.position)], ['target', rigVector(value.target)], ['fov', rigNumber(value.fov)]];
    if (value.roll !== undefined && props.roll) changes.push(['roll', rigNumber(value.roll)]);
    let text = source;
    const edits = changes.map(([name, replacement]) => [props[name].value, replacement]);
    if (value.roll !== undefined && !props.roll && value.roll !== 0) {
      const last = element.properties.at(-1);
      edits.push([{start: last.end, end: last.end}, `, roll: ${rigNumber(value.roll)}`]);
    }
    for (const [node, replacement] of edits.sort((a, b) => b[0].start - a[0].start)) {
      text = splice(text, node.start, node.end, replacement);
    }
    return JSON.stringify({source: text, inverse});
  }
  const roll = value.roll !== undefined && (value.roll !== 0 || rig.keys.some(key => key.roll !== undefined))
    ? `, roll: ${rigNumber(value.roll)}` : '';
  const text = `{frame: ${value.frame}, position: ${rigVector(value.position)}, target: ${rigVector(value.target)}, ` +
    `fov: ${rigNumber(value.fov)}${roll}}`;
  const elements = array.elements;
  const separator = elements.length > 1 ? source.slice(elements[0].end, elements[1].start) : ', ';
  const at = rig.keys.findIndex(key => key.frame > value.frame);
  const result = at === 0
    ? splice(source, elements[0].start, elements[0].start, text + separator)
    : splice(source, elements[(at < 0 ? elements.length : at) - 1].end, elements[(at < 0 ? elements.length : at) - 1].end, separator + text);
  return JSON.stringify({source: result, inverse});
}

// MARK: Map children
// Adds or removes <MapRoute>/<MapMarker> children of a <MapView>. The inverse restores the
// map element's exact text, so undo is byte-exact.
function jsxElements(source, file) {
  const elements = [];
  walk(parseSource(source, file), node => { if (node.type === 'JSXElement') elements.push(node); });
  return elements;
}
const mapNumber = value => {
  if (!Number.isFinite(value)) throw Error('refused: map coordinates must be finite numbers');
  return String(Number(value.toFixed(6)));
};
function mapChildText(type, props) {
  const field = key => mapEdit.fields(type).find(f => f.path[0] === key);
  const parts = [];
  for (const [key, value] of Object.entries(props ?? {})) {
    if (!/^[A-Za-z][A-Za-z0-9]*$/.test(key)) throw Error('refused: invalid map property name');
    if (Array.isArray(value)) {
      if (value.length !== 2 || !field(key)) throw Error(`refused: ${key} must be [longitude, latitude]`);
      parts.push(`${key}={[${value.map(mapNumber).join(', ')}]}`);
    } else if (typeof value === 'number') {
      const problem = mapEdit.invalid(type, key, value);
      if (problem && field(key)) throw Error(`refused: ${problem}`);
      parts.push(`${key}={${mapNumber(value)}}`);
    } else if (typeof value === 'string') {
      const problem = mapEdit.fields(type).some(f => f.key === key) ? mapEdit.invalid(type, key, value) : null;
      if (problem) throw Error(`refused: ${problem}`);
      // JSX attribute strings have no escapes; quotes, braces and newlines need an expression.
      parts.push(/["\\{}<>\n]/.test(value) ? `${key}={${JSON.stringify(value)}}` : `${key}="${value}"`);
    } else throw Error(`refused: unsupported value for ${key}`);
  }
  return `<${type}${parts.length ? ' ' + parts.join(' ') : ''} />`;
}
function editMapChildren(source, request) {
  const match = /^(.*):(\d+):(\d+)$/.exec(request.src);
  if (!match) throw Error(`Invalid source stamp: ${request.src}`);
  const file = match[1];
  const elements = jsxElements(source, file);
  const named = src => elements.find(e => stampOf(file, e.openingElement) === src);
  let map, child;
  if (request.key === 'remove') {
    child = named(request.src);
    if (!child) throw Error(`stale-source: ${request.src} no longer names an element; reselect it`);
    if (!['MapRoute', 'MapMarker'].includes(elementName(child.openingElement)))
      throw Error('refused: only map routes and markers can be removed here');
    map = elements.filter(e => elementName(e.openingElement) === 'MapView' && e.start < child.start && e.end > child.end).at(-1);
    if (!map || !map.children.includes(child)) throw Error('refused: this element is not a direct child of a <MapView>');
  } else {
    map = named(request.src);
    if (!map) throw Error(`stale-source: ${request.src} no longer names an element; reselect it`);
    if (elementName(map.openingElement) !== 'MapView') throw Error('refused: select a <MapView> to add routes or markers');
  }
  const old = source.slice(map.start, map.end);
  const inverse = {op: 'setMapChildren', src: stampOf(file, map.openingElement), key: 'restore', raw: old};
  if (request.key === 'restore') {
    if (typeof request.raw !== 'string') throw Error('Invalid map restore');
    return JSON.stringify({source: splice(source, map.start, map.end, request.raw), inverse});
  }
  if (request.key === 'remove') {
    let start = child.start, end = child.end;
    // Remove the child's whole line when it stands alone on it.
    const lineStart = source.lastIndexOf('\n', start - 1) + 1, lineEnd = source.indexOf('\n', end);
    if (/^[ \t]*$/.test(source.slice(lineStart, start)) && /^[ \t]*$/.test(source.slice(end, lineEnd < 0 ? source.length : lineEnd))) {
      start = lineStart; end = lineEnd < 0 ? source.length : lineEnd + 1;
    }
    return JSON.stringify({source: splice(source, start, end, ''), inverse});
  }
  if (request.key !== 'insert') throw Error('Invalid map children request');
  const type = request.value?.type;
  if (!['MapRoute', 'MapMarker'].includes(type)) throw Error('refused: add a MapRoute or MapMarker');
  const text = mapChildText(type, request.value.props);
  const opening = map.openingElement;
  const lineStart = source.lastIndexOf('\n', map.start - 1) + 1;
  const indent = /^[ \t]*/.exec(source.slice(lineStart))[0];
  if (opening.selfClosing) {
    // <MapView … /> becomes <MapView …>child</MapView>.
    const head = source.slice(opening.start, opening.end).replace(/\s*\/>$/, '>');
    return JSON.stringify({source: splice(source, map.start, map.end,
      `${head}\n${indent}  ${text}\n${indent}</MapView>`), inverse});
  }
  const closing = map.closingElement;
  const last = map.children.filter(c => c.type !== 'JSXText' || c.value.trim()).at(-1);
  const childIndent = last ? /^[ \t]*/.exec(source.slice(source.lastIndexOf('\n', last.start - 1) + 1))[0] : indent + '  ';
  const before = source.slice(0, closing.start).replace(/[ \t]*$/, '');
  const prefix = before.endsWith('\n') ? '' : '\n';
  return JSON.stringify({source: before + `${prefix}${childIndent}${text}\n${indent}` + source.slice(closing.start), inverse});
}

/** Inline style properties of the element at `src`, classified for editing. */
export function styles(source, src) {
  const element = findElement(source, src);
  const three = threeSummary(source, element);
  if (three) return JSON.stringify(three);
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

function literal(value, source, previous, digits = 3) {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw Error('Style numbers must be finite');
    return String(Number(value.toFixed(digits)));
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
  if (op === 'setText') return editText(source, request);
  if (op === 'setCameraRigKey') return editCameraRig(source, request);
  if (op === 'setMapChildren') return editMapChildren(source, request);
  if (op === 'setThreeProperty' || op === 'setMapProperty' ||
      (op === 'setStyle' && domainOf(elementName(findElement(source, src)))))
    return editThree(source, request);
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
