// A deliberately small subset of `three` for MotionSwift compositions. Math mirrors three.js r187
// in float64 so scene descriptions match what a WebGL render would compute. Rendering objects,
// textures and loaders other than the USD tags are not provided; use R3F JSX elements instead.
'use strict';
const DEG2RAD = Math.PI / 180, RAD2DEG = 180 / Math.PI;
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const MathUtils = {
  DEG2RAD, RAD2DEG, clamp,
  degToRad: degrees => degrees * DEG2RAD,
  radToDeg: radians => radians * RAD2DEG,
  lerp: (x, y, t) => (1 - t) * x + t * y,
  inverseLerp: (x, y, value) => x !== y ? (value - x) / (y - x) : 0,
  mapLinear: (x, a1, a2, b1, b2) => b1 + (x - a1) * (b2 - b1) / (a2 - a1),
  euclideanModulo: (n, m) => ((n % m) + m) % m,
  smoothstep: (x, min, max) => { if (x <= min) return 0; if (x >= max) return 1; x = (x - min) / (max - min); return x * x * (3 - 2 * x); },
  smootherstep: (x, min, max) => { if (x <= min) return 0; if (x >= max) return 1; x = (x - min) / (max - min); return x * x * x * (x * (x * 6 - 15) + 10); },
  pingpong: (x, length = 1) => length - Math.abs(((x % (length * 2)) + length * 2) % (length * 2) - length),
};

class Vector3 {
  constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; }
  get isVector3() { return true; }
  set(x, y, z) { if (z === undefined) z = this.z; this.x = x; this.y = y; this.z = z; return this; }
  setScalar(s) { this.x = this.y = this.z = s; return this; }
  setX(x) { this.x = x; return this; } setY(y) { this.y = y; return this; } setZ(z) { this.z = z; return this; }
  copy(v) { this.x = v.x; this.y = v.y; this.z = v.z; return this; }
  clone() { return new Vector3(this.x, this.y, this.z); }
  add(v) { this.x += v.x; this.y += v.y; this.z += v.z; return this; }
  addScalar(s) { this.x += s; this.y += s; this.z += s; return this; }
  addVectors(a, b) { this.x = a.x + b.x; this.y = a.y + b.y; this.z = a.z + b.z; return this; }
  addScaledVector(v, s) { this.x += v.x * s; this.y += v.y * s; this.z += v.z * s; return this; }
  sub(v) { this.x -= v.x; this.y -= v.y; this.z -= v.z; return this; }
  subVectors(a, b) { this.x = a.x - b.x; this.y = a.y - b.y; this.z = a.z - b.z; return this; }
  multiplyScalar(s) { this.x *= s; this.y *= s; this.z *= s; return this; }
  divideScalar(s) { return this.multiplyScalar(1 / s); }
  negate() { this.x = -this.x; this.y = -this.y; this.z = -this.z; return this; }
  dot(v) { return this.x * v.x + this.y * v.y + this.z * v.z; }
  lengthSq() { return this.x * this.x + this.y * this.y + this.z * this.z; }
  length() { return Math.sqrt(this.lengthSq()); }
  normalize() { return this.divideScalar(this.length() || 1); }
  setLength(l) { return this.normalize().multiplyScalar(l); }
  distanceTo(v) { return Math.sqrt((this.x - v.x) ** 2 + (this.y - v.y) ** 2 + (this.z - v.z) ** 2); }
  lerp(v, a) { this.x += (v.x - this.x) * a; this.y += (v.y - this.y) * a; this.z += (v.z - this.z) * a; return this; }
  lerpVectors(a, b, t) { this.x = a.x + (b.x - a.x) * t; this.y = a.y + (b.y - a.y) * t; this.z = a.z + (b.z - a.z) * t; return this; }
  cross(v) { return this.crossVectors(this, v); }
  crossVectors(a, b) {
    const ax = a.x, ay = a.y, az = a.z, bx = b.x, by = b.y, bz = b.z;
    this.x = ay * bz - az * by; this.y = az * bx - ax * bz; this.z = ax * by - ay * bx; return this;
  }
  applyQuaternion(q) {
    const vx = this.x, vy = this.y, vz = this.z, qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    const tx = 2 * (qy * vz - qz * vy), ty = 2 * (qz * vx - qx * vz), tz = 2 * (qx * vy - qy * vx);
    this.x = vx + qw * tx + qy * tz - qz * ty; this.y = vy + qw * ty + qz * tx - qx * tz; this.z = vz + qw * tz + qx * ty - qy * tx;
    return this;
  }
  applyEuler(euler) { return this.applyQuaternion(new Quaternion().setFromEuler(euler)); }
  setFromSphericalCoords(radius, phi, theta) {
    const s = Math.sin(phi) * radius;
    this.x = s * Math.sin(theta); this.y = Math.cos(phi) * radius; this.z = s * Math.cos(theta); return this;
  }
  setFromCylindricalCoords(radius, theta, y) { this.x = radius * Math.sin(theta); this.y = y; this.z = radius * Math.cos(theta); return this; }
  equals(v) { return v.x === this.x && v.y === this.y && v.z === this.z; }
  fromArray(array, offset = 0) { this.x = array[offset]; this.y = array[offset + 1]; this.z = array[offset + 2]; return this; }
  toArray() { return [this.x, this.y, this.z]; }
  *[Symbol.iterator]() { yield this.x; yield this.y; yield this.z; }
}

