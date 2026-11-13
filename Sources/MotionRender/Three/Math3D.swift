import Foundation
import simd

// Names mirror three.js Matrix4 (elements `e`, n11…n44, t1…t12).
// swiftlint:disable identifier_name type_name
/// three.js `Matrix4` in float64 with the same element layout (column-major) and the same
/// operation order as three.js r187 (MIT), so uploaded float32 matrices match WebGL renders bit
/// for bit. Generic SIMD inverses/products round differently in the last bit.
struct M4: Equatable {
  var e: [Double]

  static let identity = M4(e: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

  static func compose(position: [Double], quaternion: [Double], scale: [Double]) -> M4 {
    let x = quaternion[0], y = quaternion[1], z = quaternion[2], w = quaternion[3]
    let x2 = x + x, y2 = y + y, z2 = z + z
    let xx = x * x2, xy = x * y2, xz = x * z2, yy = y * y2, yz = y * z2, zz = z * z2
    let wx = w * x2, wy = w * y2, wz = w * z2
    let sx = scale[0], sy = scale[1], sz = scale[2]
    return M4(e: [
      (1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0,
      (xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0,
      (xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0,
      position[0], position[1], position[2], 1,
    ])
  }

  /// `PerspectiveCamera.updateProjectionMatrix()` + `makePerspective` (WebGL coordinates).
  static func perspective(fov: Double, aspect: Double, near: Double, far: Double, zoom: Double) -> M4 {
    let top = near * tan(Double.pi / 180 * 0.5 * fov) / zoom
    let height = 2 * top, width = aspect * height, left = -0.5 * width
    let right = left + width, bottom = top - height
    let x = 2 * near / (right - left), y = 2 * near / (top - bottom)
    let a = (right + left) / (right - left), b = (top + bottom) / (top - bottom)
    let c = -(far + near) / (far - near), d = -2 * far * near / (far - near)
    return M4(e: [x, 0, 0, 0, 0, y, 0, 0, a, b, c, -1, 0, 0, d, 0])
  }

  /// `multiplyMatrices(self, other)`.
  static func * (a: M4, b: M4) -> M4 {
    let ae = a.e, be = b.e
    let a11 = ae[0], a12 = ae[4], a13 = ae[8], a14 = ae[12]
    let a21 = ae[1], a22 = ae[5], a23 = ae[9], a24 = ae[13]
    let a31 = ae[2], a32 = ae[6], a33 = ae[10], a34 = ae[14]
    let a41 = ae[3], a42 = ae[7], a43 = ae[11], a44 = ae[15]
    let b11 = be[0], b12 = be[4], b13 = be[8], b14 = be[12]
    let b21 = be[1], b22 = be[5], b23 = be[9], b24 = be[13]
    let b31 = be[2], b32 = be[6], b33 = be[10], b34 = be[14]
    let b41 = be[3], b42 = be[7], b43 = be[11], b44 = be[15]
    var t = [Double](repeating: 0, count: 16)
    t[0] = a11 * b11 + a12 * b21 + a13 * b31 + a14 * b41
    t[4] = a11 * b12 + a12 * b22 + a13 * b32 + a14 * b42
    t[8] = a11 * b13 + a12 * b23 + a13 * b33 + a14 * b43
    t[12] = a11 * b14 + a12 * b24 + a13 * b34 + a14 * b44
    t[1] = a21 * b11 + a22 * b21 + a23 * b31 + a24 * b41
    t[5] = a21 * b12 + a22 * b22 + a23 * b32 + a24 * b42
    t[9] = a21 * b13 + a22 * b23 + a23 * b33 + a24 * b43
    t[13] = a21 * b14 + a22 * b24 + a23 * b34 + a24 * b44
    t[2] = a31 * b11 + a32 * b21 + a33 * b31 + a34 * b41
    t[6] = a31 * b12 + a32 * b22 + a33 * b32 + a34 * b42
    t[10] = a31 * b13 + a32 * b23 + a33 * b33 + a34 * b43
    t[14] = a31 * b14 + a32 * b24 + a33 * b34 + a34 * b44
    t[3] = a41 * b11 + a42 * b21 + a43 * b31 + a44 * b41
    t[7] = a41 * b12 + a42 * b22 + a43 * b32 + a44 * b42
    t[11] = a41 * b13 + a42 * b23 + a43 * b33 + a44 * b43
    t[15] = a41 * b14 + a42 * b24 + a43 * b34 + a44 * b44
    return M4(e: t)
  }

  func inverted() -> M4 {
    let n11 = e[0], n21 = e[1], n31 = e[2], n41 = e[3]
    let n12 = e[4], n22 = e[5], n32 = e[6], n42 = e[7]
    let n13 = e[8], n23 = e[9], n33 = e[10], n43 = e[11]
    let n14 = e[12], n24 = e[13], n34 = e[14], n44 = e[15]
    let t1 = n11 * n22 - n21 * n12, t2 = n11 * n32 - n31 * n12, t3 = n11 * n42 - n41 * n12
    let t4 = n21 * n32 - n31 * n22, t5 = n21 * n42 - n41 * n22, t6 = n31 * n42 - n41 * n32
    let t7 = n13 * n24 - n23 * n14, t8 = n13 * n34 - n33 * n14, t9 = n13 * n44 - n43 * n14
    let t10 = n23 * n34 - n33 * n24, t11 = n23 * n44 - n43 * n24, t12 = n33 * n44 - n43 * n34
    let det = t1 * t12 - t2 * t11 + t3 * t10 + t4 * t9 - t5 * t8 + t6 * t7
    if det == 0 { return M4(e: [Double](repeating: 0, count: 16)) }
    let d = 1 / det
    var t = [Double](repeating: 0, count: 16)
    t[0] = (n22 * t12 - n32 * t11 + n42 * t10) * d
    t[1] = (n31 * t11 - n21 * t12 - n41 * t10) * d
    t[2] = (n24 * t6 - n34 * t5 + n44 * t4) * d
    t[3] = (n33 * t5 - n23 * t6 - n43 * t4) * d
    t[4] = (n32 * t9 - n12 * t12 - n42 * t8) * d
    t[5] = (n11 * t12 - n31 * t9 + n41 * t8) * d
    t[6] = (n34 * t3 - n14 * t6 - n44 * t2) * d
    t[7] = (n13 * t6 - n33 * t3 + n43 * t2) * d
    t[8] = (n12 * t11 - n22 * t9 + n42 * t7) * d
    t[9] = (n21 * t9 - n11 * t11 - n41 * t7) * d
    t[10] = (n14 * t5 - n24 * t3 + n44 * t1) * d
    t[11] = (n23 * t3 - n13 * t5 - n43 * t1) * d
    t[12] = (n22 * t8 - n12 * t10 - n32 * t7) * d
    t[13] = (n11 * t10 - n21 * t8 + n31 * t7) * d
    t[14] = (n24 * t2 - n14 * t4 - n34 * t1) * d
    t[15] = (n13 * t4 - n23 * t2 + n33 * t1) * d
    return M4(e: t)
  }

  var determinant: Double {
    let n11 = e[0], n12 = e[4], n13 = e[8], n14 = e[12]
    let n21 = e[1], n22 = e[5], n23 = e[9], n24 = e[13]
    let n31 = e[2], n32 = e[6], n33 = e[10], n34 = e[14]
    let n41 = e[3], n42 = e[7], n43 = e[11], n44 = e[15]
    let part1 = n41 * (n14 * n23 * n32 - n13 * n24 * n32 - n14 * n22 * n33 + n12 * n24 * n33 + n13 * n22 * n34
      - n12 * n23 * n34)
    let part2 = n42 * (n11 * n23 * n34 - n11 * n24 * n33 + n14 * n21 * n33 - n13 * n21 * n34 + n13 * n24 * n31
      - n14 * n23 * n31)
    let part3 = n43 * (n11 * n24 * n32 - n11 * n22 * n34 - n14 * n21 * n32 + n12 * n21 * n34 + n14 * n22 * n31
      - n12 * n24 * n31)
    let part4 = n44 * (-n13 * n22 * n31 - n11 * n23 * n32 + n11 * n22 * n33 + n13 * n21 * n32 - n12 * n21 * n33
      + n12 * n23 * n31)
    return part1 + part2 + part3 + part4
  }

  var position: SIMD3<Double> { SIMD3(e[12], e[13], e[14]) }

  /// `Vector3.applyMatrix4` (with the perspective divide).
  func transformPoint(_ v: SIMD3<Double>) -> SIMD3<Double> {
    let w = 1 / (e[3] * v.x + e[7] * v.y + e[11] * v.z + e[15])
    return SIMD3((e[0] * v.x + e[4] * v.y + e[8] * v.z + e[12]) * w, (e[1] * v.x + e[5] * v.y + e[9] * v.z + e[13]) * w,
      (e[2] * v.x + e[6] * v.y + e[10] * v.z + e[14]) * w)
  }

  /// `Vector4.applyMatrix4` z component for (x, y, z, 1): three's render-list sort key.
  func clipZ(_ v: SIMD3<Double>) -> Double { e[2] * v.x + e[6] * v.y + e[10] * v.z + e[14] }

  /// `Vector3.transformDirection`.
  func transformDirection(_ v: SIMD3<Double>) -> SIMD3<Double> {
    let x = e[0] * v.x + e[4] * v.y + e[8] * v.z, y = e[1] * v.x + e[5] * v.y + e[9] * v.z
    let z = e[2] * v.x + e[6] * v.y + e[10] * v.z
    let length = (x * x + y * y + z * z).squareRoot()
    let scale = 1 / (length == 0 ? 1 : length)
    return SIMD3(x * scale, y * scale, z * scale)
  }

  var float: simd_float4x4 {
    simd_float4x4(columns: (SIMD4(Float(e[0]), Float(e[1]), Float(e[2]), Float(e[3])),
      SIMD4(Float(e[4]), Float(e[5]), Float(e[6]), Float(e[7])),
      SIMD4(Float(e[8]), Float(e[9]), Float(e[10]), Float(e[11])),
      SIMD4(Float(e[12]), Float(e[13]), Float(e[14]), Float(e[15]))))
  }

  /// `Matrix3.getNormalMatrix(self)`: setFromMatrix4, invert, transpose. Padded 4x4 columns.
  var normalMatrix: simd_float4x4 {
    let n11 = e[0], n21 = e[1], n31 = e[2], n12 = e[4], n22 = e[5], n32 = e[6], n13 = e[8], n23 = e[9], n33 = e[10]
    let t11 = n33 * n22 - n32 * n23, t12 = n32 * n13 - n33 * n12, t13 = n23 * n12 - n22 * n13
    let det = n11 * t11 + n21 * t12 + n31 * t13
    var m = [Double](repeating: 0, count: 9)
    if det != 0 {
      let d = 1 / det
      m = [t11 * d, (n31 * n23 - n33 * n21) * d, (n32 * n21 - n31 * n22) * d,
           t12 * d, (n33 * n11 - n31 * n13) * d, (n31 * n12 - n32 * n11) * d,
           t13 * d, (n21 * n13 - n23 * n11) * d, (n22 * n11 - n21 * n12) * d]
    }
    // Transpose: column i of the result is row i of the inverse.
    return simd_float4x4(columns: (SIMD4(Float(m[0]), Float(m[3]), Float(m[6]), 0),
      SIMD4(Float(m[1]), Float(m[4]), Float(m[7]), 0), SIMD4(Float(m[2]), Float(m[5]), Float(m[8]), 0),
      SIMD4(0, 0, 0, 1)))
  }
}

// swiftlint:enable identifier_name type_name

enum Math3D {
  static func linearToSRGB(_ value: Double) -> Double {
    value < 0.0031308 ? value * 12.92 : 1.055 * pow(value, 0.41666) - 0.055
  }

  static func vector(_ values: [Double]) -> SIMD3<Float> { SIMD3(Float(values[0]), Float(values[1]), Float(values[2])) }
  static func vector(_ value: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(value.x), Float(value.y), Float(value.z)) }
}
