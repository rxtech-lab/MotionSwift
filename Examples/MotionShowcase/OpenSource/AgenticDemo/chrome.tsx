// SPDX-FileCopyrightText: 2026 Alex Ibragimov
// SPDX-License-Identifier: MIT
import React from "react";
import { EASE, ramp } from "./motion";
import { TYPE } from "./fonts";
import { THEME } from "./theme";

export type Box = { x: number; y: number; w: number; h: number };

export const BAR = 40;
export const HEAD = 68;
export const BODY_Y = BAR + HEAD;

export function abs(box: Box) {
  return {
    position: "absolute" as const,
    left: box.x,
    top: box.y,
    width: box.w,
    height: box.h,
    boxSizing: "border-box" as const,
  };
}

export function trackPos(
  frame: number,
  keys: { at: number; x: number; y: number }[],
) {
  let i = 0;
  while (i < keys.length - 1 && frame >= keys[i + 1].at) i += 1;
  const a = keys[i];
  const b = keys[Math.min(i + 1, keys.length - 1)];
  if (a.at === b.at) return { x: a.x, y: a.y };
  const t = ramp(frame, a.at, b.at - a.at, EASE.inOutCubic);
  return {
    x: Math.round(a.x + (b.x - a.x) * t),
    y: Math.round(a.y + (b.y - a.y) * t),
  };
}

export function downAt(frame: number, beats: number[]) {
  return beats.some((b) => frame >= b && frame < b + 6);
}

const dot = {
  width: 8,
  height: 8,
  borderRadius: 99,
  background: THEME.border,
} as const;

export function AppFrame({
  w,
  title,
  heading,
  sub,
}: {
  w: number;
  title: string;
  heading: string;
  sub: string;
}) {
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: w,
          height: BAR,
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "0 16px",
          borderBottom: `1px solid ${THEME.border}`,
          background: THEME.background,
          fontFamily: TYPE,
          fontSize: 15,
          color: THEME.mutedForeground,
        }}
      >
        <div style={dot} />
        <div style={dot} />
        <div style={dot} />
        <span>{title}</span>
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: BAR,
          width: w,
          height: HEAD,
          display: "flex",
          alignItems: "center",
          gap: 12,
          padding: "0 24px",
          borderBottom: `1px solid ${THEME.border}`,
          background: THEME.background,
          fontFamily: TYPE,
          color: THEME.foreground,
        }}
      >
        <Orb />
        <div>
          <div style={{ fontSize: 21, fontWeight: 600 }}>{heading}</div>
          <div style={{ fontSize: 15, color: THEME.mutedForeground }}>
            {sub}
          </div>
        </div>
      </div>
    </>
  );
}

export function Orb({ size = 28 }: { size?: number }) {
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: 99,
        background: `radial-gradient(circle at 30% 30%, ${THEME.brandStrong}, ${THEME.brand})`,
        boxShadow: `0 0 0 3px ${THEME.brandSoft}`,
        flexShrink: 0,
      }}
    />
  );
}

export function Cursor({
  x,
  y,
  down,
}: {
  x: number;
  y: number;
  down: boolean;
}) {
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: 34,
        height: 34,
        transform: `translate(-3px, -2px) scale(${down ? 0.82 : 1})`,
        transformOrigin: "3px 2px",
        zIndex: 50,
        pointerEvents: "none",
        filter: "drop-shadow(0px 2px 6px rgba(0, 0, 0, 0.45))",
      }}
    >
      <svg width="34" height="34" viewBox="0 0 28 28">
        <path
          d="M4 3.5 L4 24 L11.2 17.4 L17.8 26.2 L21.2 24.2 L14.8 15.6 L24 15.6 Z"
          fill="#ffffff"
          stroke="#0b0b0b"
          strokeWidth="1.4"
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
}