class Vector2 {
  constructor(x = 0, y = 0) { this.x = x; this.y = y; }
  set(x, y) { this.x = x; this.y = y; return this; }
  toArray() { return [this.x, this.y]; }
}

class Quaternion {
  constructor(x = 0, y = 0, z = 0, w = 1) { this._x = x; this._y = y; this._z = z; this._w = w; this._onChangeCallback = () => {}; }
  get isQuaternion() { return true; }
  get x() { return this._x; } set x(v) { this._x = v; this._onChangeCallback(); }
  get y() { return this._y; } set y(v) { this._y = v; this._onChangeCallback(); }
  get z() { return this._z; } set z(v) { this._z = v; this._onChangeCallback(); }
  get w() { return this._w; } set w(v) { this._w = v; this._onChangeCallback(); }
  set(x, y, z, w) { this._x = x; this._y = y; this._z = z; this._w = w; this._onChangeCallback(); return this; }
  copy(q) { this._x = q.x; this._y = q.y; this._z = q.z; this._w = q.w; this._onChangeCallback(); return this; }
  clone() { return new Quaternion(this._x, this._y, this._z, this._w); }
  identity() { return this.set(0, 0, 0, 1); }
  setFromEuler(euler, update = true) {
    const x = euler._x, y = euler._y, z = euler._z, order = euler._order;
    const c1 = Math.cos(x / 2), c2 = Math.cos(y / 2), c3 = Math.cos(z / 2);
    const s1 = Math.sin(x / 2), s2 = Math.sin(y / 2), s3 = Math.sin(z / 2);
    switch (order) {
      case 'XYZ': this._x = s1*c2*c3 + c1*s2*s3; this._y = c1*s2*c3 - s1*c2*s3; this._z = c1*c2*s3 + s1*s2*c3; this._w = c1*c2*c3 - s1*s2*s3; break;
      case 'YXZ': this._x = s1*c2*c3 + c1*s2*s3; this._y = c1*s2*c3 - s1*c2*s3; this._z = c1*c2*s3 - s1*s2*c3; this._w = c1*c2*c3 + s1*s2*s3; break;
      case 'ZXY': this._x = s1*c2*c3 - c1*s2*s3; this._y = c1*s2*c3 + s1*c2*s3; this._z = c1*c2*s3 + s1*s2*c3; this._w = c1*c2*c3 - s1*s2*s3; break;
      case 'ZYX': this._x = s1*c2*c3 - c1*s2*s3; this._y = c1*s2*c3 + s1*c2*s3; this._z = c1*c2*s3 - s1*s2*c3; this._w = c1*c2*c3 + s1*s2*s3; break;
      case 'YZX': this._x = s1*c2*c3 + c1*s2*s3; this._y = c1*s2*c3 + s1*c2*s3; this._z = c1*c2*s3 - s1*s2*c3; this._w = c1*c2*c3 - s1*s2*s3; break;
      case 'XZY': this._x = s1*c2*c3 - c1*s2*s3; this._y = c1*s2*c3 - s1*c2*s3; this._z = c1*c2*s3 + s1*s2*c3; this._w = c1*c2*c3 + s1*s2*s3; break;
      default: throw Error('Unknown Euler order: ' + order);
    }
    if (update) this._onChangeCallback();
    return this;
  }
  setFromAxisAngle(axis, angle) {
    const half = angle / 2, s = Math.sin(half);
    this._x = axis.x * s; this._y = axis.y * s; this._z = axis.z * s; this._w = Math.cos(half);
    this._onChangeCallback(); return this;
  }
  // `te` is a column-major Matrix4 element array; the upper 3x3 must be a pure rotation.
  setFromRotationMatrix(m) {
    const te = m.elements, m11 = te[0], m12 = te[4], m13 = te[8], m21 = te[1], m22 = te[5], m23 = te[9],
      m31 = te[2], m32 = te[6], m33 = te[10], trace = m11 + m22 + m33;
    if (trace > 0) {
      const s = 0.5 / Math.sqrt(trace + 1.0);
      this._w = 0.25 / s; this._x = (m32 - m23) * s; this._y = (m13 - m31) * s; this._z = (m21 - m12) * s;
    } else if (m11 > m22 && m11 > m33) {
      const s = 2.0 * Math.sqrt(1.0 + m11 - m22 - m33);
      this._w = (m32 - m23) / s; this._x = 0.25 * s; this._y = (m12 + m21) / s; this._z = (m13 + m31) / s;
    } else if (m22 > m33) {
      const s = 2.0 * Math.sqrt(1.0 + m22 - m11 - m33);
      this._w = (m13 - m31) / s; this._x = (m12 + m21) / s; this._y = 0.25 * s; this._z = (m23 + m32) / s;
    } else {
      const s = 2.0 * Math.sqrt(1.0 + m33 - m11 - m22);
      this._w = (m21 - m12) / s; this._x = (m13 + m31) / s; this._y = (m23 + m32) / s; this._z = 0.25 * s;
    }
    this._onChangeCallback(); return this;
  }
  multiply(q) { return this.multiplyQuaternions(this, q); }
  premultiply(q) { return this.multiplyQuaternions(q, this); }
  multiplyQuaternions(a, b) {
    const qax = a._x, qay = a._y, qaz = a._z, qaw = a._w, qbx = b._x, qby = b._y, qbz = b._z, qbw = b._w;
    this._x = qax * qbw + qaw * qbx + qay * qbz - qaz * qby;
    this._y = qay * qbw + qaw * qby + qaz * qbx - qax * qbz;
    this._z = qaz * qbw + qaw * qbz + qax * qby - qay * qbx;
    this._w = qaw * qbw - qax * qbx - qay * qby - qaz * qbz;
    this._onChangeCallback(); return this;
  }
  _onChange(callback) { this._onChangeCallback = callback; return this; }
  toArray() { return [this._x, this._y, this._z, this._w]; }
}

