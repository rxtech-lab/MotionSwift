import Foundation
import MotionCore

/// Links a module graph with the precompiled vendor graph into a runtime bundle.
///
/// The result follows the `Runtime` bundle contract: it defines `__ms_ids` and `__ms_require`, then
/// calls `__ms_start()`. Modules are evaluated lazily, once, in import order like CommonJS.
public enum GraphLinker {
  public static func link(_ graph: ModuleGraph) throws -> String {
    try graph.validate()
    var script = try Vendor.script()
    script += "\nvar __ms_graph=(function(){var defs={"
    for path in graph.modules.keys.sorted() {
      guard let module = graph.modules[path] else { continue }
      let dependencies = try json(module.dependencies)
      script += "\n\(try json(path)):[function(module,exports,require){\n\(module.code)\n},\(dependencies)],"
    }
    script += """

      };var cache={};
      function load(id){
        if(id.slice(0,7)==='vendor:'){var v=__ms_vendor[id.slice(7)];if(!v)throw Error('Not in vendor graph: '+id.slice(7));return v;}
        var c=cache[id];if(c)return c.exports;
        var d=defs[id];if(!d)throw Error('Module not in graph: '+id);
        var module={exports:{}};cache[id]=module;
        d[0].call(module.exports,module,module.exports,function(s){
          if(!Object.prototype.hasOwnProperty.call(d[1],s))throw Error('Unresolved import '+s+' in '+id);
          return load(d[1][s]);});
        return module.exports;}
      load.reset=function(){cache={};};
      return load;})();
      var __ms_ids={react:'vendor:react',reconciler:'vendor:react-reconciler',
        shim:'vendor:@motionswift/remotion',entry:\(try json(graph.entry))};
      function __ms_require(id){return __ms_graph(id);}
      globalThis.__ms_resetModules=()=>{__ms_graph.reset();globalThis.__ms_root=null;};
      __ms_start();

      """
    return script
  }

  private static func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(bytes: try encoder.encode(value), encoding: .utf8) ?? "null"
  }
}
