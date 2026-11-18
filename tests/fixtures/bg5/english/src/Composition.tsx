import React from 'react';
import {AbsoluteFill, random, useCurrentFrame, useVideoConfig} from 'remotion';
import {ThreeCanvas} from '@remotion/three';

export const COMPOSITION_FPS = 30;
export const COMPOSITION_DURATION_IN_FRAMES = 240;
export const COMPOSITION_WIDTH = 1920;
export const COMPOSITION_HEIGHT = 1080;

// Waiting on the render, rendered in 3D. Macro shot of a machined aluminium
// progress rail whose amber fill grows steadily across the shot; slow
// push-in, then a rack focus from the rail to a laptop glowing in the dark
// behind it. Teal and amber, anamorphic flare, shallow depth of field, grain.
// Depth of field: the rail and the background render in separate passes that
// share one camera, and each pass is blurred on its own to pull focus.

const FPS = COMPOSITION_FPS;
const FOV = 30;
const TAN = Math.tan(((FOV / 2) * Math.PI) / 180);
const AMBER = '#ffa24a';
const TEAL = '#4fd1e0';

const clamp = (x: number) => Math.max(0, Math.min(1, x));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const easeOut = (x: number) => 1 - Math.pow(1 - clamp(x), 3);
const easeInOut = (x: number) => {
	const c = clamp(x);
	return c < 0.5 ? 4 * c * c * c : 1 - Math.pow(-2 * c + 2, 3) / 2;
};
// Camera-space point → pixel.
const proj = (x: number, y: number, z: number) => ({px: 960 + (x / (-z * TAN)) * 540, py: 540 - (y / (-z * TAN)) * 540});

// The rail: placed in camera space, angled so it recedes to the right.
const railPose = (t: number) => {
	const push = easeInOut(t / 8);
	return {x: lerp(0.2, 0.1, push), y: -0.27, z: lerp(-1.75, -1.4, push), ry: 0.42};
};
const fillEnd = (t: number) => lerp(-0.62, 2.9, clamp(t / 8));
const toCamera = (pose: {x: number; y: number; z: number; ry: number}, lx: number, ly: number) => ({
	x: pose.x + lx * Math.cos(pose.ry),
	y: pose.y + ly,
	z: pose.z - lx * Math.sin(pose.ry),
});

const Lights: React.FC<{tip: {x: number; y: number; z: number}}> = ({tip}) => (
	<>
		<ambientLight intensity={0.03} />
		<pointLight position={[tip.x, tip.y + 0.06, tip.z + 0.12]} intensity={1.4} color={AMBER} distance={4} decay={2} />
		<pointLight position={[1.8, 0.9, -4]} intensity={9} color={TEAL} distance={12} decay={2} />
		<spotLight position={[-0.8, 1.2, -0.4]} angle={0.7} penumbra={1} intensity={5} color="#e8eeff" distance={6} decay={2} />
		<pointLight position={[0.9, 0.1, -0.9]} intensity={0.8} color={TEAL} distance={3} decay={2} />
	</>
);

const Rail: React.FC<{t: number}> = ({t}) => {
	const pose = railPose(t);
	const end = fillEnd(t);
	const start = -3.2;
	const lightGain = lerp(1, 1.6, clamp(t / 8));
	return (
		<group position={[pose.x, pose.y, pose.z]} rotation={[0.05, pose.ry, 0]}>
			{/* Machined aluminium body with chamfered top edges */}
			<mesh>
				<boxGeometry args={[6.4, 0.07, 0.12]} />
				<meshStandardMaterial color="#9ea2aa" roughness={0.28} metalness={1} />
			</mesh>
			{[-1, 1].map((side) => (
				<mesh key={side} position={[0, 0.035, side * 0.052]} rotation={[side * 0.6, 0, 0]}>
					<boxGeometry args={[6.4, 0.012, 0.02]} />
					<meshStandardMaterial color="#c8ccd3" roughness={0.18} metalness={1} />
				</mesh>
			))}
			{/* Dark channel cut into the top */}
			<mesh position={[0, 0.036, 0]}>
				<boxGeometry args={[6.4, 0.004, 0.05]} />
				<meshStandardMaterial color="#060607" roughness={0.5} metalness={0.3} />
			</mesh>
			{/* Amber fill and its hot leading edge */}
			<mesh position={[(start + end) / 2, 0.04, 0]}>
				<boxGeometry args={[end - start, 0.008, 0.036]} />
				<meshStandardMaterial color="#000000" emissive={AMBER} emissiveIntensity={2.4 * lightGain} />
			</mesh>
			<mesh position={[end, 0.042, 0]}>
				<boxGeometry args={[0.03, 0.012, 0.04]} />
				<meshStandardMaterial color="#000000" emissive="#fff0d8" emissiveIntensity={5 * lightGain} />
			</mesh>
			{/* Engraved ticks */}
			{Array.from({length: 64}, (_, i) => (
				<mesh key={i} position={[-3.15 + i * 0.1, 0.0, 0.0605]}>
					<boxGeometry args={[0.004, i % 5 === 0 ? 0.04 : 0.022, 0.002]} />
					<meshStandardMaterial color="#3a3c41" roughness={0.6} metalness={0.8} />
				</mesh>
			))}
		</group>
	);
};

