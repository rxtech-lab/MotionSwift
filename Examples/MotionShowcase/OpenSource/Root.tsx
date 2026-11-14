import React from "react";
import { Composition } from "remotion";
import {
  ProductDemo,
  PRODUCT_DEMO_DURATION,
  PRODUCT_DEMO_FPS,
  PRODUCT_DEMO_HEIGHT,
  PRODUCT_DEMO_WIDTH,
} from "./AgenticDemo/ProductDemo";
import { DynamicIsland } from "./SwiftClip/DynamicIsland";
import { MetricDashboard } from "./SwiftClip/MetricDashboard";
import { DataViz } from "./SwiftClip/DataViz";
import { CountdownTimer } from "./SwiftClip/CountdownTimer";
import {
  BarChartAnim,
  defaultBarChartAnimProps,
} from "./RenderComp/BarChartAnim";
import {
  LineChartAnim,
  defaultLineChartAnimProps,
} from "./RenderComp/LineChartAnim";
import {
  LowerThirdGlassCard,
  defaultLowerThirdGlassCardProps,
} from "./RenderComp/LowerThirdGlassCard";
import {
  BokehCircles,
  defaultBokehCirclesProps,
} from "./RenderComp/BokehCircles";
import { DataGauge } from "./RemotionScenes/DataGauge";
import { BackgroundAurora } from "./RemotionScenes/BackgroundAurora";
import { ShapeCircularProgress } from "./RemotionScenes/ShapeCircularProgress";

export const OpenSourceRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="ProductDemo"
        component={ProductDemo}
        durationInFrames={PRODUCT_DEMO_DURATION}
        fps={PRODUCT_DEMO_FPS}
        width={PRODUCT_DEMO_WIDTH}
        height={PRODUCT_DEMO_HEIGHT}
      />
      <Composition
        id="DynamicIsland"
        component={DynamicIsland}
        durationInFrames={150}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="MetricDashboard"
        component={MetricDashboard}
        durationInFrames={240}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="DataViz"
        component={DataViz}
        durationInFrames={600}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="CountdownTimer"
        component={CountdownTimer}
        durationInFrames={210}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="BarChartAnim"
        component={BarChartAnim}
        durationInFrames={150}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={defaultBarChartAnimProps}
      />
      <Composition
        id="LineChartAnim"
        component={LineChartAnim}
        durationInFrames={150}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={defaultLineChartAnimProps}
      />
      <Composition
        id="LowerThirdGlassCard"
        component={LowerThirdGlassCard}
        durationInFrames={120}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={defaultLowerThirdGlassCardProps}
      />
      <Composition
        id="BokehCircles"
        component={BokehCircles}
        durationInFrames={150}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={defaultBokehCirclesProps}
      />
      <Composition
        id="DataGauge"
        component={DataGauge}
        durationInFrames={90}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{ value: 78, maxValue: 100, startDelay: 0 }}
      />
      <Composition
        id="BackgroundAurora"
        component={BackgroundAurora}
        durationInFrames={120}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{ startDelay: 0 }}
      />
      <Composition
        id="ShapeCircularProgress"
        component={ShapeCircularProgress}
        durationInFrames={90}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{ percentage: 75, startDelay: 0 }}
      />
    </>
  );
};
