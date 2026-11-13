import Foundation
import MotionCore

/// Triangle geometry in three.js layout: float32 positions/normals, optional uint32 indices.
/// The generators are line-for-line ports of three.js r187 (MIT) so vertex data matches WebGL renders.
struct Mesh3D {
  var positions: [Float]
  var normals: [Float]
  var indices: [UInt32]?
  /// Geometry bounding-sphere center (bounding-box center, as in three.js) used for draw ordering.
  var center: SIMD3<Double>

  init(positions: [Float], normals: [Float], indices: [UInt32]?) {
    self.positions = positions
    self.normals = normals
    self.indices = indices
    var low = SIMD3<Double>(repeating: .infinity), high = SIMD3<Double>(repeating: -.infinity)
    for index in stride(from: 0, to: positions.count, by: 3) {
      let point = SIMD3<Double>(Double(positions[index]), Double(positions[index + 1]), Double(positions[index + 2]))
      low = pointwiseMin(low, point)
      high = pointwiseMax(high, point)
    }
    center = positions.isEmpty ? .zero : (low + high) * 0.5
  }

  var vertexCount: Int { positions.count / 3 }
  var drawCount: Int { indices?.count ?? vertexCount }
}

// Single-letter names mirror the three.js generator sources so the ports stay auditable.
// swiftlint:disable identifier_name
private struct Buffers {
  var positions: [Double] = []
  var normals: [Double] = []
  var indices: [UInt32] = []

  mutating func vertex(_ x: Double, _ y: Double, _ z: Double, normal: SIMD3<Double>) {
    positions += [x, y, z]
    normals += [normal.x, normal.y, normal.z]
  }

  var mesh: Mesh3D { Mesh3D(positions: positions.map(Float.init), normals: normals.map(Float.init), indices: indices) }
}

