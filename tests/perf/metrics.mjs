export function median(values) {
  if(!values.length || values.some(value=>!Number.isFinite(value) || value<=0))throw Error('Invalid timings');
  const sorted=[...values].sort((a,b)=>a-b), middle=Math.floor(sorted.length/2);
  return sorted.length%2?sorted[middle]:(sorted[middle-1]+sorted[middle])/2;
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
