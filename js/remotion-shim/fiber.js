// React Three Fiber subset and @remotion/three's <ThreeCanvas>. R3F intrinsic elements (<mesh>,
// <boxGeometry>, <meshStandardMaterial>, lights…) are committed as ordinary host nodes; the canvas
// serializes them into one scene description that the native Metal renderer draws. Defaults and
// math follow three.js r187 + R3F 8 (ACES filmic tone mapping, sRGB output, color management).
'use strict';
const React = require('react');
const THREE = require('./three');

const ThreeContext = React.createContext(null);

function useThree(selector = state => state) {
  const state = React.useContext(ThreeContext);
  if (!state) throw Error('useThree must be used inside <ThreeCanvas>');
  return selector(state);
}
function useFrame() {
  throw Error('useFrame is not supported: derive animation from useCurrentFrame() so every frame renders independently');
}
function useLoader(loader, input) {
  if (!loader || loader.__msLoader !== 'usd') {
    throw Error('useLoader supports USDLoader/USDZLoader from three/addons/loaders in MotionSwift');
  }
  const load = src => {
    if (typeof src !== 'string' || !src) throw Error('useLoader requires a URL string');
    return modelObject(src);
  };
  return Array.isArray(input) ? input.map(load) : load(input);
}
function modelObject(src) {
  return {isObject3D: true, isGroup: true, __msModel: src, clone() { return modelObject(src); }};
}
function unsupported(name) { return () => { throw Error(name + ' is not supported in MotionSwift; use <ThreeCanvas> from @remotion/three'); }; }

// MARK: Scene serialization

const finite = (value, name) => {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw Error(name + ' must be a finite number');
  return value;
};
const toArray = value => value && typeof value.toArray === 'function' ? value.toArray() : value;
function vector(value, name, scalar) {
  value = toArray(value);
  if (typeof value === 'number' && scalar) return [value, value, value].map(v => finite(v, name));
  if (!Array.isArray(value) || value.length < 3) throw Error(name + ' must be [x, y, z]');
  return value.slice(0, 3).map(v => finite(v, name));
}
function color(value, name) {
  if (Array.isArray(value)) return value.slice(0, 3).map(v => finite(v, name));
  return new THREE.Color().set(value).toArray().map(v => finite(v, name));
}

const TRANSFORM = new Set(['position', 'rotation', 'scale', 'quaternion']);
const IGNORED = new Set(['children', 'key', 'ref', 'name', 'userData', 'castShadow', 'receiveShadow', 'frustumCulled',
  'dispose', 'attach', 'data-ms-src', 'data-ms-timeline', 'raycast']);
function transform(props, kind) {
  const position = new THREE.Vector3(), scale = new THREE.Vector3(1, 1, 1), rotation = new THREE.Euler(),
    quaternion = new THREE.Quaternion();
  rotation._onChange(() => quaternion.setFromEuler(rotation, false));
  quaternion._onChange(() => rotation.setFromQuaternion(quaternion, undefined, false));
  if (kind === 'directional' || kind === 'spot' || kind === 'hemisphere') position.set(0, 1, 0);
  const targets = {position, scale, rotation, quaternion};
  for (const [key, raw] of Object.entries(props)) {
    const pierced = /^(position|rotation|scale|quaternion)-(x|y|z|w)$/.exec(key);
    if (pierced) { targets[pierced[1]][pierced[2]] = finite(raw, key); continue; }
    if (!TRANSFORM.has(key) || raw === undefined) continue;
    const value = toArray(raw);
    if (key === 'rotation') {
      if (!Array.isArray(value) || value.length < 3) throw Error('rotation must be [x, y, z] or an Euler');
      rotation.set(finite(value[0], key), finite(value[1], key), finite(value[2], key), value[3] || 'XYZ');
    } else if (key === 'quaternion') {
      if (!Array.isArray(value) || value.length !== 4) throw Error('quaternion must be [x, y, z, w]');
      quaternion.set(...value.map(v => finite(v, key)));
    } else targets[key].set(...vector(value, key, true));
  }
  return {position: position.toArray(), quaternion: quaternion.toArray(), scale: scale.toArray()};
}

