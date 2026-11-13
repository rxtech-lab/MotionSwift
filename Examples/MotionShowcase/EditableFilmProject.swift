import Foundation
import MotionCore

/// The benchmark deliberately flattens its SVG. Only the editor copy separates its objects;
/// every generated JSX layer owns literal styles and source-backed timeline metadata.
enum EditableFilmProject {
  static func install(in project: URL) throws {
    let url = project.appendingPathComponent("src/Composition.tsx")
    var source = try String(contentsOf: url, encoding: .utf8)
    let replacements = [
      ("const draw=(n:any,key:string)=>", "const drawSVG=(n:any,key:string)=>"),
      ("const compose=", "const draw=(n:any,key:string)=>(n.o??1)<=.004?null:({n,key});\nconst compose="),
      ("{compose(A,B,u)}</svg>", "{null}</svg>"),
      ("export const MyComposition:React.FC=", "const BenchmarkComposition:React.FC="),
    ]
    for (before, after) in replacements {
      guard source.contains(before) else { throw MotionError("Test Film editor adapter no longer matches the fixture") }
      source = source.replacingOccurrences(of: before, with: after)
    }
    for name in ["LayerRegistry", "EditableFilm"] {
      guard let resource = Bundle.module.url(forResource: name, withExtension: "tsx", subdirectory: "Film") else {
        throw MotionError("Missing Test Film editable layers")
      }
      source += "\n" + (try String(contentsOf: resource, encoding: .utf8))
    }
    try source.write(to: url, atomically: true, encoding: .utf8)
  }
}
