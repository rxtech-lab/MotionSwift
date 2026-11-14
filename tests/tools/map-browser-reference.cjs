// Give the map package the real Remotion composition size in browser parity renders.
const React = require('react');
const {useVideoConfig, delayRender, continueRender, cancelRender} = require('remotion');
const shim = require('../../js/remotion-shim/index.js');
const map = require('../../js/remotion-shim/map.js');
module.exports = {...map, MapView: function MapView(props) {
  const config = useVideoConfig();
  const handle = React.useMemo(() => delayRender('Loading map tiles'), [props.center[0], props.center[1], props.zoom]);
  React.useEffect(() => {
    Promise.all([...document.images].map(img => new Promise((resolve, reject) => {
      if (img.complete) return img.naturalWidth ? resolve() : reject(Error(`Map tile failed: ${img.src}`));
      img.addEventListener('load', resolve, {once: true});
      img.addEventListener('error', () => reject(Error(`Map tile failed: ${img.src}`)), {once: true});
    }))).then(() => continueRender(handle), cancelRender);
  }, [handle]);
  return React.createElement(shim.__Config.Provider, {value: config}, React.createElement(map.MapView, props));
}};
