// SPDX-FileCopyrightText: 2026 Alex Ibragimov
// SPDX-License-Identifier: MIT

const FPS = 30;

export function bezier(
  x1: number,
  y1: number,
  x2: number,
  y2: number,
): (t: number) => number {
  const curve = (a: number, b: number, t: number) => {
    const c = 3 * a;
    const bb = 3 * (b - a) - c;
    const aa = 1 - c - bb;
    return ((aa * t + bb) * t + c) * t;
  };
  const slope = (a: number, b: number, t: number) => {
    const c = 3 * a;
    const bb = 3 * (b - a) - c;
    const aa = 1 - c - bb;
    return (3 * aa * t + 2 * bb) * t + c;
  };

  return (x: number) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;

    let t = x;
    for (let i = 0; i < 8; i++) {
      const err = curve(x1, x2, t) - x;
      if (Math.abs(err) < 1e-6) return curve(y1, y2, t);
      const d = slope(x1, x2, t);
      if (Math.abs(d) < 1e-6) break;
      t -= err / d;
    }

    let lo = 0;
    let hi = 1;
    t = x;
    while (hi - lo > 1e-6) {
      if (curve(x1, x2, t) < x) lo = t;
      else hi = t;
      t = (lo + hi) / 2;
    }
    return curve(y1, y2, t);
  };
}

function span(
  x: number,
  inA: number,
  inB: number,
  outA: number,
  outB: number,
  easing: (t: number) => number,
): number {
  if (inB === inA) return outB;
  const t = Math.min(1, Math.max(0, (x - inA) / (inB - inA)));
  return outA + (outB - outA) * easing(t);
}

type SpringConfig = { damping: number; stiffness: number; mass: number };

function oscillator(t: number, { damping, stiffness, mass }: SpringConfig) {
  const w0 = Math.sqrt(stiffness / mass);
  const zeta = damping / (2 * Math.sqrt(stiffness * mass));
  if (zeta < 1) {
    const wd = w0 * Math.sqrt(1 - zeta * zeta);
    return (
      1 -
      Math.exp(-zeta * w0 * t) *
        (Math.cos(wd * t) + ((zeta * w0) / wd) * Math.sin(wd * t))
    );
  }
  return 1 - Math.exp(-w0 * t) * (1 + w0 * t);
}

function settleTime(config: SpringConfig, eps = 1e-3): number {
  const { damping, stiffness, mass } = config;
  const w0 = Math.sqrt(stiffness / mass);
  const zeta = damping / (2 * Math.sqrt(stiffness * mass));
  const decay = zeta < 1 ? zeta * w0 : w0;
  const wd = zeta < 1 ? w0 * Math.sqrt(1 - zeta * zeta) : w0;
  const amp = zeta < 1 ? Math.sqrt(1 + ((zeta * w0) / wd) ** 2) : 2;
  return Math.max(1e-3, -Math.log(eps / amp) / decay);
}

export const EASE = {
  out: bezier(0.16, 1, 0.3, 1),
  outBack: bezier(0.34, 1.56, 0.64, 1),
  inOut: bezier(0.45, 0, 0.55, 1),
  inOutCubic: (t: number) =>
    t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2,
  word: bezier(0.22, 1, 0.36, 1),
} as const;

export const DUR = {
  press: 4,
  chip: 6,
  panel: 9,
  sheet: 13,
  hero: 18,
  word: 15,
} as const;

export const STAGGER = 2;

export function ramp(
  frame: number,
  at: number,
  dur: number = DUR.panel,
  easing: (t: number) => number = EASE.out,
): number {
  return span(frame, at, at + dur, 0, 1, easing);
}

export function mix(t: number, from: number, to: number): number {
  return from + (to - from) * t;
}

