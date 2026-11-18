// Traces text that code generates back to the string literals it comes from, so the editor can
// rewrite the literal instead of refusing. Same-file only: the literal must live in the file of the
// selected element. Everything here is static analysis of the Babel AST; no project code runs.
//
//   const title = 'Hello';            <h1>{title}</h1>                    → 'Hello'
//   const items = [{label: 'A'}, …];  items.map(i => <li>{i.label}</li>)  → each label
//   const Card = ({text}) => <p>{text}</p>;  <Card text="Hi" />           → 'Hi'
//   {title.toUpperCase()}, {`${name} wins`}, {word.split('').map(…)}      → the source strings
//
// Literal fields are offered for editing; anything that cannot be traced stays code-only.

const MAX_DEPTH = 12;
const STRING_METHODS = new Set(['toUpperCase', 'toLowerCase', 'toLocaleUpperCase', 'toLocaleLowerCase', 'trim',
  'trimStart', 'trimEnd', 'slice', 'substring', 'substr', 'padStart', 'padEnd', 'replace', 'replaceAll', 'split',
  'concat', 'join', 'toString', 'at', 'charAt', 'repeat', 'normalize']);
const ITERATORS = new Set(['map', 'flatMap', 'forEach', 'filter', 'find', 'findLast', 'some', 'every', 'reduce']);
const FUNCTIONS = new Set(['ArrowFunctionExpression', 'FunctionExpression', 'FunctionDeclaration']);
const SCOPES = new Set(['Program', 'BlockStatement', 'StaticBlock', ...FUNCTIONS]);
const WRAPPERS = new Set(['TSAsExpression', 'TSSatisfiesExpression', 'TSNonNullExpression', 'TSTypeAssertion',
  'ParenthesizedExpression', 'TypeCastExpression']);

function walk(node, visit, parent = null) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { for (const child of node) walk(child, visit, parent); return; }
  if (typeof node.type === 'string' && visit(node, parent) === false) return;
  for (const [key, value] of Object.entries(node)) {
    if (key !== 'loc' && value && typeof value === 'object') walk(value, visit, typeof node.type === 'string' ? node : parent);
  }
}

/** Parent links and declarations for one parsed file, built once per AST. */
const indexes = new WeakMap();
function indexOf(ast) {
  let index = indexes.get(ast);
  if (index) return index;
  const parents = new Map();
  const components = new Map(); // Capitalized component name → function node
  const usages = new Map();     // Component name → JSXOpeningElement[]
  walk(ast, (node, parent) => {
    parents.set(node, parent);
    if (node.type === 'JSXOpeningElement' && node.name.type === 'JSXIdentifier') {
      if (!usages.has(node.name.name)) usages.set(node.name.name, []);
      usages.get(node.name.name).push(node);
    }
    if (node.type === 'FunctionDeclaration' && node.id && /^[A-Z]/.test(node.id.name)) components.set(node.id.name, node);
    if (node.type === 'VariableDeclarator' && node.id.type === 'Identifier' && /^[A-Z]/.test(node.id.name)) {
      let init = unwrap(node.init);
      // React.memo(…) / memo(…) / forwardRef(…)
      while (init?.type === 'CallExpression' && init.arguments.length) init = unwrap(init.arguments[0]);
      if (FUNCTIONS.has(init?.type)) components.set(node.id.name, init);
    }
  });
  index = {parents, components, usages};
  indexes.set(ast, index);
  return index;
}

const unwrap = node => { while (node && WRAPPERS.has(node.type)) node = node.expression; return node; };

const keyName = property => {
  if (!property || property.computed && property.key?.type !== 'StringLiteral') return null;
  const key = property.key;
  return key?.type === 'Identifier' ? key.name : key?.type === 'StringLiteral' ? key.value
    : key?.type === 'NumericLiteral' ? String(key.value) : null;
};

/** Every declaration of `name` visible from `node`: {kind, node, owner, pattern…}. */
function lookup(name, node, index) {
  for (let scope = index.parents.get(node); scope; scope = index.parents.get(scope)) {
    if (!SCOPES.has(scope.type)) continue;
    if (FUNCTIONS.has(scope.type)) {
      for (const [position, param] of scope.params.entries()) {
        const found = bind(param, name);
        if (found) return {kind: 'param', fn: scope, position, ...found};
      }
      if (scope.type === 'FunctionExpression' && scope.id?.name === name) return null;
      continue;
    }
    const statements = scope.body ?? [];
    for (const statement of Array.isArray(statements) ? statements : [statements]) {
      const declaration = statement.type === 'ExportNamedDeclaration' ? statement.declaration : statement;
      if (declaration?.type !== 'VariableDeclaration') continue;
      for (const declarator of declaration.declarations) {
        const found = bind(declarator.id, name);
        if (found) return {kind: 'variable', declarator, constant: declaration.kind === 'const', ...found};
      }
    }
  }
  return null;
}