// Out-of-focus background: a laptop glowing in the dark, practical lights.
const Background: React.FC<{t: number}> = ({t}) => {
	const glow = 0.95 + Math.sin(t * 1.3) * 0.05;
	return (
		<group>
			<group position={[0.55, -0.55, -7.5]} rotation={[0.1, -0.5, 0]}>
				<mesh>
					<boxGeometry args={[1.6, 0.04, 1.1]} />
					<meshStandardMaterial color="#8d9097" roughness={0.3} metalness={1} />
				</mesh>
				<group position={[0, 0.02, -0.55]} rotation={[-0.25, 0, 0]}>
					<mesh position={[0, 0.52, 0]}>
						<boxGeometry args={[1.6, 1.04, 0.03]} />
						<meshStandardMaterial color="#8d9097" roughness={0.3} metalness={1} />
					</mesh>
					<mesh position={[0, 0.53, 0.017]}>
						<planeGeometry args={[1.5, 0.94]} />
						<meshStandardMaterial color="#000000" emissive="#0f3a44" emissiveIntensity={1.0 * glow} />
					</mesh>
					{/* App UI: viewer, sidebar, timeline strips */}
					<mesh position={[0.12, 0.66, 0.018]}>
						<planeGeometry args={[1.0, 0.5]} />
						<meshStandardMaterial color="#000000" emissive="#2a7f8f" emissiveIntensity={0.9 * glow} />
					</mesh>
					<mesh position={[-0.6, 0.53, 0.018]}>
						<planeGeometry args={[0.22, 0.86]} />
						<meshStandardMaterial color="#000000" emissive="#14505c" emissiveIntensity={0.8} />
					</mesh>
					{[0, 1, 2].map((i) => (
						<mesh key={i} position={[0.12, 0.33 - i * 0.07, 0.018]}>
							<planeGeometry args={[1.0, 0.04]} />
							<meshStandardMaterial color="#000000" emissive={i === 1 ? '#7a4a20' : '#1c5f6c'} emissiveIntensity={0.9} />
						</mesh>
					))}
					<mesh position={[0.12, 0.12, 0.019]}>
						<planeGeometry args={[0.9, 0.012]} />
						<meshStandardMaterial color="#000000" emissive="#e9fdff" emissiveIntensity={1.6} />
					</mesh>
				</group>
			</group>
			<pointLight position={[0.55, 0.1, -6.8]} intensity={4} color={TEAL} distance={6} decay={2} />
			<mesh position={[0, -1.1, -7]} rotation={[-Math.PI / 2, 0, 0]}>
				<planeGeometry args={[30, 30]} />
				<meshStandardMaterial color="#0a0a0b" roughness={0.35} metalness={0.4} />
			</mesh>
			{/* Bokeh: distant practicals */}
			{Array.from({length: 26}, (_, i) => {
				const warm = random(`w${i}`) > 0.5;
				return (
					<mesh key={i} position={[-4 + random(`x${i}`) * 8, -0.6 + random(`y${i}`) * 2.6, -9 - random(`z${i}`) * 8]}>
						<sphereGeometry args={[0.1 + random(`r${i}`) * 0.16, 16, 16]} />
						<meshStandardMaterial color="#000000" emissive={warm ? AMBER : TEAL} emissiveIntensity={1 + random(`i${i}`) * 2} />
					</mesh>
				);
			})}
		</group>
	);
};

const Pass: React.FC<{t: number; blur: number; children: React.ReactNode}> = ({t, blur, children}) => {
	const {width, height} = useVideoConfig();
	const tip = toCamera(railPose(t), fillEnd(t), 0.04);
	return (
		<div style={{position: 'absolute', left: 0, top: 0, width, height, filter: blur > 0.2 ? `blur(${blur}px)` : undefined}}>
			<ThreeCanvas data-ms-timeline={{"duration":null,"keyframes":{"cameraFov":[{"frame":0,"easing":"linear","value":30}],"cameraRotationX":[{"frame":0,"easing":"linear","value":0}],"cameraRotationZ":[{"value":0,"easing":"linear","frame":0}],"cameraRotationY":[{"frame":0,"easing":"linear","value":0}],"cameraPositionY":[{"value":0,"easing":"linear","frame":0}],"cameraPositionX":[{"frame":0,"easing":"linear","value":0}],"cameraPositionZ":[{"frame":0,"easing":"linear","value":0}]},"from":0}} width={width} height={height} camera={{position: [0, 0, 0], rotation: [0, 0, 0], fov: 30, near: 0.05, far: 60}}>
				<fog attach="fog" args={['#020203', 4, 22]} />
				<Lights tip={tip} />
				{children}
			</ThreeCanvas>
		</div>
	);
};

