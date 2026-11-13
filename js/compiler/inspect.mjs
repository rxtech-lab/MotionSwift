import {parse} from '@babel/parser';
const THREE_ELEMENTS = new Set(['group', 'object3D', 'mesh', 'primitive', 'ambientLight', 'directionalLight', 'pointLight',
  'spotLight', 'hemisphereLight', 'color', 'fog', 'fogExp2', 'boxGeometry', 'sphereGeometry', 'planeGeometry',
  'cylinderGeometry', 'coneGeometry', 'torusGeometry', 'torusKnotGeometry', 'circleGeometry', 'ringGeometry',
  'icosahedronGeometry', 'octahedronGeometry', 'tetrahedronGeometry', 'dodecahedronGeometry', 'meshBasicMaterial',
  'meshLambertMaterial', 'meshPhongMaterial', 'meshStandardMaterial', 'meshPhysicalMaterial', 'meshNormalMaterial']);
export function inspect(source, file, subset) {
  const diagnostics = [];
  function lint(ast, file) {
    function visit(node) {
      if (!node || typeof node !== "object") return;
      const fail = (rule, message) => diagnostics.push({ rule, file, message });
      if (node.type === "JSXOpeningElement") {
        const name = node.name.name;
        if (["perspectiveCamera", "orthographicCamera"].includes(name))
          fail(
            "ms/unsupported-element",
            `${name} is not supported; aim the ThreeCanvas camera with useThree(state => state.camera)`,
          );
        else if (["video", "audio"].includes(name))
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
            "ellipse", "text", "radialGradient", "linearGradient", "stop", "pattern"].includes(name) &&
          // React Three Fiber elements; the native 3D renderer validates their props inside <ThreeCanvas>.
          !THREE_ELEMENTS.has(name)
        )
          fail("ms/unsupported-element", `${name} is not implemented`);
        for (const attr of node.attributes || [])
          if (["className", "dangerouslySetInnerHTML"].includes(attr.name?.name))
            fail("ms/no-classname", "Only inline styles are supported");
      }
      if (
        node.type === "ObjectProperty" &&
        (node.key.value ?? node.key.name) === "display" &&
        node.value.type === "StringLiteral" &&
        !["flex", "none"].includes(node.value.value)
      )
        fail("ms/unsupported-css-value", "Only flex/none is supported");
      if (
        node.type === "ObjectProperty" &&
        (node.key.value ?? node.key.name) === "position" &&
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
  const tree = parse(source, {sourceType: 'unambiguous', plugins: ['typescript', 'jsx'], createImportExpressions: true});
  if (subset) lint(tree, file);
  function scan(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'ImportExpression' || (node.type === 'CallExpression' && node.callee?.name === 'require' &&
        (node.arguments.length !== 1 || node.arguments[0]?.type !== 'StringLiteral'))) {
      throw Error('Dynamic import/require is not supported: ' + file);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(scan);
      else if (value && typeof value === 'object') scan(value);
    }
  }
  scan(tree);
  return JSON.stringify(diagnostics);
}