/** Where `name` sits inside a binding pattern: the property path from the bound value, and a default. */
function bind(pattern, name, path = []) {
  pattern = unwrap(pattern);
  if (!pattern) return null;
  if (pattern.type === 'Identifier') return pattern.name === name ? {path, fallback: null} : null;
  if (pattern.type === 'AssignmentPattern') {
    const found = bind(pattern.left, name, path);
    if (found && pattern.left.type === 'Identifier') return {...found, fallback: pattern.right};
    return found;
  }
  if (pattern.type === 'ObjectPattern') {
    for (const property of pattern.properties) {
      if (property.type === 'RestElement') { const found = bind(property.argument, name, path); if (found) return found; continue; }
      const key = keyName(property);
      const found = key !== null && bind(property.value, name, [...path, key]);
      if (found) return found;
    }
  }
  if (pattern.type === 'ArrayPattern') {
    for (const [position, element] of pattern.elements.entries()) {
      const found = element && bind(element, name, [...path, position]);
      if (found) return found;
    }
  }
  return null;
}

/**
 * The AST nodes an expression may evaluate to. Objects and arrays are returned as nodes so member
 * access can narrow them; `transformed` marks values code changes before display.
 */
function values(node, ctx, depth = 0, transformed = false) {
  node = unwrap(node);
  if (!node || depth > MAX_DEPTH || ctx.seen.has(node)) return [];
  ctx.seen.add(node);
  try {
    switch (node.type) {
    case 'StringLiteral': case 'TemplateLiteral': case 'ObjectExpression': case 'ArrayExpression': case 'JSXText':
      if (node.type === 'TemplateLiteral' && node.expressions.length) {
        return node.expressions.flatMap(expression => values(expression, ctx, depth + 1, true));
      }
      return [{node, transformed}];
    case 'Identifier': return identifier(node, ctx, depth, transformed);
    case 'MemberExpression': case 'OptionalMemberExpression': return member(node, ctx, depth, transformed);
    case 'ConditionalExpression':
      return [...values(node.consequent, ctx, depth + 1, transformed), ...values(node.alternate, ctx, depth + 1, transformed)];
    case 'LogicalExpression':
      return [...values(node.left, ctx, depth + 1, transformed), ...values(node.right, ctx, depth + 1, transformed)];
    case 'BinaryExpression':
      return node.operator === '+' ? [...values(node.left, ctx, depth + 1, true), ...values(node.right, ctx, depth + 1, true)] : [];
    case 'CallExpression': case 'OptionalCallExpression': {
      const callee = unwrap(node.callee);
      if ((callee.type === 'MemberExpression' || callee.type === 'OptionalMemberExpression') && !callee.computed) {
        const method = callee.property.name;
        if (STRING_METHODS.has(method) || ITERATORS.has(method)) return values(callee.object, ctx, depth + 1, true);
      }
      if (callee.type === 'Identifier' && callee.name === 'String') return values(node.arguments[0], ctx, depth + 1, transformed);
      return [];
    }
    case 'JSXExpressionContainer': return values(node.expression, ctx, depth + 1, transformed);
    default: return [];
    }
  } finally {
    ctx.seen.delete(node);
  }
}

function identifier(node, ctx, depth, transformed) {
  const binding = lookup(node.name, node, ctx.index);
  if (!binding) return [];
  const results = [];
  if (binding.kind === 'variable') {
    results.push(...narrow(values(binding.declarator.init, ctx, depth + 1, transformed), binding.path, ctx, depth));
  } else {
    results.push(...param(binding, ctx, depth, transformed));
  }
  if (binding.fallback) results.push(...values(binding.fallback, ctx, depth + 1, transformed));
  return results;
}

