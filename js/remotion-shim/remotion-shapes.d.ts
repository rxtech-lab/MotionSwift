export interface ShapeInfo {path: string; width: number; height: number; transformOrigin: string; instructions: readonly unknown[]}
export declare function makeRect(options: {width: number; height: number; edgeRoundness?: number | null; cornerRadius?: number}): ShapeInfo;
export declare function makeCircle(options: {radius: number}): ShapeInfo;
export declare function makeEllipse(options: {rx: number; ry: number}): ShapeInfo;