class Matrix4 {
  constructor() { this.elements = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]; }
  makeRotationFromQuaternion(q) {
    const te = this.elements, x = q.x, y = q.y, z = q.z, w = q.w;
    const x2 = x + x, y2 = y + y, z2 = z + z, xx = x * x2, xy = x * y2, xz = x * z2;
    const yy = y * y2, yz = y * z2, zz = z * z2, wx = w * x2, wy = w * y2, wz = w * z2;
    te[0] = 1 - (yy + zz); te[4] = xy - wz; te[8] = xz + wy;
    te[1] = xy + wz; te[5] = 1 - (xx + zz); te[9] = yz - wx;
    te[2] = xz - wy; te[6] = yz + wx; te[10] = 1 - (xx + yy);
    te[3] = te[7] = te[11] = te[12] = te[13] = te[14] = 0; te[15] = 1;
    return this;
  }
  lookAt(eye, target, up) {
    const te = this.elements, x = new Vector3(), y = new Vector3(), z = new Vector3();
    z.subVectors(eye, target);
    if (z.lengthSq() === 0) z.z = 1;
    z.normalize();
    x.crossVectors(up, z);
    if (x.lengthSq() === 0) {
      if (Math.abs(up.z) === 1) z.x += 0.0001; else z.z += 0.0001;
      z.normalize(); x.crossVectors(up, z);
    }
    x.normalize(); y.crossVectors(z, x);
    te[0] = x.x; te[4] = y.x; te[8] = z.x; te[1] = x.y; te[5] = y.y; te[9] = z.y; te[2] = x.z; te[6] = y.z; te[10] = z.z;
    return this;
  }
}

