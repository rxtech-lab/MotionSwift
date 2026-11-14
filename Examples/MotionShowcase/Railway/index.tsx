import React from 'react';
import {AbsoluteFill, Composition, registerRoot, useCurrentFrame} from 'remotion';
import {MapMarker, MapView, useMap} from '@motionswift/map';
import type {Coordinate} from '@motionswift/map';
import {mapData} from './map-data';
import {cameraFrame} from './camera';
import {durationInFrames, fps, journeyFrame, stations} from './route';

const CANVAS_WIDTH = 1920;
const CANVAS_HEIGHT = 1080;
const hubs = new Set(['Tokyo', 'Shinagawa', 'Shibuya', 'Shinjuku', 'Ikebukuro', 'Ueno']);
const nbsp = (text: string) => text.replace(/ /g, '\u00a0');

function clippedPath(points: number[][], width: number, height: number, limit = points.length, pad = 96) {
  if (limit < 2) return '';
  const minX = -pad, maxX = width + pad, minY = -pad, maxY = height + pad;
  const parts: string[] = [];
  let open = false;
  const end = Math.min(points.length, limit);
  for (let i = 1; i < end; i++) {
    const a = points[i - 1];
    const b = points[i];
    if ((a[0] < minX && b[0] < minX) || (a[0] > maxX && b[0] > maxX) ||
        (a[1] < minY && b[1] < minY) || (a[1] > maxY && b[1] > maxY)) {
      open = false;
      continue;
    }
    if (!open) {
      parts.push(`M${a[0].toFixed(2)} ${a[1].toFixed(2)}`);
      open = true;
    }
    parts.push(`L${b[0].toFixed(2)} ${b[1].toFixed(2)}`);
  }
  return parts.join(' ');
}

function ringDistance(a: number, b: number, count: number) {
  const delta = Math.abs(a - b);
  return Math.min(delta, count - delta);
}

function RailwayOverlay() {
  const view = useMap();
  const frame = useCurrentFrame();
  const state = journeyFrame(frame);
  const points = mapData.route.map(coordinate => view.project(coordinate as Coordinate));
  const trainPoint = view.project(state.coordinate as Coordinate);
  const fullTrack = clippedPath(points, view.width, view.height);
  const traveledPoints = points.slice(0, state.routeIndex);
  traveledPoints.push(trainPoint);
  const activeTrack = state.progress > 0 ? clippedPath(traveledPoints, view.width, view.height) : '';
  const zoomedIn = view.zoom > 13.6;

  return <>
    <svg width={view.width} height={view.height} style={{position: 'absolute', left: 0, top: 0, pointerEvents: 'none'}}>
      {fullTrack ? <>
        <path d={fullTrack} fill="none" stroke="#ffffff" strokeWidth={13} strokeLinecap="round" strokeLinejoin="round" />
        <path d={fullTrack} fill="none" stroke="#afc99f" strokeWidth={7} strokeLinecap="round" strokeLinejoin="round" />
      </> : null}
      {activeTrack ? <>
        <path d={activeTrack} fill="none" stroke="#7ac142" strokeWidth={8.5} strokeLinecap="round" strokeLinejoin="round" />
        <path d={activeTrack} fill="none" stroke="#dff5be" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" />
      </> : null}
      <circle cx={trainPoint[0]} cy={trainPoint[1]} r={19} fill="none" stroke="#ff674c" strokeWidth={2.5} />
    </svg>
    {stations.map((station, index) => {
      const passed = state.complete || index <= state.stationIndex;
      const nearby = ringDistance(index, state.stationIndex, stations.length) <= 2 || index === state.nextIndex;
      const showLabel = zoomedIn ? (nearby || hubs.has(station.name)) : (hubs.has(station.name) || index === state.stationIndex);
      return <MapMarker
        key={station.id}
        coordinate={station.coordinate as Coordinate}
        color={index === state.nextIndex && !state.stopped ? '#ff674c' : passed ? '#7ac142' : '#2d5936'}
        size={zoomedIn ? (nearby ? 13 : 10) : (hubs.has(station.name) ? 11 : 8)}
        label={showLabel ? (zoomedIn ? `${station.code} · ${station.name}` : station.name) : undefined}
      />;
    })}
    <MapMarker coordinate={state.coordinate as Coordinate} color="#ff674c" size={24} />
  </>;
}

