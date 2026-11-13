// Shared by source inspection and playback: editor keys map to R3F props, never CSS.
'use strict';
const transforms = ['position', 'rotation', 'scale'];
const objects = ['group', 'object3D', 'mesh', 'primitive', 'ambientLight', 'hemisphereLight',
  'directionalLight', 'pointLight', 'spotLight'];
const materials = ['meshBasicMaterial', 'meshLambertMaterial', 'meshPhongMaterial',
  'meshStandardMaterial', 'meshPhysicalMaterial', 'meshNormalMaterial'];
function fields(type) {
  const result = [];
  if (typeof type !== 'string') return result;
  const add = (key, path, fallback) => result.push({key, path, fallback});
  if (objects.includes(type)) {
    for (const name of transforms) for (const [index, axis] of ['X', 'Y', 'Z'].entries())
      add(name + axis, [name, index], name === 'scale' ? 1 :
        name === 'position' && index === 1 && ['hemisphereLight', 'directionalLight', 'spotLight'].includes(type) ? 1 : 0);
  }
  if (type.endsWith('Light')) {
    add('intensity', ['intensity'], 1);
    add('color', ['color'], '#ffffff');
    if (['pointLight', 'spotLight'].includes(type)) {
      add('distance', ['distance'], 0); add('decay', ['decay'], 2);
    }
    if (type === 'spotLight') { add('angle', ['angle'], Math.PI / 3); add('penumbra', ['penumbra'], 0); }
  }
  if (materials.includes(type)) {
    add('color', ['color'], '#ffffff'); add('opacity', ['opacity'], 1);
    if (['meshStandardMaterial', 'meshPhysicalMaterial'].includes(type)) {
      add('roughness', ['roughness'], 1); add('metalness', ['metalness'], 0);
    }
    if (type === 'meshPhongMaterial') add('shininess', ['shininess'], 30);
    if (type === 'meshPhysicalMaterial') add('ior', ['ior'], 1.5);
  }
  if (type === 'ThreeCanvas') {
    for (const [index, axis] of ['X', 'Y', 'Z'].entries()) add('cameraPosition' + axis, ['camera', 'position', index], index === 2 ? 5 : 0);
    for (const [index, axis] of ['X', 'Y', 'Z'].entries()) add('cameraRotation' + axis, ['camera', 'rotation', index], 0);
    add('cameraFov', ['camera', 'fov'], 75); add('cameraZoom', ['camera', 'zoom'], 1);
  }
  return result;
}
function values(type, props) {
  const result = {};
  for (const field of fields(type)) {
    let value = props;
    for (const part of field.path) value = typeof value === 'number' && typeof part === 'number' ? value : value?.[part];
    const pierced = field.path.length === 2 ? props[field.path[0] + '-' + 'xyz'[field.path[1]]] : undefined;
    value = pierced === undefined ? value : pierced;
    if (value === undefined) value = field.fallback;
    if (typeof value === 'number' || typeof value === 'string') result[field.key] = value;
  }
  return result;
}
function animate(type, props, key, value) {
  const field = fields(type).find(field => field.key === key);
  if (!field) throw Error('Unsupported 3D keyframe property: ' + key);
  if (field.path[0] === 'camera') {
    props.camera = {...props.camera};
    if (field.path.length === 3) {
      const name = field.path[1];
      props.camera[name] = [...(props.camera[name] || (name === 'position' ? [0, 0, 5] : [0, 0, 0]))];
      props.camera[name][field.path[2]] = value;
    } else props.camera[field.path[1]] = value;
  } else if (field.path.length === 2) props[field.path[0] + '-' + 'xyz'[field.path[1]]] = value;
  else props[field.path[0]] = value;
}
module.exports = {fields, values, animate, isThree: type => fields(type).length > 0};