const GEOMETRIES = {
  boxGeometry: 'box', sphereGeometry: 'sphere', planeGeometry: 'plane', cylinderGeometry: 'cylinder',
  coneGeometry: 'cone', torusGeometry: 'torus', torusKnotGeometry: 'torusKnot', circleGeometry: 'circle',
  ringGeometry: 'ring', icosahedronGeometry: 'icosahedron', octahedronGeometry: 'octahedron',
  tetrahedronGeometry: 'tetrahedron', dodecahedronGeometry: 'dodecahedron',
};
const MATERIALS = {
  meshBasicMaterial: 'basic', meshLambertMaterial: 'lambert', meshPhongMaterial: 'phong',
  meshStandardMaterial: 'standard', meshPhysicalMaterial: 'physical', meshNormalMaterial: 'normal',
};
const LIGHTS = {ambientLight: 'ambient', hemisphereLight: 'hemisphere', directionalLight: 'directional',
  pointLight: 'point', spotLight: 'spot'};

function geometry(node) {
  const props = node.props;
  for (const key of Object.keys(props)) if (key !== 'args' && !IGNORED.has(key)) throw Error(`<${node.type}> property ${key} is not supported`);
  const args = (props.args || []).map((value, index) => typeof value === 'boolean' ? (value ? 1 : 0) : finite(value, `${node.type} args[${index}]`));
  return {type: GEOMETRIES[node.type], args};
}

const MATERIAL_PROPS = new Set(['color', 'emissive', 'emissiveIntensity', 'roughness', 'metalness', 'opacity', 'transparent',
  'side', 'flatShading', 'specular', 'shininess', 'toneMapped', 'depthTest', 'depthWrite', 'fog', 'ior', 'visible', 'args']);
function material(node) {
  const type = MATERIALS[node.type];
  const props = {...(node.props.args?.[0] || {}), ...node.props};
  for (const [key, value] of Object.entries(props)) {
    if (IGNORED.has(key)) continue;
    if (key === 'wireframe' || key === 'vertexColors') { if (value) throw Error(`${node.type}.${key} is not supported`); continue; }
    if (!MATERIAL_PROPS.has(key)) throw Error(`${node.type} property ${key} is not supported`);
  }
  const bool = (key, fallback) => props[key] === undefined ? fallback : !!props[key];
  const num = (key, fallback) => props[key] === undefined ? fallback : finite(props[key], `${node.type}.${key}`);
  const side = num('side', 0);
  if (![0, 1, 2].includes(side)) throw Error('material side must be FrontSide, BackSide or DoubleSide');
  return {
    type, color: color(props.color ?? 0xffffff, 'color'), emissive: color(props.emissive ?? 0x000000, 'emissive'),
    emissiveIntensity: num('emissiveIntensity', 1), roughness: num('roughness', 1), metalness: num('metalness', 0),
    opacity: num('opacity', 1), transparent: bool('transparent', false), side, flatShading: bool('flatShading', false),
    specular: color(props.specular ?? 0x111111, 'specular'), shininess: num('shininess', 30),
    toneMapped: bool('toneMapped', true), depthTest: bool('depthTest', true), depthWrite: bool('depthWrite', true),
    fog: type !== 'normal' && bool('fog', true), ior: num('ior', 1.5), visible: bool('visible', true),
  };
}

const LIGHT_ARGS = {
  ambient: ['color', 'intensity'], directional: ['color', 'intensity'], point: ['color', 'intensity', 'distance', 'decay'],
  spot: ['color', 'intensity', 'distance', 'angle', 'penumbra', 'decay'], hemisphere: ['color', 'groundColor', 'intensity'],
};
const LIGHT_PROPS = new Set(['color', 'groundColor', 'intensity', 'distance', 'decay', 'angle', 'penumbra', 'visible', 'args']);
function light(node, kind) {
  const props = {};
  (node.props.args || []).forEach((value, index) => { if (value !== undefined) props[LIGHT_ARGS[kind][index]] = value; });
  for (const [key, value] of Object.entries(node.props)) {
    if (key === 'args' || TRANSFORM.has(key) || /^(position|rotation|scale|quaternion)-/.test(key) || IGNORED.has(key) || key.startsWith('shadow')) continue;
    if (key === 'target') throw Error('Light targets are not supported; directional and spot lights aim at the origin');
    if (!LIGHT_PROPS.has(key)) throw Error(`<${node.type}> property ${key} is not supported`);
    props[key] = value;
  }
  const num = (key, fallback) => props[key] === undefined ? fallback : finite(props[key], `${node.type}.${key}`);
  return {
    color: color(props.color ?? 0xffffff, 'color'), groundColor: color(props.groundColor ?? 0xffffff, 'groundColor'),
    intensity: num('intensity', 1), distance: num('distance', 0), decay: num('decay', 2),
    angle: num('angle', Math.PI / 3), penumbra: num('penumbra', 0),
  };
}

