import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {MapMarker, MapRoute, MapView} from '@motionswift/map';

// Every map prop below is editable in the visual editor: camera, provider and style on the map,
// endpoints, travel mode and progress on each route, and position and label on each marker.
export const HarbourJourney = () => (
  <MapView center={[-122.3860, 37.6220]} zoom={13.2} bearing={0} provider="openstreetmap" mapStyle="standard"
    saturation={1} brightness={1}
    data-ms-timeline={{"from":0,"duration":null,"keyframes":{"zoom":[{"frame":0,"value":13.2,"easing":"linear"},{"frame":240,"value":14,"easing":"linear"}],"centerLongitude":[{"frame":0,"value":-122.397,"easing":"linear"},{"frame":240,"value":-122.379,"easing":"linear"}]}}}>
    <MapRoute from={[-122.3920, 37.6160]} to={[-122.3899, 37.6003]} mode="railway" color="#0b7fc7" width={6}
      data-ms-timeline={{"from":0,"duration":null,"keyframes":{"progress":[{"frame":20,"value":0,"easing":"linear"},{"frame":240,"value":1,"easing":"linear"}]}}} />
    <MapRoute from={[-122.4080, 37.6250]} to={[-122.3790, 37.6213]} mode="arc" color="#ff5a36" width={4}
      markerSize={0} progress={1} />
    <MapMarker coordinate={[-122.3920, 37.6160]} color="#0b7fc7" label="SFO International Terminal" />
    <MapMarker coordinate={[-122.3899, 37.6003]} color="#0b7fc7" label="Millbrae" />
    <MapMarker coordinate={[-122.3790, 37.6213]} color="#ff5a36" size={14} label="SFO Airport" />
  </MapView>
);

const SFOTiles = () => <MapView center={[-122.3790, 37.6213]} zoom={13.2} provider="openstreetmap" mapStyle="standard"
  data-ms-timeline={{"from":0,"duration":null,"keyframes":{"centerLongitude":[{"frame":0,"value":-122.397,"easing":"linear"},{"frame":239,"value":-122.379,"easing":"linear"}]}}}>
  <MapMarker coordinate={[-122.3790, 37.6213]} label="SFO Airport" color="#ff5a36" />
</MapView>;
const SFOSnapshot = () => <MapView center={[-122.3790, 37.6213]} zoom={13.2} provider="apple" mapStyle="standard">
  <MapMarker coordinate={[-122.3790, 37.6213]} label="SFO Airport" color="#ff5a36"
    data-ms-timeline={{"from":0,"duration":null,"keyframes":{"longitude":[{"frame":0,"value":-122.392,"easing":"linear"},{"frame":239,"value":-122.379,"easing":"linear"}]}}} />
</MapView>;
registerRoot(() => <>
  <Composition id="HarbourJourney" component={HarbourJourney} width={1280} height={720} fps={30} durationInFrames={300} />
  <Composition id="OpenStreetMapTiles" component={SFOTiles} width={960} height={540} fps={30} durationInFrames={240} />
  <Composition id="MapKitSnapshot" component={SFOSnapshot} width={960} height={540} fps={30} durationInFrames={240} />
</>);
