const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");
const deps = createRequire(path.resolve(__dirname, "../../tests/package.json"));
const swc = deps("@swc/core");
const repo = path.resolve(__dirname, "../..");
const [project, entry] = process.argv.slice(2);
if (!project || !entry) throw Error("Usage: compile.cjs project entry");
const modules = new Map();
const diagnostics = [];
const aliases = { remotion: path.join(repo, "js/remotion-shim/index.js") };
function resolve(specifier, parent) {
  if (aliases[specifier]) return aliases[specifier];
  if (/^(node:|fs$|path$|child_process$|react-dom|@remotion\/)/.test(specifier))
    throw Error(`ms/unsupported-package: ${specifier} in ${parent}`);
  if (specifier.startsWith(".")) {
    const base = path.resolve(path.dirname(parent), specifier);
    for (const suffix of [
      "",
      ".ts",
      ".tsx",
      ".js",
      ".jsx",
      ".json",
      "/index.ts",
      "/index.tsx",
      "/index.js",
    ]) {
      const file = base + suffix;
      if (fs.existsSync(file) && fs.statSync(file).isFile()) return file;
    }
    throw Error(`Cannot resolve ${specifier} from ${parent}`);
  }
  if (!/^(react($|\/)|react-reconciler$|scheduler$)/.test(specifier))
    throw Error(`ms/unsupported-package: ${specifier}`);
  return deps.resolve(specifier);
}
function lint(ast, file) {
  function visit(node) {
    if (!node || typeof node !== "object") return;
    const fail = (rule, message) => diagnostics.push({ rule, file, message });
    if (node.type === "JSXOpeningElement") {
      const name = node.name.value;
      if (["video", "audio"].includes(name))
        fail(
          "ms/no-raw-media",
          `Use native media components instead of ${name}`,
        );
      else if (
        name &&
        name[0] === name[0].toLowerCase() &&
        // SVG JSX may be serialized into an img data URI by user code. Host SVG
        // nodes still fail explicitly in the painter; only SVG images are supported.
        !["div", "span", "img", "svg", "g", "defs", "path", "rect", "circle",
          "ellipse", "text", "radialGradient", "linearGradient", "stop", "pattern"].includes(name)
      )
        fail("ms/unsupported-element", `${name} is not implemented`);
      for (const attr of node.attributes || [])
        if (["className", "dangerouslySetInnerHTML"].includes(attr.name?.value))
          fail("ms/no-classname", "Only inline styles are supported");
    }
    if (
      node.type === "KeyValueProperty" &&
      node.key.value === "display" &&
      node.value.type === "StringLiteral" &&
      !["flex", "none"].includes(node.value.value)
    )
      fail("ms/unsupported-css-value", "Only flex/none is supported");
    if (
      node.type === "KeyValueProperty" &&
      node.key.value === "position" &&
      node.value.type === "StringLiteral" &&
      !["relative", "absolute"].includes(node.value.value)
    )
      fail("ms/unsupported-css-value", "Only relative/absolute is supported");
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === "object") visit(value);
    }
  }
  visit(ast);
}
function add(file) {
  file = fs.realpathSync(file);
  if (modules.has(file)) return modules.get(file).id;
  const id = modules.size;
  const mod = { id, code: "", file };
  modules.set(file, mod);
  if (file.endsWith(".json")) {
    mod.code = "module.exports=" + fs.readFileSync(file, "utf8");
    return id;
  }
  const source = fs.readFileSync(file, "utf8");
  const typescript = /\.tsx?$/.test(file);
  const parser = {
    syntax: typescript ? "typescript" : "ecmascript",
    tsx: typescript && file.endsWith(".tsx"),
    jsx: !typescript,
  };
  if (!file.includes("node_modules") && !file.startsWith(path.join(repo, "js")))
    lint(swc.parseSync(source, parser), file);
  let { code } = swc.transformSync(source, {
    filename: file,
    swcrc: false,
    configFile: false,
    jsc: {
      parser,
      target: "es2022",
      transform: {
        react: { runtime: "automatic" },
        optimizer: {
          globals: { vars: { "process.env.NODE_ENV": '"production"' } },
        },
      },
    },
    module: { type: "commonjs" },
    sourceMaps: false,
  });
  // SWC normalizes static imports to require calls. Reject dynamic imports and non-literal requires.
  const tree = swc.parseSync(code, { syntax: "ecmascript" });
  const imports = [];
  function scan(node) {
    if (!node || typeof node !== "object") return;
    if (
      node.type === "CallExpression" &&
      (node.callee.type === "Import" || node.callee.value === "require")
    ) {
      const arg = node.arguments[0]?.expression;
      if (node.callee.type === "Import" || arg?.type !== "StringLiteral")
        throw Error(`Dynamic import/require is not supported: ${file}`);
      imports.push(arg.value);
    }
    for (const v of Object.values(node))
      if (Array.isArray(v)) v.forEach(scan);
      else if (v && typeof v === "object") scan(v);
  }
  scan(tree);
  const links = {};
  for (const spec of imports) links[spec] = add(resolve(spec, file));
  mod.code = `const require = spec => __ms_require(${JSON.stringify(links)}[spec]);\n${code}`;
  return id;
}
try {
  const ids = {
    entry: add(path.resolve(project, entry)),
    react: add(deps.resolve("react")),
    reconciler: add(deps.resolve("react-reconciler")),
    shim: add(aliases.remotion),
  };
  if (diagnostics.length) {
    process.stderr.write(JSON.stringify(diagnostics, null, 2) + "\n");
    process.exit(1);
  }
  const factories = [...modules.values()]
    .map((m) => `${m.id}:function(module,exports){\n${m.code}\n}`)
    .join(",\n");
  process.stdout
    .write(`const __ms_factories={${factories}};\nconst __ms_modules={};\nfunction __ms_require(id){
    if(__ms_modules[id])return __ms_modules[id].exports;
    if(!__ms_factories[id])throw Error('Missing module '+id);
    const module={exports:{}}; __ms_modules[id]=module; __ms_factories[id](module,module.exports); return module.exports;
  }\nconst __ms_ids=${JSON.stringify(ids)};\n__ms_start();`);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