const Grain: React.FC<{f: number}> = ({f}) => (
	<>
		{Array.from({length: 520}, (_, i) => (
			<div key={i} style={{position: 'absolute', left: random(`gx${f}-${i}`) * 1920, top: random(`gy${f}-${i}`) * 1080, width: 1.5, height: 1.5, background: random(`gc${f}-${i}`) > 0.5 ? '#ffffff' : '#000000', opacity: 0.015 + random(`go${f}-${i}`) * 0.03}} />
		))}
	</>
);

const FONT = 'Helvetica Neue, Arial, sans-serif';
const Title: React.FC<{s: number; from: number; to: number; size?: number; weight?: number; color?: string; top?: number; children: React.ReactNode}> = ({s, from, to, size = 92, weight = 600, color = '#f5f5f7', top, children}) => {
	if (s < from - 0.05 || s > to + 0.05) return null;
	const inP = easeOut((s - from) / 0.9);
	const outP = clamp((to - s) / 0.5);
	const o = Math.min(inP, outP);
	const drift = 1.04 - 0.04 * easeOut((s - from) / (to - from));
	return (
		<div style={{position: 'absolute', left: 0, top: top === undefined ? 0 : top, width: 1920, height: top === undefined ? 1080 : size * 1.3, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
			<div style={{fontFamily: FONT, fontSize: size, fontWeight: weight, letterSpacing: -size * 0.03, lineHeight: 1.05, color, textAlign: 'center', opacity: o, filter: `blur(${(1 - inP) * 14}px)`, transform: `scale(${drift})`}}>{children}</div>
		</div>
	);
};


export const MyComposition: React.FC = () => {
	const f = useCurrentFrame();
	const t = f / FPS;
	// Rack focus from the rail to the laptop between 4.3 s and 5.8 s.
	const rack = easeInOut((t - 4.3) / 1.5);
	const railBlur = lerp(0, 16, rack);
	const bgBlur = lerp(14, 1.5, rack);
	const tip = toCamera(railPose(t), fillEnd(t), 0.04);
	const tp = proj(tip.x, tip.y, tip.z);
	const lap = proj(0.55, -0.0, -7.5);
	const flare = lerp(0.65, 1, clamp(t / 8));
	return (
		<AbsoluteFill style={{background: '#020203'}}>
			<Pass t={t} blur={bgBlur}>
				<Background t={t} />
			</Pass>
			<Title s={t + 11.4} from={11.9} to={15.8} size={92} top={710}>{"Until you hit."}</Title>
			<Pass t={t} blur={railBlur}>
				<Rail t={t} />
			</Pass>

			{/* Bloom and anamorphic flare on the fill's leading edge; laptop halo */}
			<div style={{position: 'absolute', left: lap.px - 420, top: lap.py - 260, width: 840, height: 520, borderRadius: 840, background: `radial-gradient(ellipse at center, rgba(79,209,224,${0.1 + 0.18 * rack}) 0%, rgba(0,0,0,0) 65%)`, mixBlendMode: 'screen'}} />
			<div style={{position: 'absolute', left: tp.px - 110, top: tp.py - 110, width: 220, height: 220, borderRadius: 220, background: 'radial-gradient(circle, rgba(255,226,180,0.85) 0%, rgba(255,162,74,0.3) 30%, rgba(0,0,0,0) 70%)', mixBlendMode: 'screen', opacity: flare}} />
			<div style={{position: 'absolute', left: tp.px - 900, top: tp.py - 4, width: 1800, height: 8, borderRadius: 8, background: 'linear-gradient(90deg, rgba(79,209,224,0) 0%, rgba(120,220,255,0.35) 30%, rgba(255,214,170,0.7) 50%, rgba(120,220,255,0.35) 70%, rgba(79,209,224,0) 100%)', filter: 'blur(2px)', mixBlendMode: 'screen', opacity: flare}} />

			{/* Grade, vignette, grain */}
			<div style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, background: 'linear-gradient(180deg, rgba(10,45,55,0.25) 0%, rgba(0,0,0,0) 55%, rgba(50,25,5,0.15) 100%)', mixBlendMode: 'soft-light'}} />
			<div style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, background: 'radial-gradient(ellipse at center, rgba(0,0,0,0) 40%, rgba(0,0,0,0.8) 100%)'}} />
			<Grain f={f} />
		</AbsoluteFill>
	);
};
