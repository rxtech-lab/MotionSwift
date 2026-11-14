// SPDX-FileCopyrightText: 2026 Alex Ibragimov
// SPDX-License-Identifier: MIT
import React from "react";
import { AbsoluteFill, Sequence, useCurrentFrame } from "remotion";
import { Demo, DEMO_LEN } from "./Demo";
import { TITLE_LEN, TitleCard } from "./title-card";
import { THEME } from "./theme";

export const PRODUCT_DEMO_FPS = 30;
export const PRODUCT_DEMO_WIDTH = 1600;
export const PRODUCT_DEMO_HEIGHT = 1000;
export const PRODUCT_DEMO_DURATION = DEMO_LEN + TITLE_LEN;

export const ProductDemo: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: THEME.ground }}>
      {frame < TITLE_LEN && (
        <TitleCard
          name="Acme Studio"
          kicker="Ask a question, publish the answer"
          frame={frame}
        />
      )}
      <Sequence from={TITLE_LEN}>
        <Demo />
      </Sequence>
    </AbsoluteFill>
  );
};
