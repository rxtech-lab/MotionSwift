export function median(values) {
  if(!values.length || values.some(value=>!Number.isFinite(value) || value<=0))throw Error('Invalid timings');
  const sorted=[...values].sort((a,b)=>a-b), middle=Math.floor(sorted.length/2);
  return sorted.length%2?sorted[middle]:(sorted[middle-1]+sorted[middle])/2;
}
// Remotion's video renderer needs a frame advance to finish mounting at render scale.
// Still fixtures can select one reference frame, while video measurements use a short clip.
export function benchmarkRange(frames, minimumFrames=1) {
  if(!Number.isSafeInteger(minimumFrames)||minimumFrames<1)throw Error('Invalid minimum video frame count');
  const range=Array.isArray(frames)?[Math.min(...frames),Math.max(...frames)]:
    typeof frames==='string'&&/^\d+-\d+$/.test(frames)?frames.split('-').map(Number):[];
  if(range.length!==2||range.some(frame=>!Number.isSafeInteger(frame)||frame<0)||range[1]<range[0])
    throw Error('Fixture needs an inclusive frame range');
  const last=Math.max(range[1],range[0]+(minimumFrames-1));
  if(!Number.isSafeInteger(last))throw Error('Video frame range is too large');
  return `${range[0]}-${last}`;
}
export function stdev(values) {
  const mean=values.reduce((a,b)=>a+b,0)/values.length;
  return Math.sqrt(values.reduce((sum,value)=>sum+(value-mean)**2,0)/values.length);
}
export function geometricMean(values) {
  if(!values.length)return null;
  if(values.some(value=>!Number.isFinite(value)||value<=0))throw Error('Invalid speedups');
  return Math.exp(values.reduce((sum,value)=>sum+Math.log(value),0)/values.length);
}
export function sameMachine(a,b) {
  return !!a && !!b && ['platform','cpu','cores','memoryGB','runner','node'].every(key=>a[key]===b[key]);
}
export function parityMetadata(a,b) {
  return ['codec_name','width','height','r_frame_rate','nb_read_packets'].every(key=>a[key]!==undefined && a[key]===b[key]);
}
