// The MIT paths algorithms only need the v4 arc-orientation feature flag.
// Timing/motion remains supplied by our existing clean-room shim.
const {interpolate, Easing} = require('../remotion-shim');
module.exports = {NoReactInternals:{ENABLE_V5_BREAKING_CHANGES:false}, interpolate, Easing};
