// Installed before module evaluation; all lines/columns exposed to users are one-based.
globalThis.__ms_mapStack = function (text) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  function position(map, line, column) {
    let source = 0, originalLine = 0, originalColumn = 0, found;
    const lines = map.mappings.split(';');
    for (let row = 0; row <= line && row < lines.length; row++) {
      let generatedColumn = 0;
      for (const segment of lines[row].split(',')) {
        if (!segment) continue;
        let values = [], value = 0, shift = 0;
        for (const char of segment) {
          const digit = alphabet.indexOf(char);
          value += (digit & 31) * 2 ** shift;
          if (digit & 32) shift += 5;
          else { values.push(value & 1 ? -(value >> 1) : value >> 1); value = 0; shift = 0; }
        }
        generatedColumn += values[0];
        if (values.length >= 4) {
          source += values[1]; originalLine += values[2]; originalColumn += values[3];
        }
        if (row === line && generatedColumn <= column) {
          found = values.length >= 4 ? `${map.sources[source]}:${originalLine + 1}:${originalColumn + 1}` : null;
        }
      }
    }
    return found;
  }
  return String(text).replace(/motionswift:bundle:(\d+):(\d+)/g, (match, line, column) => {
    const item = globalThis.__ms_sourceMaps.find(item => +line > item.offset && +line <= item.offset + item.lines);
    if (!item) return match;
    return position(item.map, +line - item.offset - 1, +column - 1) || match;
  });
};
