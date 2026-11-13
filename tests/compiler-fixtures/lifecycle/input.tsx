import React, {useEffect, useState} from 'react';
import {Composition, registerRoot, useCurrentFrame, delayRender, continueRender, cancelRender} from 'remotion';
let visits = 0;
const View = ({mode = 'ok', color = 'red'}) => {
  const frame = useCurrentFrame();
  const [ready, setReady] = useState(false);
  const [random] = useState(() => Math.random());
  visits++;
  useEffect(() => {
    const handle = delayRender('fixture asset /example.png', {timeoutInMilliseconds: 50});
    if (mode === 'globals') {
      const url = new URL('../asset?q=hello+world', 'https://example.com/path/base');
      if (url.href !== 'https://example.com/asset?q=hello+world' || url.searchParams.get('q') !== 'hello world') throw Error('URL mismatch');
      if (new TextDecoder().decode(new TextEncoder().encode('你好')) !== '你好' || atob(btoa('hello')) !== 'hello') throw Error('encoding mismatch');
      const controller = new AbortController(); controller.abort(Error('expected abort'));
      fetch('https://unused.invalid', {signal: controller.signal}).catch(error => {
        if (error.message !== 'expected abort') throw error;
      });
      new Response('{"ready":true}', {headers: {'X-Test': 'yes'}}).json().then(result => {
        if (!result.ready) throw Error('Response mismatch');
      });
      Promise.reject(Error('caught rejection')).catch(() => {});
      const interval = setInterval(() => { clearInterval(interval); }, 2);
      queueMicrotask(() => {});
    }
    if (mode === 'timeout') return;
    if (mode === 'cancel') { cancelRender(Error('decode failed /example.png')); return; }
    if (mode === 'reject') { Promise.reject(Error('asset promise failed')); return; }
    if (mode === 'throw') { setTimeout(() => { throw Error('timer callback failed'); }, 5); return; }
    const timer = setTimeout(() => {
      Promise.resolve().then(() => {
        setReady(true);
        continueRender(handle);
        if (mode === 'duplicate') continueRender(handle);
      });
    }, 5);
    return () => clearTimeout(timer);
  }, []);
  return <div style={{left: frame, backgroundColor: color, opacity: ready ? 1 : 0, ...(frame % 2 === 0 ? {borderRadius: 1} : {})}}
    data-ms-src="lifecycle/input.tsx:26:10"><div style={{width: random, height: visits}} />
    {frame % 2 === 0 ? <span style={{height: 2}} /> : null}
    {frame % 3 === 0 ? <div><span /></div> : <span><div /></span>}</div>;
};
registerRoot(() => <>
  <Composition id="Lifecycle" component={View} width={16} height={16} fps={30} durationInFrames={20} />
  <Composition id="Other" component={View} width={16} height={16} fps={30} durationInFrames={20} />
</>);
