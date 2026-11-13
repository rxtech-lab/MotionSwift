/** Pinned MIT, DOM-free @remotion/paths subset. */
export declare function getLength(path: string): number;
export declare function evolvePath(progress: number, path: string): {strokeDasharray: string; strokeDashoffset: number};
export declare function translatePath(path: string, x: number, y: number): string;
export declare function scalePath(path: string, scaleX: number, scaleY: number): string;