class Euler {
  constructor(x = 0, y = 0, z = 0, order = 'XYZ') { this._x = x; this._y = y; this._z = z; this._order = order; this._onChangeCallback = () => {}; }
  get isEuler() { return true; }
  get x() { return this._x; } set x(v) { this._x = v; this._onChangeCallback(); }
  get y() { return this._y; } set y(v) { this._y = v; this._onChangeCallback(); }
  get z() { return this._z; } set z(v) { this._z = v; this._onChangeCallback(); }
  get order() { return this._order; } set order(v) { this._order = v; this._onChangeCallback(); }
  set(x, y, z, order = this._order) { this._x = x; this._y = y; this._z = z; this._order = order; this._onChangeCallback(); return this; }
  copy(e) { return this.set(e._x, e._y, e._z, e._order); }
  clone() { return new Euler(this._x, this._y, this._z, this._order); }
  setFromRotationMatrix(m, order = this._order, update = true) {
    const te = m.elements, m11 = te[0], m12 = te[4], m13 = te[8], m21 = te[1], m22 = te[5], m23 = te[9],
      m31 = te[2], m32 = te[6], m33 = te[10];
    switch (order) {
      case 'XYZ':
        this._y = Math.asin(clamp(m13, -1, 1));
        if (Math.abs(m13) < 0.9999999) { this._x = Math.atan2(-m23, m33); this._z = Math.atan2(-m12, m11); }
        else { this._x = Math.atan2(m32, m22); this._z = 0; }
        break;
      case 'YXZ':
        this._x = Math.asin(-clamp(m23, -1, 1));
        if (Math.abs(m23) < 0.9999999) { this._y = Math.atan2(m13, m33); this._z = Math.atan2(m21, m22); }
        else { this._y = Math.atan2(-m31, m11); this._z = 0; }
        break;
      default: throw Error('Euler.setFromRotationMatrix supports XYZ and YXZ orders in MotionSwift');
    }
    this._order = order;
    if (update) this._onChangeCallback();
    return this;
  }
  setFromQuaternion(q, order, update) { return this.setFromRotationMatrix(new Matrix4().makeRotationFromQuaternion(q), order, update); }
  _onChange(callback) { this._onChangeCallback = callback; return this; }
  toArray() { return [this._x, this._y, this._z, this._order]; }
}
const _colorKeywords = { 'aliceblue': 0xF0F8FF, 'antiquewhite': 0xFAEBD7, 'aqua': 0x00FFFF, 'aquamarine': 0x7FFFD4, 'azure': 0xF0FFFF,
	'beige': 0xF5F5DC, 'bisque': 0xFFE4C4, 'black': 0x000000, 'blanchedalmond': 0xFFEBCD, 'blue': 0x0000FF, 'blueviolet': 0x8A2BE2,
	'brown': 0xA52A2A, 'burlywood': 0xDEB887, 'cadetblue': 0x5F9EA0, 'chartreuse': 0x7FFF00, 'chocolate': 0xD2691E, 'coral': 0xFF7F50,
	'cornflowerblue': 0x6495ED, 'cornsilk': 0xFFF8DC, 'crimson': 0xDC143C, 'cyan': 0x00FFFF, 'darkblue': 0x00008B, 'darkcyan': 0x008B8B,
	'darkgoldenrod': 0xB8860B, 'darkgray': 0xA9A9A9, 'darkgreen': 0x006400, 'darkgrey': 0xA9A9A9, 'darkkhaki': 0xBDB76B, 'darkmagenta': 0x8B008B,
	'darkolivegreen': 0x556B2F, 'darkorange': 0xFF8C00, 'darkorchid': 0x9932CC, 'darkred': 0x8B0000, 'darksalmon': 0xE9967A, 'darkseagreen': 0x8FBC8F,
	'darkslateblue': 0x483D8B, 'darkslategray': 0x2F4F4F, 'darkslategrey': 0x2F4F4F, 'darkturquoise': 0x00CED1, 'darkviolet': 0x9400D3,
	'deeppink': 0xFF1493, 'deepskyblue': 0x00BFFF, 'dimgray': 0x696969, 'dimgrey': 0x696969, 'dodgerblue': 0x1E90FF, 'firebrick': 0xB22222,
	'floralwhite': 0xFFFAF0, 'forestgreen': 0x228B22, 'fuchsia': 0xFF00FF, 'gainsboro': 0xDCDCDC, 'ghostwhite': 0xF8F8FF, 'gold': 0xFFD700,
	'goldenrod': 0xDAA520, 'gray': 0x808080, 'green': 0x008000, 'greenyellow': 0xADFF2F, 'grey': 0x808080, 'honeydew': 0xF0FFF0, 'hotpink': 0xFF69B4,
	'indianred': 0xCD5C5C, 'indigo': 0x4B0082, 'ivory': 0xFFFFF0, 'khaki': 0xF0E68C, 'lavender': 0xE6E6FA, 'lavenderblush': 0xFFF0F5, 'lawngreen': 0x7CFC00,
	'lemonchiffon': 0xFFFACD, 'lightblue': 0xADD8E6, 'lightcoral': 0xF08080, 'lightcyan': 0xE0FFFF, 'lightgoldenrodyellow': 0xFAFAD2, 'lightgray': 0xD3D3D3,
	'lightgreen': 0x90EE90, 'lightgrey': 0xD3D3D3, 'lightpink': 0xFFB6C1, 'lightsalmon': 0xFFA07A, 'lightseagreen': 0x20B2AA, 'lightskyblue': 0x87CEFA,
	'lightslategray': 0x778899, 'lightslategrey': 0x778899, 'lightsteelblue': 0xB0C4DE, 'lightyellow': 0xFFFFE0, 'lime': 0x00FF00, 'limegreen': 0x32CD32,
	'linen': 0xFAF0E6, 'magenta': 0xFF00FF, 'maroon': 0x800000, 'mediumaquamarine': 0x66CDAA, 'mediumblue': 0x0000CD, 'mediumorchid': 0xBA55D3,
	'mediumpurple': 0x9370DB, 'mediumseagreen': 0x3CB371, 'mediumslateblue': 0x7B68EE, 'mediumspringgreen': 0x00FA9A, 'mediumturquoise': 0x48D1CC,
	'mediumvioletred': 0xC71585, 'midnightblue': 0x191970, 'mintcream': 0xF5FFFA, 'mistyrose': 0xFFE4E1, 'moccasin': 0xFFE4B5, 'navajowhite': 0xFFDEAD,
	'navy': 0x000080, 'oldlace': 0xFDF5E6, 'olive': 0x808000, 'olivedrab': 0x6B8E23, 'orange': 0xFFA500, 'orangered': 0xFF4500, 'orchid': 0xDA70D6,
	'palegoldenrod': 0xEEE8AA, 'palegreen': 0x98FB98, 'paleturquoise': 0xAFEEEE, 'palevioletred': 0xDB7093, 'papayawhip': 0xFFEFD5, 'peachpuff': 0xFFDAB9,
	'peru': 0xCD853F, 'pink': 0xFFC0CB, 'plum': 0xDDA0DD, 'powderblue': 0xB0E0E6, 'purple': 0x800080, 'rebeccapurple': 0x663399, 'red': 0xFF0000, 'rosybrown': 0xBC8F8F,
	'royalblue': 0x4169E1, 'saddlebrown': 0x8B4513, 'salmon': 0xFA8072, 'sandybrown': 0xF4A460, 'seagreen': 0x2E8B57, 'seashell': 0xFFF5EE,
	'sienna': 0xA0522D, 'silver': 0xC0C0C0, 'skyblue': 0x87CEEB, 'slateblue': 0x6A5ACD, 'slategray': 0x708090, 'slategrey': 0x708090, 'snow': 0xFFFAFA,
	'springgreen': 0x00FF7F, 'steelblue': 0x4682B4, 'tan': 0xD2B48C, 'teal': 0x008080, 'thistle': 0xD8BFD8, 'tomato': 0xFF6347, 'turquoise': 0x40E0D0,
	'violet': 0xEE82EE, 'wheat': 0xF5DEB3, 'white': 0xFFFFFF, 'whitesmoke': 0xF5F5F5, 'yellow': 0xFFFF00, 'yellowgreen': 0x9ACD32 };