/// `Vector3.normalize()`: multiply by the reciprocal length, as three.js does.
private func normalized(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> {
  let length = (x * x + y * y + z * z).squareRoot()
  let scale = 1 / (length == 0 ? 1 : length)
  return SIMD3(x * scale, y * scale, z * scale)
}

enum GeometryFactory {
  static func make(_ geometry: Scene3D.Geometry) throws -> Mesh3D {
    let args = geometry.args
    func arg(_ index: Int, _ fallback: Double) -> Double { index < args.count ? args[index] : fallback }
    func segments(_ index: Int, _ fallback: Double) throws -> Int {
      let value = arg(index, fallback).rounded(.down)
      guard value >= 1, value <= 4096 else { throw MotionError("\(geometry.type) segment counts must be in 1...4096") }
      return Int(value)
    }
    switch geometry.type {
    case "box":
      return box(arg(0, 1), arg(1, 1), arg(2, 1), try segments(3, 1), try segments(4, 1), try segments(5, 1))
    case "sphere":
      return sphere(arg(0, 1), max(3, try segments(1, 32)), max(2, try segments(2, 16)), arg(3, 0), arg(4, .pi * 2),
        arg(5, 0), arg(6, .pi))
    case "plane": return plane(arg(0, 1), arg(1, 1), try segments(2, 1), try segments(3, 1))
    case "cylinder":
      return cylinder(arg(0, 1), arg(1, 1), arg(2, 1), try segments(3, 32), try segments(4, 1), arg(5, 0) != 0,
        arg(6, 0), arg(7, .pi * 2))
    case "cone":
      return cylinder(0, arg(0, 1), arg(1, 1), try segments(2, 32), try segments(3, 1), arg(4, 0) != 0, arg(5, 0),
        arg(6, .pi * 2))
    case "torus":
      return torus(arg(0, 1), arg(1, 0.4), try segments(2, 12), try segments(3, 48), arg(4, .pi * 2), arg(5, 0),
        arg(6, .pi * 2))
    case "torusKnot":
      return torusKnot(arg(0, 1), arg(1, 0.4), try segments(2, 64), try segments(3, 8), arg(4, 2), arg(5, 3))
    case "circle": return circle(arg(0, 1), max(3, try segments(1, 32)), arg(2, 0), arg(3, .pi * 2))
    case "ring":
      return ring(arg(0, 0.5), arg(1, 1), max(3, try segments(2, 32)), max(1, try segments(3, 1)), arg(4, 0),
        arg(5, .pi * 2))
    case "icosahedron", "octahedron", "tetrahedron", "dodecahedron":
      let detail = arg(1, 0).rounded(.down)
      guard detail >= 0, detail <= 64 else { throw MotionError("\(geometry.type) detail must be in 0...64") }
      let (vertices, indices) = Polyhedra.table(geometry.type)
      return polyhedron(vertices, indices, radius: arg(0, 1), detail: Int(detail))
    default: throw MotionError("Unsupported 3D geometry: \(geometry.type)")
    }
  }

}

extension GeometryFactory {
  static func box(_ width: Double, _ height: Double, _ depth: Double, _ widthSegments: Int, _ heightSegments: Int,
                  _ depthSegments: Int) -> Mesh3D {
    var buffers = Buffers()
    var vertexCount: UInt32 = 0
    // Axis indices: x=0, y=1, z=2.
    // swiftlint:disable:next function_parameter_count
    func plane(_ u: Int, _ v: Int, _ w: Int, _ udir: Double, _ vdir: Double, _ width: Double, _ height: Double,
               _ depth: Double, _ gridX: Int, _ gridY: Int) {
      let segmentWidth = width / Double(gridX), segmentHeight = height / Double(gridY)
      let widthHalf = width / 2, heightHalf = height / 2, depthHalf = depth / 2
      let gridX1 = gridX + 1, gridY1 = gridY + 1
      for iy in 0..<gridY1 {
        let y = Double(iy) * segmentHeight - heightHalf
        for ix in 0..<gridX1 {
          let x = Double(ix) * segmentWidth - widthHalf
          var vector = [0.0, 0.0, 0.0]
          vector[u] = x * udir
          vector[v] = y * vdir
          vector[w] = depthHalf
          var normal = [0.0, 0.0, 0.0]
          normal[w] = depth > 0 ? 1 : -1
          buffers.vertex(vector[0], vector[1], vector[2], normal: SIMD3(normal[0], normal[1], normal[2]))
        }
      }
      for iy in 0..<gridY {
        for ix in 0..<gridX {
          let a = vertexCount + UInt32(ix + gridX1 * iy), b = vertexCount + UInt32(ix + gridX1 * (iy + 1))
          let c = vertexCount + UInt32(ix + 1 + gridX1 * (iy + 1)), d = vertexCount + UInt32(ix + 1 + gridX1 * iy)
          buffers.indices += [a, b, d, b, c, d]
        }
      }
      vertexCount += UInt32(gridX1 * gridY1)
    }
    plane(2, 1, 0, -1, -1, depth, height, width, depthSegments, heightSegments)
    plane(2, 1, 0, 1, -1, depth, height, -width, depthSegments, heightSegments)
    plane(0, 2, 1, 1, 1, width, depth, height, widthSegments, depthSegments)
    plane(0, 2, 1, 1, -1, width, depth, -height, widthSegments, depthSegments)
    plane(0, 1, 2, 1, -1, width, height, depth, widthSegments, heightSegments)
    plane(0, 1, 2, -1, -1, width, height, -depth, widthSegments, heightSegments)
    return buffers.mesh
  }

  static func sphere(_ radius: Double, _ widthSegments: Int, _ heightSegments: Int, _ phiStart: Double,
                     _ phiLength: Double, _ thetaStart: Double, _ thetaLength: Double) -> Mesh3D {
    var buffers = Buffers()
    let thetaEnd = min(thetaStart + thetaLength, .pi)
    var grid: [[UInt32]] = []
    var index: UInt32 = 0
    for iy in 0...heightSegments {
      var row: [UInt32] = []
      let v = Double(iy) / Double(heightSegments)
      let theta = thetaStart + v * thetaLength
      let y = radius * cos(theta)
      let ringRadius = (radius * radius - y * y).squareRoot()
      for ix in 0...widthSegments {
        let u = Double(ix) / Double(widthSegments)
        let phi = phiStart + u * phiLength
        let x = -ringRadius * cos(phi), z = ringRadius * sin(phi)
        buffers.vertex(x, y, z, normal: normalized(x, y, z))
        row.append(index)
        index += 1
      }
      grid.append(row)
    }
    for iy in 0..<heightSegments {
      for ix in 0..<widthSegments {
        let a = grid[iy][ix + 1], b = grid[iy][ix], c = grid[iy + 1][ix], d = grid[iy + 1][ix + 1]
        if iy != 0 || thetaStart > 0 { buffers.indices += [a, b, d] }
        if iy != heightSegments - 1 || thetaEnd < .pi { buffers.indices += [b, c, d] }
      }
    }
    return buffers.mesh
  }

  static func plane(_ width: Double, _ height: Double, _ gridX: Int, _ gridY: Int) -> Mesh3D {
    var buffers = Buffers()
    let segmentWidth = width / Double(gridX), segmentHeight = height / Double(gridY)
    for iy in 0...gridY {
      let y = Double(iy) * segmentHeight - height / 2
      for ix in 0...gridX {
        buffers.vertex(Double(ix) * segmentWidth - width / 2, -y, 0, normal: SIMD3(0, 0, 1))
      }
    }
    for iy in 0..<gridY {
      for ix in 0..<gridX {
        let a = UInt32(ix + (gridX + 1) * iy), b = UInt32(ix + (gridX + 1) * (iy + 1))
        let c = UInt32(ix + 1 + (gridX + 1) * (iy + 1)), d = UInt32(ix + 1 + (gridX + 1) * iy)
        buffers.indices += [a, b, d, b, c, d]
      }
    }
    return buffers.mesh
  }

  static func cylinder(_ radiusTop: Double, _ radiusBottom: Double, _ height: Double, _ radialSegments: Int,
                       _ heightSegments: Int, _ openEnded: Bool, _ thetaStart: Double, _ thetaLength: Double) -> Mesh3D {
    var buffers = Buffers()
    var index: UInt32 = 0
    var rows: [[UInt32]] = []
    let halfHeight = height / 2
    let slope = (radiusBottom - radiusTop) / height
    for y in 0...heightSegments {
      var row: [UInt32] = []
      let v = Double(y) / Double(heightSegments)
      let radius = v * (radiusBottom - radiusTop) + radiusTop
      for x in 0...radialSegments {
        let u = Double(x) / Double(radialSegments)
        let theta = u * thetaLength + thetaStart
        let sinTheta = sin(theta), cosTheta = cos(theta)
        buffers.vertex(radius * sinTheta, -v * height + halfHeight, radius * cosTheta,
          normal: normalized(sinTheta, slope, cosTheta))
        row.append(index)
        index += 1
      }
      rows.append(row)
    }
    for x in 0..<radialSegments {
      for y in 0..<heightSegments {
        let a = rows[y][x], b = rows[y + 1][x], c = rows[y + 1][x + 1], d = rows[y][x + 1]
        if radiusTop > 0 || y != 0 { buffers.indices += [a, b, d] }
        if radiusBottom > 0 || y != heightSegments - 1 { buffers.indices += [b, c, d] }
      }
    }
    func cap(top: Bool) {
      let centerStart = index
      let radius = top ? radiusTop : radiusBottom
      let sign: Double = top ? 1 : -1
      for _ in 1...radialSegments {
        buffers.vertex(0, halfHeight * sign, 0, normal: SIMD3(0, sign, 0))
        index += 1
      }
      let centerEnd = index
      for x in 0...radialSegments {
        let theta = Double(x) / Double(radialSegments) * thetaLength + thetaStart
        buffers.vertex(radius * sin(theta), halfHeight * sign, radius * cos(theta), normal: SIMD3(0, sign, 0))
        index += 1
      }
      for x in 0..<UInt32(radialSegments) {
        let c = centerStart + x, i = centerEnd + x
        buffers.indices += top ? [i, i + 1, c] : [i + 1, i, c]
      }
    }
    if !openEnded {
      if radiusTop > 0 { cap(top: true) }
      if radiusBottom > 0 { cap(top: false) }
    }
    return buffers.mesh
  }

}

extension GeometryFactory {
  static func torus(_ radius: Double, _ tube: Double, _ radialSegments: Int, _ tubularSegments: Int, _ arc: Double,
                    _ thetaStart: Double, _ thetaLength: Double) -> Mesh3D {
    var buffers = Buffers()
    for j in 0...radialSegments {
      let v = thetaStart + (Double(j) / Double(radialSegments)) * thetaLength
      for i in 0...tubularSegments {
        let u = Double(i) / Double(tubularSegments) * arc
        let x = (radius + tube * cos(v)) * cos(u), y = (radius + tube * cos(v)) * sin(u), z = tube * sin(v)
        buffers.vertex(x, y, z, normal: normalized(x - radius * cos(u), y - radius * sin(u), z))
      }
    }
    let stride = UInt32(tubularSegments + 1)
    for j in 1...UInt32(radialSegments) {
      for i in 1...UInt32(tubularSegments) {
        let a = stride * j + i - 1, b = stride * (j - 1) + i - 1, c = stride * (j - 1) + i, d = stride * j + i
        buffers.indices += [a, b, d, b, c, d]
      }
    }
    return buffers.mesh
  }

  static func torusKnot(_ radius: Double, _ tube: Double, _ tubularSegments: Int, _ radialSegments: Int,
                        _ p: Double, _ q: Double) -> Mesh3D {
    var buffers = Buffers()
    func curve(_ u: Double) -> SIMD3<Double> {
      let quOverP = q / p * u, cs = cos(quOverP)
      return SIMD3(radius * (2 + cs) * 0.5 * cos(u), radius * (2 + cs) * sin(u) * 0.5, radius * sin(quOverP) * 0.5)
    }
    func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
      SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    func normalize(_ v: SIMD3<Double>) -> SIMD3<Double> { normalized(v.x, v.y, v.z) }
    for i in 0...tubularSegments {
      let u = Double(i) / Double(tubularSegments) * p * .pi * 2
      let p1 = curve(u), p2 = curve(u + 0.01)
      let tangent = p2 - p1
      var normal = p2 + p1
      var binormal = cross(tangent, normal)
      normal = cross(binormal, tangent)
      binormal = normalize(binormal)
      normal = normalize(normal)
      for j in 0...radialSegments {
        let v = Double(j) / Double(radialSegments) * .pi * 2
        let cx = -tube * cos(v), cy = tube * sin(v)
        let x = p1.x + (cx * normal.x + cy * binormal.x)
        let y = p1.y + (cx * normal.y + cy * binormal.y)
        let z = p1.z + (cx * normal.z + cy * binormal.z)
        buffers.vertex(x, y, z, normal: normalized(x - p1.x, y - p1.y, z - p1.z))
      }
    }
    let stride = UInt32(radialSegments + 1)
    for j in 1...UInt32(tubularSegments) {
      for i in 1...UInt32(radialSegments) {
        let a = stride * (j - 1) + (i - 1), b = stride * j + (i - 1), c = stride * j + i, d = stride * (j - 1) + i
        buffers.indices += [a, b, d, b, c, d]
      }
    }
    return buffers.mesh
  }

  static func circle(_ radius: Double, _ segments: Int, _ thetaStart: Double, _ thetaLength: Double) -> Mesh3D {
    var buffers = Buffers()
    buffers.vertex(0, 0, 0, normal: SIMD3(0, 0, 1))
    for segment in 0...segments {
      let angle = thetaStart + Double(segment) / Double(segments) * thetaLength
      buffers.vertex(radius * cos(angle), radius * sin(angle), 0, normal: SIMD3(0, 0, 1))
    }
    for index in 1...UInt32(segments) { buffers.indices += [index, index + 1, 0] }
    return buffers.mesh
  }

  static func ring(_ innerRadius: Double, _ outerRadius: Double, _ thetaSegments: Int, _ phiSegments: Int,
                   _ thetaStart: Double, _ thetaLength: Double) -> Mesh3D {
    var buffers = Buffers()
    var radius = innerRadius
    let step = (outerRadius - innerRadius) / Double(phiSegments)
    for _ in 0...phiSegments {
      for i in 0...thetaSegments {
        let angle = thetaStart + Double(i) / Double(thetaSegments) * thetaLength
        buffers.vertex(radius * cos(angle), radius * sin(angle), 0, normal: SIMD3(0, 0, 1))
      }
      radius += step
    }
    for j in 0..<phiSegments {
      let level = j * (thetaSegments + 1)
      for i in 0..<thetaSegments {
        let segment = UInt32(i + level), next = UInt32(thetaSegments)
        buffers.indices += [segment, segment + next + 1, segment + 1, segment + next + 1, segment + next + 2, segment + 1]
      }
    }
    return buffers.mesh
  }

  /// Non-indexed polyhedron, flat normals at detail 0 and normalized positions otherwise.
  static func polyhedron(_ vertices: [Double], _ indices: [Int], radius: Double, detail: Int) -> Mesh3D {
    var buffer: [Double] = []
    func lerp(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
      SIMD3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }
    func vertex(_ index: Int) -> SIMD3<Double> { SIMD3(vertices[index * 3], vertices[index * 3 + 1], vertices[index * 3 + 2]) }
    func push(_ v: SIMD3<Double>) { buffer += [v.x, v.y, v.z] }
    for face in stride(from: 0, to: indices.count, by: 3) {
      let a = vertex(indices[face]), b = vertex(indices[face + 1]), c = vertex(indices[face + 2])
      let cols = detail + 1
      var grid: [[SIMD3<Double>]] = []
      for i in 0...cols {
        let aj = lerp(a, c, Double(i) / Double(cols)), bj = lerp(b, c, Double(i) / Double(cols))
        let rows = cols - i
        grid.append((0...rows).map { j in j == 0 && i == cols ? aj : lerp(aj, bj, Double(j) / Double(rows)) })
      }
      for i in 0..<cols {
        for j in 0..<(2 * (cols - i) - 1) {
          let k = j / 2
          if j % 2 == 0 {
            push(grid[i][k + 1]); push(grid[i + 1][k]); push(grid[i][k])
          } else {
            push(grid[i][k + 1]); push(grid[i + 1][k + 1]); push(grid[i + 1][k])
          }
        }
      }
    }
    for index in stride(from: 0, to: buffer.count, by: 3) {
      let n = normalized(buffer[index], buffer[index + 1], buffer[index + 2])
      buffer[index] = n.x * radius
      buffer[index + 1] = n.y * radius
      buffer[index + 2] = n.z * radius
    }
    let positions = buffer.map(Float.init)
    var normals = positions
    if detail == 0 {
      // computeVertexNormals on the float32 attribute: (C - B) × (A - B) per face.
      for face in stride(from: 0, to: positions.count, by: 9) {
        func point(_ offset: Int) -> SIMD3<Double> {
          SIMD3(Double(positions[face + offset]), Double(positions[face + offset + 1]), Double(positions[face + offset + 2]))
        }
        let pA = point(0), pB = point(3), pC = point(6)
        let cb = pC - pB, ab = pA - pB
        let n = SIMD3(cb.y * ab.z - cb.z * ab.y, cb.z * ab.x - cb.x * ab.z, cb.x * ab.y - cb.y * ab.x)
        for vertex in 0..<3 { for axis in 0..<3 { normals[face + vertex * 3 + axis] = Float(n[axis]) } }
      }
    }
    for index in stride(from: 0, to: normals.count, by: 3) {
      let n = normalized(Double(normals[index]), Double(normals[index + 1]), Double(normals[index + 2]))
      normals[index] = Float(n.x)
      normals[index + 1] = Float(n.y)
      normals[index + 2] = Float(n.z)
    }
    return Mesh3D(positions: positions, normals: normals, indices: nil)
  }
}

private enum Polyhedra {
  static func table(_ type: String) -> ([Double], [Int]) {
    let t = (1 + 5.0.squareRoot()) / 2
    switch type {
    case "icosahedron":
      return ([-1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0, 0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, t, 0, -1, t, 0, 1, -t, 0, -1,
        -t, 0, 1],
        [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2,
         3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
    case "octahedron":
      return ([1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1],
        [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2])
    case "tetrahedron":
      return ([1, 1, 1, -1, -1, 1, -1, 1, -1, 1, -1, -1], [2, 1, 0, 0, 3, 2, 1, 3, 0, 2, 3, 1])
    default:
      let r = 1 / t
      return ([-1, -1, -1, -1, -1, 1, -1, 1, -1, -1, 1, 1, 1, -1, -1, 1, -1, 1, 1, 1, -1, 1, 1, 1, 0, -r, -t, 0, -r, t, 0, r,
        -t, 0, r, t, -r, -t, 0, -r, t, 0, r, -t, 0, r, t, 0, -t, 0, -r, t, 0, -r, -t, 0, r, t, 0, r],
        [3, 11, 7, 3, 7, 15, 3, 15, 13, 7, 19, 17, 7, 17, 6, 7, 6, 15, 17, 4, 8, 17, 8, 10, 17, 10, 6, 8, 0, 16, 8, 16, 2,
         8, 2, 10, 0, 12, 1, 0, 1, 18, 0, 18, 16, 6, 10, 2, 6, 2, 13, 6, 13, 15, 2, 16, 18, 2, 18, 3, 2, 3, 13, 18, 1, 9,
         18, 9, 11, 18, 11, 3, 4, 14, 12, 4, 12, 0, 4, 0, 8, 11, 9, 5, 11, 5, 19, 11, 19, 7, 19, 5, 14, 19, 14, 4, 19, 4,
         17, 1, 12, 14, 1, 14, 5, 1, 5, 9])
    }
  }
}
// swiftlint:enable identifier_name