function parseHexRgba(color: string): [number, number, number, number] {
  if (color === "transparent") return [0, 0, 0, 0];
  const hex = color.replace(/^#/, "");
  const r = parseInt(hex.slice(0, 2), 16) / 255;
  const g = parseInt(hex.slice(2, 4), 16) / 255;
  const b = parseInt(hex.slice(4, 6), 16) / 255;
  const a = hex.length >= 8 ? parseInt(hex.slice(6, 8), 16) / 255 : 1;
  return [r, g, b, a];
}

function toLinear(c: number): number {
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}

function fromLinear(c: number): number {
  const clamped = Math.min(1, Math.max(0, c));
  return clamped <= 0.0031308
    ? 12.92 * clamped
    : 1.055 * clamped ** (1 / 2.4) - 0.055;
}

function srgbToOklab(r: number, g: number, b: number): [number, number, number] {
  const lr = toLinear(r);
  const lg = toLinear(g);
  const lb = toLinear(b);
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

function oklabToSrgb(L: number, a: number, b: number): [number, number, number] {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    fromLinear(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    fromLinear(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    fromLinear(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
  ];
}

/** True CSS Color 4 premultiplied OKLab interpolation matching `color-mix(in oklab, ...)`. */
export function mixToken(t: number, from: string, to: string): string {
  const u = Math.min(1, Math.max(0, t));
  if (u <= 0) return from;
  if (u >= 1) return to;
  const [r1, g1, b1, a1] = parseHexRgba(from);
  const [r2, g2, b2, a2] = parseHexRgba(to);
  const [L1, A1, B1] = srgbToOklab(r1, g1, b1);
  const [L2, A2, B2] = srgbToOklab(r2, g2, b2);
  const alpha = mix(u, a1, a2);
  if (alpha <= 1e-6) return "transparent";
  const L = mix(u, L1 * a1, L2 * a2) / alpha;
  const A = mix(u, A1 * a1, A2 * a2) / alpha;
  const B = mix(u, B1 * a1, B2 * a2) / alpha;
  const [r, g, b] = oklabToSrgb(L, A, B);
  return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${Number(alpha.toFixed(3))})`;
}

type EnterOpts = {
  dur?: number;
  y?: number;
  x?: number;
  scale?: number;
  easing?: (t: number) => number;
};

export function enter(
  frame: number,
  at: number,
  opts: EnterOpts = {},
): { opacity: number; transform: string } {
  const {
    dur = DUR.panel,
    y = 12,
    x = 0,
    scale = 1,
    easing = EASE.out,
  } = opts;
  const t = ramp(frame, at, dur, easing);
  const parts = [
    `translate(${mix(t, x, 0).toFixed(2)}px, ${mix(t, y, 0).toFixed(2)}px)`,
  ];
  if (scale !== 1) parts.push(`scale(${mix(t, scale, 1).toFixed(4)})`);
  return { opacity: t, transform: parts.join(" ") };
}

export function enterAt(
  frame: number,
  at: number,
  index: number,
  opts: EnterOpts = {},
): { opacity: number; transform: string } {
  return enter(frame, at + index * STAGGER, opts);
}

export function leave(
  frame: number,
  at: number,
  opts: EnterOpts = {},
): { opacity: number; transform: string } {
  const { dur = DUR.chip, y = 12, x = 0, easing = EASE.out } = opts;
  const t = ramp(frame, at, dur, easing);
  return {
    opacity: 1 - t,
    transform: `translate(${mix(t, 0, x).toFixed(2)}px, ${mix(t, 0, y).toFixed(2)}px)`,
  };
}

export function pop(
  frame: number,
  at: number,
  config: { damping?: number; stiffness?: number; mass?: number } = {},
  durationInFrames: number = DUR.sheet,
): number {
  const cfg = { damping: 14, stiffness: 120, mass: 0.8, ...config };
  const elapsed = frame - at;
  if (elapsed <= 0) return 0;
  if (elapsed >= durationInFrames) return 1;
  const t = (elapsed / durationInFrames) * settleTime(cfg);
  return oscillator(t, cfg);
}

export function press(frame: number, at: number, depth = 0.04): number {
  const len = DUR.press * 2;
  if (frame < at || frame >= at + len) return 1;
  const t = (frame - at) / (len - 1);
  return 1 - depth * Math.sin(Math.PI * t);
}

export function countTo(
  frame: number,
  at: number,
  to: number,
  dur: number = DUR.sheet,
): number {
  return Math.round(mix(ramp(frame, at, dur, EASE.out), 0, to));
}

export function caretOn(frame: number): boolean {
  return Math.floor(frame / (FPS / 2)) % 2 === 0;
}

export function typed(
  frame: number,
  at: number,
  text: string,
  cps = 28,
): string {
  if (frame <= at) return "";
  return text.slice(0, Math.floor(((frame - at) / FPS) * cps));
}