const SRGBToLinear = c => (c < 0.04045) ? c * 0.0773993808 : Math.pow(c * 0.9478672986 + 0.0521327014, 2.4);
const LinearToSRGB = c => (c < 0.0031308) ? c * 12.92 : 1.055 * (Math.pow(c, 0.41666)) - 0.055;
const SRGBColorSpace = 'srgb', LinearSRGBColorSpace = 'srgb-linear', NoColorSpace = '';
function hue2rgb(p, q, t) {
  if (t < 0) t += 1; if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 1 / 2) return q;
  if (t < 2 / 3) return p + (q - p) * 6 * (2 / 3 - t);
  return p;
}
// Components are linear-sRGB, the working color space of three.js with ColorManagement enabled.
class Color {
  constructor(r, g, b) { this.r = 1; this.g = 1; this.b = 1; if (r !== undefined) this.set(r, g, b); }
  get isColor() { return true; }
  set(r, g, b) {
    if (g === undefined && b === undefined) {
      const value = r;
      if (value && value.isColor) this.copy(value);
      else if (typeof value === 'number') this.setHex(value);
      else if (typeof value === 'string') this.setStyle(value);
      else throw Error('Unsupported color value: ' + String(value));
    } else this.setRGB(r, g, b);
    return this;
  }
  setScalar(s) { this.r = this.g = this.b = s; return this; }
  setHex(hex, colorSpace = SRGBColorSpace) {
    hex = Math.floor(hex);
    return this.setRGB((hex >> 16 & 255) / 255, (hex >> 8 & 255) / 255, (hex & 255) / 255, colorSpace);
  }
  setRGB(r, g, b, colorSpace = LinearSRGBColorSpace) {
    if (colorSpace === SRGBColorSpace) { this.r = SRGBToLinear(r); this.g = SRGBToLinear(g); this.b = SRGBToLinear(b); }
    else { this.r = r; this.g = g; this.b = b; }
    return this;
  }
  setHSL(h, s, l, colorSpace = LinearSRGBColorSpace) {
    h = MathUtils.euclideanModulo(h, 1); s = clamp(s, 0, 1); l = clamp(l, 0, 1);
    if (s === 0) return this.setRGB(l, l, l, colorSpace);
    const p = l <= 0.5 ? l * (1 + s) : l + s - (l * s), q = (2 * l) - p;
    return this.setRGB(hue2rgb(q, p, h + 1 / 3), hue2rgb(q, p, h), hue2rgb(q, p, h - 1 / 3), colorSpace);
  }
  setStyle(style, colorSpace = SRGBColorSpace) {
    let m;
    if ((m = /^(\w+)\(([^)]*)\)/.exec(style))) {
      const name = m[1], components = m[2];
      if (name === 'rgb' || name === 'rgba') {
        if ((m = /^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(\d*\.?\d+)\s*)?$/.exec(components)))
          return this.setRGB(Math.min(255, parseInt(m[1], 10)) / 255, Math.min(255, parseInt(m[2], 10)) / 255, Math.min(255, parseInt(m[3], 10)) / 255, colorSpace);
        if ((m = /^\s*(\d+)%\s*,\s*(\d+)%\s*,\s*(\d+)%\s*(?:,\s*(\d*\.?\d+)\s*)?$/.exec(components)))
          return this.setRGB(Math.min(100, parseInt(m[1], 10)) / 100, Math.min(100, parseInt(m[2], 10)) / 100, Math.min(100, parseInt(m[3], 10)) / 100, colorSpace);
      } else if (name === 'hsl' || name === 'hsla') {
        if ((m = /^\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)%\s*,\s*(\d*\.?\d+)%\s*(?:,\s*(\d*\.?\d+)\s*)?$/.exec(components)))
          return this.setHSL(parseFloat(m[1]) / 360, parseFloat(m[2]) / 100, parseFloat(m[3]) / 100, colorSpace);
      }
      throw Error('Unsupported color style: ' + style);
    }
    if ((m = /^#([A-Fa-f\d]+)$/.exec(style))) {
      const hex = m[1];
      if (hex.length === 3) return this.setRGB(parseInt(hex[0], 16) / 15, parseInt(hex[1], 16) / 15, parseInt(hex[2], 16) / 15, colorSpace);
      if (hex.length === 6) return this.setHex(parseInt(hex, 16), colorSpace);
      throw Error('Invalid hex color: ' + style);
    }
    const keyword = _colorKeywords[style.toLowerCase()];
    if (keyword === undefined) throw Error('Unknown color: ' + style);
    return this.setHex(keyword, colorSpace);
  }
  copy(c) { this.r = c.r; this.g = c.g; this.b = c.b; return this; }
  clone() { return new Color().copy(this); }
  multiplyScalar(s) { this.r *= s; this.g *= s; this.b *= s; return this; }
  lerp(c, a) { this.r += (c.r - this.r) * a; this.g += (c.g - this.g) * a; this.b += (c.b - this.b) * a; return this; }
  lerpColors(a, b, t) { this.r = a.r + (b.r - a.r) * t; this.g = a.g + (b.g - a.g) * t; this.b = a.b + (b.b - a.b) * t; return this; }
  getHex() { return Math.round(clamp(LinearToSRGB(this.r) * 255, 0, 255)) * 65536 + Math.round(clamp(LinearToSRGB(this.g) * 255, 0, 255)) * 256 + Math.round(clamp(LinearToSRGB(this.b) * 255, 0, 255)); }
  getHexString() { return ('000000' + this.getHex().toString(16)).slice(-6); }
  getStyle() { return '#' + this.getHexString(); }
  fromArray(array, offset = 0) { this.r = array[offset]; this.g = array[offset + 1]; this.b = array[offset + 2]; return this; }
  toArray() { return [this.r, this.g, this.b]; }
}

