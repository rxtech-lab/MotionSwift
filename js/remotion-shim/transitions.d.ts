import type {ComponentType, ReactNode} from 'react';
export interface Timing {readonly __msTiming: true; readonly duration: number; readonly easing: (progress: number) => number}
export interface Presentation {readonly __msPresentation: 'fade' | 'slide' | 'wipe'}
export declare function linearTiming(options: {durationInFrames: number; easing?: (progress: number) => number}): Timing;
export declare const TransitionSeries: ComponentType<{children?: ReactNode}> & {
  Sequence: ComponentType<{durationInFrames: number; children?: ReactNode}>;
  Transition: ComponentType<{timing: Timing; presentation: Presentation}>;
};
