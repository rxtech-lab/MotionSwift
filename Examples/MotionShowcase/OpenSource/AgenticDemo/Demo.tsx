// SPDX-FileCopyrightText: 2026 Alex Ibragimov
// SPDX-License-Identifier: MIT
import React, { type ReactNode } from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import {
  DUR,
  EASE,
  countTo,
  caretOn,
  enter,
  enterAt,
  mix,
  mixToken,
  pop,
  press,
  ramp,
  typed,
} from "./motion";
import { AppFrame, BODY_Y, Cursor, Orb, abs, downAt, trackPos } from "./chrome";
import { TYPE } from "./fonts";
import { THEME } from "./theme";

export const DEMO_LEN = 414;

const APP_IN = 0;
const FIELD_CLICK = 20;
const TYPE_AT = 26;
const RUN_CLICK = 88;
const ROWS_AT = 96;
const COUNT_AT = 100;
const CHIP_CLICK = 184;
const REFILTER_AT = 190;
const PUBLISH_CLICK = 274;
const TOAST_AT = 282;
const OUT_AT = 380;

const PROMPT = "Revenue by channel, last quarter";

const CLICKS = [FIELD_CLICK, RUN_CLICK, CHIP_CLICK, PUBLISH_CLICK];
const HOLD = 8;

const POINTER = [
  { at: 0, x: 860, y: 700 },
  { at: FIELD_CLICK - 14, x: 420, y: 194 },
  { at: FIELD_CLICK + HOLD, x: 420, y: 194 },
  { at: RUN_CLICK - 16, x: 1484, y: 194 },
  { at: RUN_CLICK + HOLD, x: 1484, y: 194 },
  { at: CHIP_CLICK - 20, x: 1285, y: 465 },
  { at: CHIP_CLICK + HOLD, x: 1285, y: 465 },
  { at: PUBLISH_CLICK - 22, x: 1305, y: 917 },
  { at: DEMO_LEN, x: 1305, y: 917 },
];

const W = 1600;
const FIELD = { x: 48, y: BODY_Y + 50, w: 1504, h: 72 };
const RESULTS = { x: 48, y: 262, w: 980, h: 596 };
const SIDE = { x: 1060, y: 262, w: 492, h: 596 };
const PUBLISH = { x: 1060, y: 884, w: 492, h: 68 };

const ROWS = [
  { label: "Organic search", bar: 0.92, n: 1204, paid: false },
  { label: "Paid social", bar: 0.6, n: 786, paid: true },
  { label: "Paid search", bar: 0.39, n: 512, paid: true },
  { label: "Email", bar: 0.3, n: 389, paid: false },
  { label: "Referral", bar: 0.13, n: 171, paid: false },
];

const TOTAL_ALL = 3062;
const TOTAL_PAID = 1298;

const CHIPS = ["All channels", "Paid only", "Organic"];
const LIT_CHIP = 1;

