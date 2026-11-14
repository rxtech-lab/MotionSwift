// SPDX-FileCopyrightText: 2026 Alex Ibragimov
// SPDX-License-Identifier: MIT
import React from "react";
import { AbsoluteFill } from "remotion";
import { DUR, EASE, mix, ramp } from "./motion";
import { TYPE } from "./fonts";
import { THEME } from "./theme";

export const TITLE_LEN = 66;

const WORD_IN = 6;
const WORD_STAGGER = 3;
const KICKER_IN = 22;
const RULE_IN = 26;
const OUT_AT = TITLE_LEN - 12;

export function TitleCard({
  name,
  kicker,
  frame,
}: {
  name: string;
  kicker: string;
  frame: number;
}) {
  const words = name.split(" ");
  const out = 1 - ramp(frame, OUT_AT, 12, EASE.out);

  return (
    <AbsoluteFill
      style={{
        background: THEME.ground,
        fontFamily: TYPE,
        alignItems: "center",
        justifyContent: "center",
        opacity: out,
      }}
    >
      <div
        style={{ display: "flex", flexDirection: "column", alignItems: "center" }}
      >
        <div style={{ display: "flex", gap: 22 }}>
          {words.map((word, i) => {
            const t = ramp(
              frame,
              WORD_IN + i * WORD_STAGGER,
              DUR.word,
              EASE.word,
            );
            return (
              <div
                key={`${word}-${i}`}
                style={{
                  overflow: "hidden",
                  lineHeight: 1.06,
                  paddingBottom: 6,
                }}
              >
                <div
                  style={{
                    fontSize: 92,
                    fontWeight: 700,
                    letterSpacing: -2.5,
                    color: "white",
                    transform: `translateY(${mix(t, 110, 0).toFixed(2)}%)`,
                  }}
                >
                  {word}
                </div>
              </div>
            );
          })}
        </div>

        <div
          style={{
            width: 120,
            height: 3,
            borderRadius: 99,
            marginTop: 26,
            background: THEME.brand,
            transformOrigin: "center",
            transform: `scaleX(${ramp(frame, RULE_IN, DUR.sheet, EASE.out).toFixed(3)})`,
          }}
        />

        <div
          style={{
            marginTop: 22,
            fontSize: 22,
            fontWeight: 500,
            color: "white",
            opacity: ramp(frame, KICKER_IN, DUR.sheet, EASE.out) * 0.68,
            transform: `translateY(${mix(
              ramp(frame, KICKER_IN, DUR.sheet, EASE.out),
              10,
              0,
            ).toFixed(2)}px)`,
          }}
        >
          {kicker}
        </div>
      </div>
    </AbsoluteFill>
  );
}