function objectProps(node, allowed) {
  for (const [key, value] of Object.entries(node.props)) {
    if (IGNORED.has(key) || TRANSFORM.has(key) || allowed.has(key) || /^(position|rotation|scale|quaternion)-[xyzw]$/.test(key)) continue;
    if (key.startsWith('on') && typeof value === 'function') continue;
    throw Error(`<${node.type}> property ${key} is not supported in ThreeCanvas`);
  }
}

function serializeObject(node, scene) {
  if (node.type === '#text') throw Error('Text is not allowed inside <ThreeCanvas>');
  const props = node.props;
  const base = {visible: props.visible === undefined ? true : !!props.visible,
    renderOrder: props.renderOrder === undefined ? 0 : finite(props.renderOrder, 'renderOrder')};
  const children = [];
  const visitChildren = (exclude = () => false) => node.children.forEach(child => {
    if (exclude(child)) return;
    const value = serializeObject(child, scene);
    if (value) children.push(value);
  });
  if (node.type === 'color' && props.attach === 'background') { scene.background = color(props.args?.[0] ?? props.color, 'background'); return null; }
  if ((node.type === 'fog' || node.type === 'fogExp2') && props.attach === 'fog') {
    const [value, a, b] = props.args || [];
    scene.fog = node.type === 'fog'
      ? {type: 'linear', color: color(value, 'fog color'), near: finite(a ?? 1, 'fog near'), far: finite(b ?? 1000, 'fog far'), density: 0}
      : {type: 'exp2', color: color(value, 'fog color'), near: 0, far: 0, density: finite(a ?? 0.00025, 'fog density')};
    return null;
  }
  if (GEOMETRIES[node.type] || MATERIALS[node.type]) throw Error(`<${node.type}> must be a direct child of <mesh>`);
  if (node.type === 'group' || node.type === 'object3D') {
    objectProps(node, new Set(['visible', 'renderOrder']));
    visitChildren();
    return {kind: 'group', ...transform(props, 'group'), ...base, children};
  }
  if (node.type === 'mesh') {
    objectProps(node, new Set(['visible', 'renderOrder']));
    let geometryValue = null, materialValue = null;
    visitChildren(child => {
      if (GEOMETRIES[child.type]) { geometryValue = geometry(child); return true; }
      if (MATERIALS[child.type]) { materialValue = material(child); return true; }
      return false;
    });
    if (!geometryValue) throw Error('<mesh> requires a geometry child such as <boxGeometry>');
    return {kind: 'mesh', ...transform(props, 'mesh'), ...base, geometry: geometryValue,
      material: materialValue || material({type: 'meshBasicMaterial', props: {}}), children};
  }
  if (node.type === 'primitive') {
    const object = props.object;
    if (!object || typeof object.__msModel !== 'string') throw Error('<primitive> supports objects returned by useLoader(USDLoader, url)');
    objectProps(node, new Set(['object', 'visible', 'renderOrder']));
    visitChildren();
    return {kind: 'model', src: object.__msModel, ...transform(props, 'model'), ...base, children};
  }
  if (LIGHTS[node.type]) {
    const kind = LIGHTS[node.type];
    visitChildren();
    return {kind, ...transform(props, kind), ...base, light: light(node, kind), children};
  }
  if (node.type === 'perspectiveCamera' || node.type === 'orthographicCamera') {
    throw Error(`<${node.type}> is not supported; aim the default camera with useThree(state => state.camera)`);
  }
  throw Error(`<${node.type}> is not supported inside <ThreeCanvas>`);
}

function serialize(state, node) {
  const scene = {background: null, fog: null};
  const objects = [];
  for (const child of node.children) {
    const value = serializeObject(child, scene);
    if (value) objects.push(value);
  }
  const camera = state.camera;
  const position = vector(camera.position, 'camera.position');
  const quaternion = camera.quaternion.toArray().map(v => finite(v, 'camera.quaternion'));
  return JSON.stringify({
    width: state.size.width, height: state.size.height, dpr: state.dpr, flat: state.flat,
    background: scene.background, fog: scene.fog,
    camera: {fov: finite(camera.fov, 'camera.fov'), near: finite(camera.near, 'camera.near'), far: finite(camera.far, 'camera.far'),
      zoom: finite(camera.zoom, 'camera.zoom'), aspect: camera.manual ? finite(camera.aspect, 'camera.aspect') : null,
      position, quaternion},
    objects,
  });
}

