#!/usr/bin/env python3
"""Generates tests/three/public/models/probe.usdz, a small space probe for the 3D fixtures.

Meshes are triangulated with per-vertex normals and UsdPreviewSurface materials so both three.js'
USDLoader and ModelIO read identical geometry. Run: python3 tests/three/tools/make-model.py
(requires macOS usdcat/usdzip)."""
import math, os, subprocess, tempfile

def box(w, h, d):
    pts, nrm, idx = [], [], []
    faces = [((1,0,0),(0,0,-1),(0,1,0)), ((-1,0,0),(0,0,1),(0,1,0)), ((0,1,0),(1,0,0),(0,0,-1)),
             ((0,-1,0),(1,0,0),(0,0,1)), ((0,0,1),(1,0,0),(0,1,0)), ((0,0,-1),(-1,0,0),(0,1,0))]
    half = (w/2, h/2, d/2)
    for n, u, v in faces:
        base = len(pts)
        for su, sv in ((-1,-1),(1,-1),(1,1),(-1,1)):
            pts.append(tuple(half[i]*(n[i] + su*u[i] + sv*v[i]) for i in range(3)))
            nrm.append(n)
        idx += [base, base+1, base+2, base, base+2, base+3]
    return pts, nrm, idx

def cylinder(r, h, seg):
    pts, nrm, idx = [], [], []
    for i in range(seg + 1):
        a = 2*math.pi*i/seg; c, s = math.cos(a), math.sin(a)
        pts += [(r*s, h/2, r*c), (r*s, -h/2, r*c)]; nrm += [(s,0,c), (s,0,c)]
    for i in range(seg):
        a, b = 2*i, 2*i+2
        idx += [a, a+1, b, b, a+1, b+1]
    for y, ny in ((h/2, 1), (-h/2, -1)):
        center = len(pts); pts.append((0,y,0)); nrm.append((0,ny,0))
        for i in range(seg + 1):
            a = 2*math.pi*i/seg; pts.append((r*math.sin(a), y, r*math.cos(a))); nrm.append((0,ny,0))
        for i in range(seg):
            p, q = center+1+i, center+2+i
            idx += [center, p, q] if ny > 0 else [center, q, p]
    return pts, nrm, idx

def sphere(r, ws, hs):
    pts, nrm, idx = [], [], []
    for y in range(hs + 1):
        t = math.pi*y/hs
        for x in range(ws + 1):
            p = 2*math.pi*x/ws
            n = (-math.cos(p)*math.sin(t), math.cos(t), math.sin(p)*math.sin(t))
            pts.append(tuple(r*c for c in n)); nrm.append(n)
    for y in range(hs):
        for x in range(ws):
            a, b = y*(ws+1)+x+1, y*(ws+1)+x
            c, d = b+ws+1, a+ws+1
            if y: idx += [a, b, d]
            if y != hs-1: idx += [b, c, d]
    return pts, nrm, idx

fmt = lambda values: ', '.join('(%s)' % ', '.join('%.6g' % c for c in v) for v in values)
def mesh(name, geo, material, translate=(0,0,0), rotate=(0,0,0), scale=(1,1,1)):
    pts, nrm, idx = geo
    return f'''
        def Xform "{name}"
        {{
            double3 xformOp:translate = ({translate[0]}, {translate[1]}, {translate[2]})
            float3 xformOp:rotateXYZ = ({rotate[0]}, {rotate[1]}, {rotate[2]})
            float3 xformOp:scale = ({scale[0]}, {scale[1]}, {scale[2]})
            uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ", "xformOp:scale"]
            def Mesh "Geometry"
            {{
                uniform bool doubleSided = 0
                int[] faceVertexCounts = [{', '.join(['3'] * (len(idx)//3))}]
                int[] faceVertexIndices = [{', '.join(map(str, idx))}]
                point3f[] points = [{fmt(pts)}]
                normal3f[] normals = [{fmt(nrm)}] (interpolation = "vertex")
                uniform token subdivisionScheme = "none"
                rel material:binding = </Probe/Materials/{material}>
            }}
        }}'''

def material(name, color, roughness, metallic, emissive=(0,0,0)):
    return f'''
        def Material "{name}"
        {{
            token outputs:surface.connect = </Probe/Materials/{name}/Surface.outputs:surface>
            def Shader "Surface"
            {{
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor = ({color[0]}, {color[1]}, {color[2]})
                color3f inputs:emissiveColor = ({emissive[0]}, {emissive[1]}, {emissive[2]})
                float inputs:roughness = {roughness}
                float inputs:metallic = {metallic}
                token outputs:surface
            }}
        }}'''

parts = [
    mesh('Body', cylinder(0.45, 1.2, 24), 'Hull'),
    mesh('Dish', sphere(0.5, 24, 12), 'Gold', (0, 0.85, 0), (0, 0, 0), (1, 0.25, 1)),
    mesh('Antenna', cylinder(0.04, 0.7, 8), 'Hull', (0, 1.25, 0)),
    mesh('Beacon', sphere(0.09, 12, 8), 'Beacon', (0, 1.62, 0)),
    mesh('PanelLeft', box(1.3, 0.05, 0.55), 'Panel', (-1.15, 0, 0), (0, 0, 8)),
    mesh('PanelRight', box(1.3, 0.05, 0.55), 'Panel', (1.15, 0, 0), (0, 0, -8)),
    mesh('Strut', box(0.9, 0.06, 0.06), 'Hull', (0, 0, 0), (0, 0, 0), (2.2, 1, 1)),
    mesh('Thruster', cylinder(0.22, 0.3, 16), 'Gold', (0, -0.75, 0)),
]
materials = [material('Hull', (0.62, 0.64, 0.7), 0.35, 0.8), material('Gold', (0.9, 0.62, 0.18), 0.3, 1.0),
             material('Panel', (0.05, 0.12, 0.45), 0.25, 0.2), material('Beacon', (1, 0.2, 0.1), 0.6, 0, (1, 0.15, 0.05))]
usda = f'''#usda 1.0
(
    defaultPrim = "Probe"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "Probe"
{{{''.join(parts)}
    def Scope "Materials"
    {{{''.join(materials)}
    }}
}}
'''
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, 'public', 'models', 'probe.usdz')
with tempfile.TemporaryDirectory() as tmp:
    text = os.path.join(tmp, 'probe.usda'); crate = os.path.join(tmp, 'probe.usdc')
    open(text, 'w').write(usda)
    subprocess.run(['usdcat', text, '-o', crate], check=True)
    if os.path.exists(out): os.remove(out)
    subprocess.run(['usdzip', out, 'probe.usdc'], check=True, cwd=tmp)
print('wrote', out)