// Keep the composition ID stable for showcase navigation and existing editor integrations.
export const IslandRailway = () => {
  const frame = useCurrentFrame();
  const state = journeyFrame(frame);
  const camera = cameraFrame(frame);
  const currentStation = stations[state.stationIndex];
  const nextStation = stations[state.nextIndex];
  const featured = state.stopped ? currentStation : nextStation;
  const stationNumber = featured.code.slice(2);
  const statusLabel = nbsp(state.complete ? 'ARRIVED TOKYO' : state.stopped ? 'READY TO DEPART' : 'CONTINUOUS LOOP');
  const percent = Math.round(state.progress * 100);
  const legLabel = nbsp(state.complete ? 'Tokyo loop completed' : `${currentStation.name} → ${nextStation.name}`);

  return <AbsoluteFill style={{backgroundColor: '#dde3d8', overflow: 'hidden', fontFamily: 'Arial'}}>
    <MapView center={camera.center} zoom={camera.zoom} bearing={camera.bearing}
      provider="openstreetmap" mapStyle="standard" attribution="bottom-right">
      <RailwayOverlay />
    </MapView>

    <div style={{
      position: 'absolute', left: 36, top: 32, width: 436, height: 104,
      display: 'flex', flexDirection: 'row', alignItems: 'center', boxSizing: 'border-box', padding: 18,
      backgroundColor: '#102117', border: '2px solid #356b3e',
      borderRadius: 18, color: '#f3f7f0',
    }}>
      <div style={{
        width: 60, height: 60, borderRadius: 14, backgroundColor: '#80c241',
        display: 'flex', alignItems: 'center', justifyContent: 'center', marginRight: 16, flexShrink: 0,
      }}>
        <div style={{
          width: 46, height: 46, borderRadius: 9, backgroundColor: '#ffffff',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <div style={{width: 40, height: 22, fontSize: 20, fontWeight: 700, lineHeight: 1.1, textAlign: 'center', color: '#142c1e'}}>JY</div>
        </div>
      </div>
      <div style={{width: 320, display: 'flex', flexDirection: 'column'}}>
        <div style={{width: 320, height: 15, display: 'flex', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'}}>
          <div style={{width: 220, height: 15, fontSize: 11, fontWeight: 700, lineHeight: 1.2, color: '#9ed36a'}}>
            {nbsp('JR EAST · OUTER LOOP')}
          </div>
          <div style={{width: 90, height: 15, fontSize: 11, fontWeight: 700, lineHeight: 1.2, color: '#9ed36a', textAlign: 'right'}}>
            外回り
          </div>
        </div>
        <div style={{width: 320, height: 28, marginTop: 4, display: 'flex', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'}}>
          <div style={{width: 200, height: 28, fontSize: 22, fontWeight: 700, lineHeight: 1.2, color: '#ffffff'}}>
            {nbsp('Yamanote Line')}
          </div>
          <div style={{width: 112, height: 28, fontSize: 20, fontWeight: 700, lineHeight: 1.2, color: '#dce8df', textAlign: 'right'}}>
            山手線
          </div>
        </div>
        <div style={{width: 320, height: 18, fontSize: 13, lineHeight: 1.2, marginTop: 4, color: '#a8bdb0'}}>
          {nbsp('Tokyo → Tokyo · 30 stations · Nonstop view')}
        </div>
      </div>
    </div>

    <div style={{
      position: 'absolute', left: 36, bottom: 34, width: 436, height: 204,
      display: 'flex', flexDirection: 'column', boxSizing: 'border-box', padding: 20,
      backgroundColor: '#102117', border: '2px solid #356b3e',
      borderRadius: 18, color: '#f3f7f0',
    }}>
      <div style={{width: 392, height: 20, display: 'flex', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'}}>
        <div style={{width: 248, display: 'flex', flexDirection: 'row', alignItems: 'center'}}>
          <div style={{
            width: 8, height: 8, borderRadius: 4, marginRight: 8, flexShrink: 0,
            backgroundColor: state.stopped ? '#80c241' : '#ff674c',
          }} />
          <div style={{width: 232, height: 15, fontSize: 11, fontWeight: 700, lineHeight: 1.2, color: '#9ed36a'}}>
            {statusLabel}
          </div>
        </div>
        <div style={{width: 138, height: 17, fontSize: 13, fontWeight: 700, lineHeight: 1.2, color: '#dce8df', textAlign: 'right'}}>
          {nbsp(`${state.stopsVisited} / 30 · ${percent}%`)}
        </div>
      </div>

      <div style={{width: 392, height: 60, marginTop: 14, display: 'flex', flexDirection: 'row', alignItems: 'center'}}>
        <div style={{
          width: 56, height: 56, borderRadius: 13, backgroundColor: '#ffffff',
          border: '4px solid #80c241', boxSizing: 'border-box', marginRight: 16, flexShrink: 0,
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        }}>
          <div style={{width: 44, height: 12, fontSize: 10, fontWeight: 700, lineHeight: 1.1, textAlign: 'center', color: '#244b2c'}}>JY</div>
          <div style={{width: 44, height: 21, fontSize: 18, fontWeight: 700, lineHeight: 1.1, textAlign: 'center', color: '#112619'}}>{stationNumber}</div>
        </div>
        <div style={{width: 320, display: 'flex', flexDirection: 'column'}}>
          <div style={{width: 320, height: 30, fontSize: 24, fontWeight: 700, lineHeight: 1.2, color: '#ffffff'}}>
            {nbsp(featured.localName)}
          </div>
          <div style={{width: 320, height: 20, fontSize: 15, lineHeight: 1.2, marginTop: 4, color: '#bdd0c3'}}>
            {nbsp(featured.name)}
          </div>
        </div>
      </div>

      <div style={{width: 392, height: 1, marginTop: 14, backgroundColor: '#2d3c33'}} />

      <div style={{
        width: 392, height: 20, marginTop: 11,
        display: 'flex', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{width: 316, height: 18, fontSize: 13, lineHeight: 1.2, color: '#b4c7ba'}}>
          {legLabel}
        </div>
        <div style={{width: 64, height: 16, fontSize: 12, fontWeight: 700, lineHeight: 1.2, color: '#80c241', textAlign: 'right'}}>
          {featured.code}
        </div>
      </div>

      <div style={{
        width: 392, height: 6, marginTop: 12, borderRadius: 3,
        backgroundColor: '#314137', overflow: 'hidden', display: 'flex',
      }}>
        <div style={{
          width: Math.max(6, Math.round(state.progress * 392)), height: 6, borderRadius: 3,
          backgroundColor: '#80c241',
        }} />
      </div>
    </div>

    <div data-ms-properties={{backgroundColor: {label: 'Progress color', group: 'Map'}}}
      style={{
        position: 'absolute', left: 0, bottom: 0, width: state.progress * CANVAS_WIDTH, height: 6,
        backgroundColor: '#ff674c',
      }} />
  </AbsoluteFill>;
};

registerRoot(() => <Composition id="IslandRailway" component={IslandRailway}
  width={CANVAS_WIDTH} height={CANVAS_HEIGHT} fps={fps} durationInFrames={durationInFrames} />);