// MARK: <ThreeCanvas>

const CAMERA_OPTIONS = new Set(['fov', 'near', 'far', 'zoom', 'position', 'rotation', 'up', 'aspect', 'quaternion']);
function createCamera(options = {}, width, height) {
  if (options instanceof THREE.PerspectiveCamera) return options;
  const camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
  camera.position.z = 5;
  for (const [key, value] of Object.entries(options)) {
    if (!CAMERA_OPTIONS.has(key)) throw Error('ThreeCanvas camera option ' + key + ' is not supported');
    if (key === 'rotation') { const r = toArray(value); camera.rotation.set(r[0], r[1], r[2], r[3] || 'XYZ'); }
    else if (key === 'quaternion') camera.quaternion.set(...toArray(value));
    else if (key === 'position' || key === 'up') camera[key].set(...vector(value, 'camera.' + key));
    else camera[key] = finite(value, 'camera.' + key);
  }
  if ('aspect' in options) camera.manual = true;
  if (!options.rotation && !options.quaternion) camera.lookAt(0, 0, 0);
  return camera;
}

function ThreeCanvas({width, height, style, children, camera, flat = false, linear = false, legacy = false, dpr = [1, 2],
  shadows, orthographic, gl, scene, onCreated, frameloop, resize, events, raycaster, eventSource, eventPrefix,
  onPointerMissed, performance: _performance, ...rest}) {
  for (const [name, value] of [['width', width], ['height', height]]) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
      throw Error(`The "${name}" prop of the <ThreeCanvas /> component must be a positive number`);
    }
  }
  if (linear || legacy) throw Error('ThreeCanvas linear/legacy color management is not supported');
  if (shadows) throw Error('ThreeCanvas shadows are not supported by the native renderer yet');
  if (orthographic) throw Error('Orthographic ThreeCanvas cameras are not supported yet');
  if (scene) throw Error('The ThreeCanvas scene prop is not supported; use <color attach="background"> and <fog attach="fog">');
  for (const key of Object.keys(rest)) if (!IGNORED.has(key)) throw Error('ThreeCanvas property ' + key + ' is not supported');
  const dprRange = (Array.isArray(dpr) ? dpr : [dpr, dpr]).map(value => finite(value, 'dpr'));
  const state = React.useMemo(() => {
    const value = {size: {width, height, top: 0, left: 0}, flat: !!flat, dpr: dprRange,
      invalidate() {}, advance() {}, setSize() {}, setDpr() {}, setFrameloop() {}, gl: null, frameloop: 'never'};
    value.camera = createCamera(camera, width, height);
    value.scene = {isScene: true};
    value.viewport = {width, height, aspect: width / height, dpr: dprRange[0], factor: 1, distance: 0};
    value.set = partial => {
      const next = typeof partial === 'function' ? partial(value) : partial;
      if (next.camera && !(next.camera instanceof THREE.PerspectiveCamera)) throw Error('useThree().set supports PerspectiveCamera only');
      Object.assign(value, next);
    };
    value.get = () => value;
    return value;
  // Remotion creates the R3F root once; camera options are applied only when it is created.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  if (!state.camera.manual) state.camera.aspect = width / height;
  state.size = {width, height, top: 0, left: 0};
  React.useLayoutEffect(() => { if (onCreated) onCreated(state); }, []);
  return React.createElement('ms-three', {
    style: {width, height, ...style},
    __msScene: node => serialize(state, node),
  }, React.createElement(ThreeContext.Provider, {value: state}, children));
}

module.exports = {
  ThreeCanvas, useThree, useFrame, useLoader, Canvas: unsupported('Canvas'), extend: unsupported('extend'),
  createRoot: unsupported('createRoot'), useVideoTexture: unsupported('useVideoTexture'),
  useOffthreadVideoTexture: unsupported('useOffthreadVideoTexture'),
  // Exposed for tests: serialize a committed host subtree with a given canvas state.
  __serialize: serialize, __createCamera: createCamera,
};