/** A function parameter: an iterator callback's item, or a component's props from its JSX usages. */
function param(binding, ctx, depth, transformed) {
  const {fn, position, path} = binding;
  const call = ctx.index.parents.get(fn);
  if (call?.type === 'CallExpression' && call.arguments.includes(fn)) {
    const callee = unwrap(call.callee);
    if (callee?.type === 'MemberExpression' && !callee.computed && ITERATORS.has(callee.property.name)) {
      // reduce's item is its second parameter; every other iterator passes it first.
      const item = callee.property.name === 'reduce' ? 1 : 0;
      if (position !== item) return [];
      const items = values(callee.object, ctx, depth + 1, transformed).flatMap(({node, transformed: changed}) =>
        node.type === 'ArrayExpression' ? node.elements.filter(Boolean).flatMap(element =>
          element.type === 'SpreadElement' ? [] : values(element, ctx, depth + 1, changed)) : []);
      return narrow(items, path, ctx, depth);
    }
    return [];
  }
  if (position !== 0) return [];
  const name = componentName(fn, ctx.index);
  if (!name || !path.length || typeof path[0] !== 'string') return [];
  const [prop, ...rest] = path;
  const results = [];
  for (const usage of ctx.index.usages.get(name) ?? []) {
    const attribute = usage.attributes.findLast(attr => attr.type === 'JSXAttribute' && attr.name?.name === prop);
    if (!attribute?.value) continue;
    const found = attribute.value.type === 'StringLiteral'
      ? [{node: attribute.value, transformed}]
      : values(attribute.value, ctx, depth + 1, transformed);
    results.push(...narrow(found, rest, ctx, depth));
  }
  // `children` passed between the tags.
  if (prop === 'children' && !rest.length) {
    for (const usage of ctx.index.usages.get(name) ?? []) {
      const element = ctx.index.parents.get(usage);
      for (const child of element?.children ?? []) {
        if (child.type === 'JSXText' && child.value.trim()) results.push({node: child, transformed});
        else if (child.type === 'JSXExpressionContainer') results.push(...values(child.expression, ctx, depth + 1, transformed));
      }
    }
  }
  return results;
}

function componentName(fn, index) {
  if (fn.type === 'FunctionDeclaration') return fn.id?.name ?? null;
  for (const [name, component] of index.components) if (component === fn) return name;
  return null;
}

/** `props.title`, `item.label`, `items[2]`, `data.rows[i].name`. */
function member(node, ctx, depth, transformed) {
  if (!node.computed && node.property.name === 'length') return [];
  const key = !node.computed ? node.property.name
    : node.property.type === 'StringLiteral' ? node.property.value
      : node.property.type === 'NumericLiteral' ? node.property.value : undefined;
  // `props.title` on a component's whole-props parameter.
  const object = unwrap(node.object);
  if (object.type === 'Identifier' && typeof key === 'string') {
    const binding = lookup(object.name, object, ctx.index);
    if (binding?.kind === 'param' && !binding.path.length) {
      return param({...binding, path: [key]}, ctx, depth, transformed);
    }
  }
  return narrow(values(node.object, ctx, depth + 1, transformed), [key], ctx, depth);
}

/** Follows a property path into object and array literals. `undefined` keys mean "any element". */
function narrow(found, path, ctx, depth) {
  let current = found;
  for (const key of path) {
    current = current.flatMap(({node, transformed}) => {
      if (node.type === 'ObjectExpression') {
        const property = node.properties.findLast(p => p.type === 'ObjectProperty' && keyName(p) === String(key));
        return property ? values(property.value, ctx, depth + 1, transformed) : [];
      }
      if (node.type === 'ArrayExpression') {
        const elements = typeof key === 'number' ? [node.elements[key]] : key === undefined ? node.elements : [];
        return elements.filter(e => e && e.type !== 'SpreadElement').flatMap(e => values(e, ctx, depth + 1, transformed));
      }
      return [];
    });
  }
  return current;
}

/** React's whitespace rules for a JSX text child. */
export function jsxTextValue(value) {
  const lines = value.replace(/\r\n?/g, '\n').split('\n');
  const last = lines.findLastIndex(line => /[^ \t]/.test(line));
  return lines.map((line, index) => {
    let part = line.replace(/\t/g, ' ');
    if (index !== 0) part = part.replace(/^ +/, '');
    if (index !== lines.length - 1) part = part.replace(/ +$/, '');
    return part && index < last ? part + ' ' : part;
  }).join('');
}

function stringValue(node) {
  if (node.type === 'StringLiteral') return node.value;
  if (node.type === 'TemplateLiteral' && !node.expressions.length) return node.quasis[0].value.cooked;
  if (node.type === 'JSXText') return jsxTextValue(node.value);
  return null;
}

/** A readable name for where the literal lives: its variable, property, prop or "Text". */
function labelOf(node, index) {
  let child = node;
  for (let parent = index.parents.get(node); parent; child = parent, parent = index.parents.get(parent)) {
    if (parent.type === 'ObjectProperty' && parent.value === child) return keyName(parent) ?? 'Text';
    if (parent.type === 'JSXAttribute') return parent.name?.name ?? 'Text';
    if (parent.type === 'VariableDeclarator') return parent.id.type === 'Identifier' ? parent.id.name : 'Text';
    if (parent.type === 'ArrayExpression') continue;
    if (WRAPPERS.has(parent.type)) continue;
    break;
  }
  return 'Text';
}