export function Demo() {
  const frame = useCurrentFrame();

  const appIn = ramp(frame, APP_IN, DUR.sheet, EASE.out);
  const appOut = 1 - ramp(frame, OUT_AT, 20, EASE.out);
  const app = Math.min(appIn, appOut);

  const pointer = trackPos(frame, POINTER);
  const down = downAt(frame, CLICKS);

  const focus =
    ramp(frame, FIELD_CLICK, DUR.chip) * (1 - ramp(frame, RUN_CLICK, DUR.chip));
  const text = typed(frame, TYPE_AT, PROMPT);
  const typing = text.length > 0 && text.length < PROMPT.length;

  const publishIn = enter(frame, ROWS_AT + 10, { dur: DUR.panel, y: 10 });

  const matched = countTo(frame, COUNT_AT, 1940);
  const refilter = ramp(frame, REFILTER_AT, DUR.sheet);
  const shown =
    frame < REFILTER_AT ? matched : Math.round(mix(refilter, 1940, 312));

  const totalShown =
    frame < REFILTER_AT
      ? TOTAL_ALL
      : Math.round(mix(refilter, TOTAL_ALL, TOTAL_PAID));
  const chipOn = ramp(frame, CHIP_CLICK, DUR.chip);

  return (
    <AbsoluteFill style={{ background: THEME.ground }}>
      <AbsoluteFill
        style={{
          background: THEME.background,
          fontFamily: TYPE,
          color: THEME.foreground,
          opacity: app,
        }}
      >
        <AppFrame
          w={W}
          title="Acme Studio"
          heading="New report"
          sub="Ask for anything"
        />

        {/* Prompt field */}
        <div
          style={{
            ...abs(FIELD),
            borderRadius: THEME.radius,
            background: THEME.card,
            border: `1px solid ${mixToken(focus, THEME.border, THEME.brand)}`,
            boxShadow: `0 0 0 ${(focus * 3).toFixed(1)}px ${THEME.brandSoft}`,
            display: "flex",
            alignItems: "center",
            padding: "0 20px",
            gap: 2,
          }}
        >
          <span style={{ fontSize: 24, opacity: text ? 1 : 0.45 }}>
            {text || "Ask for anything"}
          </span>
          <div
            style={{
              width: 2,
              height: 28,
              marginLeft: 3,
              background: THEME.brand,
              opacity: focus > 0.5 && (typing || caretOn(frame)) ? 1 : 0,
            }}
          />

          <div
            style={{
              marginLeft: "auto",
              padding: "12px 28px",
              borderRadius: 10,
              fontSize: 19,
              fontWeight: 600,
              color: "white",
              background: THEME.brand,
              transform: `scale(${press(frame, RUN_CLICK).toFixed(4)})`,
            }}
          >
            Run
          </div>
        </div>

        {/* Empty state */}
        <div
          style={{
            ...abs({ x: RESULTS.x, y: RESULTS.y, w: SIDE.x + SIDE.w - RESULTS.x, h: RESULTS.h }),
            borderRadius: THEME.radius,
            border: `1px solid ${THEME.border}`,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: 16,
            opacity: ramp(frame, APP_IN + 4, DUR.sheet) * (1 - ramp(frame, ROWS_AT, DUR.chip)),
          }}
        >
          <Orb size={34} />
          <div style={{ fontSize: 20, color: THEME.mutedForeground }}>
            Results will appear here
          </div>
        </div>

        {/* Results */}
        <div
          style={{
            ...abs(RESULTS),
            borderRadius: THEME.radius,
            border: `1px solid ${THEME.border}`,
            background: THEME.card,
            padding: 28,
            ...enter(frame, ROWS_AT, { dur: DUR.sheet, y: 14, scale: 0.985 }),
          }}
        >
          <div style={{ fontSize: 15, color: THEME.mutedForeground }}>
            CHANNEL BREAKDOWN
          </div>

          {ROWS.map((row, i) => {
            const at = ROWS_AT + 8;
            const grow = ramp(frame, at + i * 2 + 4, DUR.hero, EASE.out);
            const cut = row.paid
              ? 0
              : ramp(frame, REFILTER_AT + i * 2, DUR.sheet, EASE.out);
            const ent = enterAt(frame, at, i, { y: 10 });
            return (
              <div
                key={row.label}
                style={{
                  marginTop: 34,
                  ...ent,
                  opacity: (ent.opacity as number) * mix(cut, 1, 0.26),
                }}
              >
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    fontSize: 19,
                    marginBottom: 9,
                  }}
                >
                  <span>{row.label}</span>
                  <span style={{ color: THEME.mutedForeground }}>
                    {row.n.toLocaleString("en-US")}
                  </span>
                </div>
                <div
                  style={{
                    height: 10,
                    borderRadius: 99,
                    background: THEME.muted,
                    overflow: "hidden",
                  }}
                >
                  <div
                    style={{
                      height: "100%",
                      width: `${row.bar * 100}%`,
                      borderRadius: 99,
                      background: THEME.brand,
                      transformOrigin: "left center",
                      transform: `scaleX(${(grow * mix(cut, 1, 0)).toFixed(4)})`,
                    }}
                  />
                </div>
              </div>
            );
          })}

          <div
            style={{
              marginTop: 30,
              paddingTop: 20,
              borderTop: `1px solid ${THEME.border}`,
              display: "flex",
              justifyContent: "space-between",
              fontSize: 19,
              ...enter(frame, ROWS_AT + 20, { y: 8 }),
            }}
          >
            <span style={{ color: THEME.mutedForeground }}>Total</span>
            <span style={{ fontWeight: 600 }}>
              {totalShown.toLocaleString("en-US")}
            </span>
          </div>
        </div>

        {/* Side panel */}
        <div
          style={{
            ...abs(SIDE),
            borderRadius: THEME.radius,
            border: `1px solid ${THEME.border}`,
            background: THEME.card,
            padding: 28,
            ...enter(frame, ROWS_AT + 4, { dur: DUR.sheet, y: 14, scale: 0.985 }),
          }}
        >
          <div style={{ fontSize: 15, color: THEME.mutedForeground }}>
            ROWS MATCHED
          </div>
          <div
            style={{
              fontSize: 76,
              fontWeight: 700,
              letterSpacing: -2,
              marginTop: 6,
            }}
          >
            {shown.toLocaleString("en-US")}
          </div>

          <div style={{ display: "flex", gap: 10, marginTop: 30, flexWrap: "wrap" }}>
            {CHIPS.map((chip, i) => {
              const lit = i === 0 ? 1 - chipOn : i === LIT_CHIP ? chipOn : 0;
              return (
                <div
                  key={chip}
                  style={{
                    padding: "10px 18px",
                    borderRadius: 99,
                    fontSize: 17,
                    border: `1px solid ${mixToken(lit, THEME.border, THEME.brand)}`,
                    background: mixToken(lit, "transparent", THEME.brandSoft),
                    color: mixToken(lit, THEME.mutedForeground, THEME.brandStrong),
                    transform: `scale(${(i === LIT_CHIP ? press(frame, CHIP_CLICK, 0.06) : 1).toFixed(4)})`,
                  }}
                >
                  {chip}
                </div>
              );
            })}
          </div>

          {(
            [
              [
                "Top channel",
                <div key="top-channel" style={{ position: "relative", width: 150, height: 22 }}>
                  <span
                    style={{
                      position: "absolute",
                      right: 0,
                      top: 0,
                      whiteSpace: "nowrap",
                      opacity: 1 - refilter,
                    }}
                  >
                    Organic search
                  </span>
                  <span
                    style={{
                      position: "absolute",
                      right: 0,
                      top: 0,
                      whiteSpace: "nowrap",
                      opacity: refilter,
                    }}
                  >
                    Paid social
                  </span>
                </div>,
              ],
              ["Period", <span key="period">Q3 2026</span>],
            ] as [string, ReactNode][]
          ).map(([k, v], i) => (
            <div
              key={k}
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                fontSize: 17,
                marginTop: 20,
                paddingTop: 20,
                borderTop: `1px solid ${THEME.border}`,
                ...enterAt(frame, ROWS_AT + 16, i, { y: 8 }),
              }}
            >
              <span style={{ color: THEME.mutedForeground }}>{k}</span>
              <div>{v}</div>
            </div>
          ))}

          <div
            style={{
              marginTop: 34,
              padding: 22,
              borderRadius: 12,
              background: THEME.brandSoft,
              border: `1px solid ${THEME.brand}`,
              display: "flex",
              gap: 14,
              alignItems: "center",
              opacity: ramp(frame, TOAST_AT, DUR.chip),
              transform: `translateY(${mix(pop(frame, TOAST_AT), 16, 0).toFixed(2)}px)`,
            }}
          >
            <Orb size={22} />
            <div>
              <div style={{ fontSize: 18, fontWeight: 600 }}>Report published</div>
              <div style={{ fontSize: 15, color: THEME.mutedForeground }}>
                Shared with 4 people
              </div>
            </div>
          </div>
        </div>

        {/* Publish button */}
        <div
          style={{
            ...abs(PUBLISH),
            borderRadius: 12,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 20,
            fontWeight: 600,
            color: "white",
            background: THEME.brand,
            ...publishIn,
            transform: `${publishIn.transform} scale(${press(frame, PUBLISH_CLICK).toFixed(4)})`,
          }}
        >
          Publish report
        </div>

        <Cursor x={pointer.x} y={pointer.y} down={down} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
}