const DEFAULT_UP = () => new Vector3(0, 1, 0);
// Only the parts of Object3D needed to aim the camera from useThree().
class Object3D {
  constructor() {
    this.position = new Vector3();
    this.rotation = new Euler();
    this.quaternion = new Quaternion();
    this.scale = new Vector3(1, 1, 1);
    this.up = DEFAULT_UP();
    this.rotation._onChange(() => this.quaternion.setFromEuler(this.rotation, false));
    this.quaternion._onChange(() => this.rotation.setFromQuaternion(this.quaternion, undefined, false));
  }
  lookAt(x, y, z) {
    const target = x && x.isVector3 ? x.clone() : new Vector3(x, y, z);
    const matrix = this.isCamera ? new Matrix4().lookAt(this.position, target, this.up) : new Matrix4().lookAt(target, this.position, this.up);
    this.quaternion.setFromRotationMatrix(matrix);
  }
  updateMatrix() {} updateMatrixWorld() {}
}
class PerspectiveCamera extends Object3D {
  constructor(fov = 50, aspect = 1, near = 0.1, far = 2000) {
    super(); this.fov = fov; this.aspect = aspect; this.near = near; this.far = far; this.zoom = 1; this.manual = false;
  }
  get isCamera() { return true; }
  get isPerspectiveCamera() { return true; }
  // The native renderer derives the projection from fov/aspect/near/far/zoom at paint time.
  updateProjectionMatrix() {}
}

class USDLoader { static get __msLoader() { return 'usd'; } }
class USDZLoader extends USDLoader {}

module.exports = {
  MathUtils, Vector2, Vector3, Quaternion, Euler, Matrix4, Color, Object3D, PerspectiveCamera,
  FrontSide: 0, BackSide: 1, DoubleSide: 2,
  NoToneMapping: 0, ACESFilmicToneMapping: 4,
  SRGBColorSpace, LinearSRGBColorSpace, NoColorSpace,
  __USDLoader: USDLoader, __USDZLoader: USDZLoader,
};