/** Literals that sit outside the element itself are shared by everything that reads them. */
function isShared(node, element) {
  return node.start < element.start || node.end > element.end;
}

const normalize = text => text.replace(/\s+/g, ' ').trim();

/**
 * Literal fields behind the selected element's text. `element` is its JSXElement; `rendered` is
 * the text the frame shows for the picked instance, used to keep only the strings it displays
 * (one row of a mapped list) when available.
 */
export function textFields(ast, source, element, rendered) {
  const index = indexOf(ast);
  const ctx = {index, seen: new Set()};
  const found = [];
  for (const child of element.children) {
    if (child.type === 'JSXText') {
      if (child.value.trim()) found.push({node: child, transformed: false});
    } else if (child.type === 'JSXExpressionContainer' && child.expression.type !== 'JSXEmptyExpression') {
      found.push(...values(child.expression, ctx));
    } else if (child.type === 'JSXElement' || child.type === 'JSXFragment') {
      // Text of nested elements is edited on those elements, unless it all comes from code above.
      walk(child, node => {
        if (node.type === 'JSXExpressionContainer' && node.expression.type !== 'JSXEmptyExpression') {
          found.push(...values(node.expression, ctx).filter(({node: value}) => isShared(value, element)));
          return false;
        }
      });
    }
  }
  return collect(found, source, element, rendered, index);
}

/** Literal fields behind one expression (a lettering argument, a style `content`). */
export function expressionFields(ast, source, expression, container, rendered) {
  const index = indexOf(ast);
  return collect(values(expression, {index, seen: new Set()}), source, container, rendered, index);
}

function collect(found, source, element, rendered, index) {
  const unique = new Map();
  for (const {node, transformed} of found) {
    const value = stringValue(node);
    if (value === null) continue;
    const prior = unique.get(node.start);
    if (prior) { prior.transformed ||= transformed; continue; }
    unique.set(node.start, {
      offset: node.start, raw: source.slice(node.start, node.end), value,
      label: node.type === 'JSXText' ? (isShared(node, element) ? 'children' : 'Text') : labelOf(node, index),
      line: node.loc.start.line, transformed, shared: isShared(node, element),
      kind: node.type === 'JSXText' ? 'jsxText' : index.parents.get(node)?.type === 'JSXAttribute' ? 'attribute'
        : node.type === 'TemplateLiteral' ? 'template' : 'string',
    });
  }
  // Text inside the element first, in reading order; shared sources (variables, data, props) after.
  let fields = [...unique.values()].sort((a, b) => (a.shared - b.shared) || a.offset - b.offset);
  const shown = rendered ? normalize(rendered) : '';
  if (shown && fields.length > 1) {
    const lower = shown.toLowerCase();
    const visible = fields.filter(field => {
      const value = normalize(field.value);
      if (!value) return false;
      if (shown.includes(value)) return true;
      // Upper/lowercased, or split into letters with spacing.
      return lower.includes(value.toLowerCase()) || lower.replace(/ /g, '').includes(value.toLowerCase().replace(/ /g, ''));
    });
    if (visible.length) fields = visible;
  }
  return fields.slice(0, 24);
}

/** Text that writes `value` back in the place of the literal `node`, keeping its syntax. */
export function literalReplacement(field, value) {
  const quoted = JSON.stringify(value).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  switch (field.kind) {
  case 'attribute':
    // JSX attribute strings have no escapes; anything special becomes an expression.
    if (!/["\\{}<>&\n\r]/.test(value)) return `"${value}"`;
    return `{${quoted}}`;
  case 'jsxText': {
    // Surrounding whitespace that spans lines is insignificant to React; keep it byte-for-byte.
    const multiline = /\n/.test(field.raw);
    const lead = multiline ? /^\s*/.exec(field.raw)[0] : '', trail = multiline ? /\s*$/.exec(field.raw)[0] : '';
    const plain = value.length && !/[{}<>&\n\r]/.test(value) && (!multiline || value.trim() === value);
    return plain ? lead + value + trail : `{${quoted}}`;
  }
  case 'template':
    return '`' + value.replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\$\{/g, '\\${') + '`';
  default: {
    const quote = field.raw[0] === "'" ? "'" : '"';
    if (quote === '"') return quoted;
    return "'" + quoted.slice(1, -1).replace(/\\"/g, '"').replace(/'/g, "\\'") + "'";
  }
  }
}
