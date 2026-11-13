use skia_safe::{
    canvas::SaveLayerRec, color_filters, gpu, images, surfaces, AlphaType, Color, ColorMatrix,
    ColorType, Data, EncodedImageFormat, Font, FontMgr, FontStyle, ImageInfo, Paint, Rect,
    RuntimeEffect, Surface,
};
use std::ffi::{c_char, c_void, CStr};
extern "C" {
    fn msk_solid_rrect(
        canvas: *const c_void,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        radius: f32,
        color: u32,
    );
    fn msk_rrect_mask(
        canvas: *const c_void,
        left: f32,
        top: f32,
        right: f32,
        bottom: f32,
        radius: f32,
    );
    fn msk_svg_paint_canvas(canvas: *const c_void) -> *mut c_void;
    fn msk_svg_paint_canvas_destroy(canvas: *mut c_void);
    fn msk_path_coverage(
        svg: *const c_char,
        matrix: *const f32,
        output: *mut u8,
        width: i32,
        height: i32,
    ) -> bool;
}

// Shader compilation is independent of the target backend. A bounded per-worker
// cache keeps retained video renders from recompiling identical programs each frame.
thread_local! {
    static SHADER_EFFECTS:std::cell::RefCell<std::collections::HashMap<String,RuntimeEffect>>=std::cell::RefCell::new(std::collections::HashMap::new());
    static COLOR_EFFECTS:std::cell::RefCell<std::collections::HashMap<String,RuntimeEffect>>=std::cell::RefCell::new(std::collections::HashMap::new());
}
fn shader_effect(source: &str) -> Result<RuntimeEffect, String> {
    SHADER_EFFECTS.with(|cache| {
        let mut cache = cache.borrow_mut();
        if let Some(effect) = cache.get(source) {
            return Ok(effect.clone());
        }
        let effect = RuntimeEffect::make_for_shader(source, None)?;
        if cache.len() >= 64 {
            cache.clear();
        }
        cache.insert(source.to_owned(), effect.clone());
        Ok(effect)
    })
}
fn color_effect(source: &str) -> Result<RuntimeEffect, String> {
    COLOR_EFFECTS.with(|cache| {
        let mut cache = cache.borrow_mut();
        if let Some(effect) = cache.get(source) {
            return Ok(effect.clone());
        }
        let effect = RuntimeEffect::make_for_color_filter(source, None)?;
        if cache.len() >= 64 {
            cache.clear();
        }
        cache.insert(source.to_owned(), effect.clone());
        Ok(effect)
    })
}

/// One drawing target. A handle is owned by Swift's Canvas and confined to one render
/// worker thread; GPU handles also own their Ganesh context, which is not thread-safe.
/// Field order matters: the surface must be dropped before the context that backs it.
pub struct Target {
    surface: Surface,
    failed: bool,
    effects_precision: bool,
    backdrop_group: bool,
    pending_clip: Option<skia_safe::Shader>,
    dither_origin: (f32, f32),
    layers: Vec<EffectSurface>,
    depth: usize,
    context: Option<gpu::DirectContext>,
    solid: Option<RuntimeEffect>,
    resolve: Option<RuntimeEffect>,
    byte_blend: Option<RuntimeEffect>,
}
struct EffectSurface {
    parent: Surface,
    depth: usize,
    paint: Paint,
    clip: Option<skia_safe::Shader>,
    alpha: f32,
    quantize: bool,
    dither_origin: (f32, f32),
    mask: Option<skia_safe::Shader>,
}

impl Target {
    fn effect_surface(&mut self, paint: Paint, color_type: ColorType, alpha: f32, quantize: bool) {
        let info = ImageInfo::new(
            (self.surface.width(), self.surface.height()),
            color_type,
            AlphaType::Premul,
            None,
        );
        let Some(mut child) = self.surface.new_surface(&info) else {
            self.failed = true;
            self.surface.canvas().save();
            self.depth += 1;
            return;
        };
        child.canvas().clear(Color::TRANSPARENT);
        child
            .canvas()
            .set_matrix(&self.surface.canvas().local_to_device());
        let parent = std::mem::replace(&mut self.surface, child);
        self.layers.push(EffectSurface {
            parent,
            depth: self.depth,
            paint,
            clip: self.pending_clip.take(),
            alpha,
            quantize,
            dither_origin: self.dither_origin,
            mask: None,
        });
        self.depth += 1;
    }
    fn restore(&mut self) {
        if self.depth == 0 {
            self.failed = true;
            return;
        }
        if self
            .layers
            .last()
            .is_some_and(|layer| layer.depth + 1 == self.depth)
        {
            let mut image = self.surface.image_snapshot();
            let layer = self.layers.pop().unwrap();
            if layer.quantize && layer.paint.image_filter().is_some() {
                let info = ImageInfo::new(
                    (image.width(), image.height()),
                    ColorType::RGBA8888,
                    AlphaType::Premul,
                    None,
                );
                let Some(mut filtered) = self.surface.new_surface(&info) else {
                    self.failed = true;
                    self.surface = layer.parent;
                    self.dither_origin = layer.dither_origin;
                    self.depth -= 1;
                    return;
                };
                filtered.canvas().clear(Color::TRANSPARENT);
                let mut paint = Paint::default();
                paint.set_image_filter(layer.paint.image_filter());
                filtered.canvas().draw_image(&image, (0, 0), Some(&paint));
                image = filtered.image_snapshot();
            }
            self.surface = layer.parent;
            self.dither_origin = layer.dither_origin;
            let backdrop = self.surface.image_snapshot();
            let canvas = self.surface.canvas();
            canvas.save();
            canvas.reset_matrix();
            if layer.quantize
                && layer.paint.blend_mode_or(skia_safe::BlendMode::SrcOver)
                    == skia_safe::BlendMode::SrcOver
            {
                let source = image
                    .to_shader(None, skia_safe::SamplingOptions::default(), None)
                    .unwrap();
                let background = backdrop
                    .to_shader(None, skia_safe::SamplingOptions::default(), None)
                    .unwrap();
                let has_mask = layer.mask.is_some();
                let has_clip = layer.clip.is_some();
                let white = skia_safe::shaders::color(Color::WHITE);
                let mask = layer.mask.unwrap_or_else(|| white.clone());
                let clip = layer.clip.unwrap_or(white);
                let source_code="uniform shader content;uniform shader backdrop;uniform shader mask;uniform shader clip;uniform float opacity;uniform float hasMask;uniform float hasClip;half4 main(float2 p){float4 src=floor(float4(content.eval(p))*255.0+0.5)/255.0;float coverage=1.0;if(hasClip>0.5){float2 data=floor(float2(clip.eval(p).rg)*255.0+0.5);coverage=(data.r+data.g/255.0)/255.0;if(clip.eval(p).b>0.5)coverage=floor(coverage*4.0+0.5)/4.0;}if(hasMask>0.5){float a=floor(float(mask.eval(p).a)*255.0+0.5)/255.0;src=floor(src*a*255.0+0.5)/255.0;}src*=opacity;float4 original=float4(backdrop.eval(p));if(src.a<=0.0)return half4(original);float4 dst=floor(original*255.0+0.5)/255.0;float4 blended=src+dst*(1.0-src.a);if(hasClip>0.5 && clip.eval(p).b>0.5)blended=floor(blended*255.0+0.5)/255.0;return half4(floor(mix(dst,blended,coverage)*255.0+0.5)/255.0);}";
                let effect = shader_effect(source_code).unwrap();
                let values = [
                    layer.alpha,
                    if has_mask { 1. } else { 0. },
                    if has_clip { 1. } else { 0. },
                ];
                let bytes: Vec<u8> = values.iter().flat_map(|v| v.to_ne_bytes()).collect();
                let shader = effect
                    .make_shader(
                        Data::new_copy(&bytes),
                        &[source.into(), background.into(), mask.into(), clip.into()],
                        None,
                    )
                    .unwrap();
                let mut paint = Paint::default();
                paint
                    .set_shader(shader)
                    .set_blend_mode(skia_safe::BlendMode::Src);
                canvas.draw_rect(
                    Rect::from_wh(image.width() as f32, image.height() as f32),
                    &paint,
                );
            } else {
                canvas.draw_image(&image, (0, 0), Some(&layer.paint));
            }
            canvas.restore();
        } else {
            self.surface.canvas().restore();
        }
        self.depth -= 1;
    }
}

// Ganesh folds constant paint colours (and colour filters on them) into premultiplied
// byte vertex colours, rounding colour*coverage (81.5 -> 82). A runtime shader with a
// float uniform cannot be folded, so GPU quads keep the raster pipeline's precision.
const SOLID_SKSL: &str =
    "uniform float4 color; half4 main(float2 p) { return half4(color.rgb * color.a, color.a); }";

fn valid(width: i32, height: i32) -> bool {
    width > 0 && height > 0 && width <= 16384 && height <= 16384
}
fn boxed(mut surface: Surface, context: Option<gpu::DirectContext>) -> *mut Target {
    surface.canvas().clear(Color::TRANSPARENT);
    let solid = if context.is_some() {
        match shader_effect(SOLID_SKSL) {
            Ok(effect) => Some(effect),
            Err(_) => return std::ptr::null_mut(),
        }
    } else {
        None
    };
    Box::into_raw(Box::new(Target { surface, failed:false, effects_precision:false, backdrop_group:false, pending_clip:None, dither_origin:(0.,0.), layers: Vec::new(), depth: 0, context, solid, resolve:None, byte_blend:RuntimeEffect::make_for_blender("uniform float sourceQuantize;half4 main(half4 source,half4 destination){float4 src=float4(source);if(sourceQuantize>0.5)src=floor(src*255.0+0.5)/255.0;float4 dst=floor(float4(destination)*255.0+0.5)/255.0;return half4(floor((src+dst*(1.0-src.a))*255.0+0.5)/255.0);}",None).ok() }))
}

#[no_mangle]
pub extern "C" fn msk_create(width: i32, height: i32) -> *mut Target {
    if !valid(width, height) {
        return std::ptr::null_mut();
    }
    surfaces::raster_n32_premul((width, height))
        .map(|s| boxed(s, None))
        .unwrap_or(std::ptr::null_mut())
}
/// Creates a Metal-backed Ganesh surface. `device` and `queue` are borrowed
/// `id<MTLDevice>` / `id<MTLCommandQueue>` pointers; Skia retains its own references.
#[no_mangle]
pub unsafe extern "C" fn msk_create_gpu(
    width: i32,
    height: i32,
    device: *const c_void,
    queue: *const c_void,
) -> *mut Target {
    if !valid(width, height) || device.is_null() || queue.is_null() {
        return std::ptr::null_mut();
    }
    let backend = gpu::mtl::BackendContext::new(device, queue);
    // Shader tiling implements transparent borders on the GPU without requiring a
    // clamp-to-border sampler, which virtual Metal devices do not support.
    let mut options = gpu::ContextOptions::default();
    options.reduced_shader_variations = true;
    let Some(mut context) = gpu::direct_contexts::make_metal(&backend, Some(&options)) else {
        return std::ptr::null_mut();
    };
    // Blend in half-float and round to 8 bits once, on readback, like the raster backend's
    // F16 layers. This also makes opaque layers unnecessary on the GPU (see msk_save).
    let color_type = ColorType::RGBAF16;
    let info = ImageInfo::new((width, height), color_type, AlphaType::Premul, None);
    gpu::surfaces::render_target(
        &mut context,
        gpu::Budgeted::Yes,
        &info,
        None,
        gpu::SurfaceOrigin::TopLeft,
        None,
        false,
        None,
    )
    .map(|s| boxed(s, Some(context)))
    .unwrap_or(std::ptr::null_mut())
}
/// Select the CSS effects pipeline before drawing a frame. Existing SVG data-URI
/// projects keep the original raster/saveLayer behavior and their exact snapshots.
#[no_mangle]
pub unsafe extern "C" fn msk_effects_precision(s: *mut Target, enabled: bool) -> bool {
    let target = &mut *s;
    if target.effects_precision == enabled {
        return true;
    }
    if target.depth != 0 || !target.layers.is_empty() {
        return false;
    }
    if target.context.is_none() {
        let info = ImageInfo::new(
            (target.surface.width(), target.surface.height()),
            if enabled {
                ColorType::RGBAF16
            } else {
                ColorType::N32
            },
            AlphaType::Premul,
            None,
        );
        let Some(surface) = surfaces::raster(&info, None, None) else {
            return false;
        };
        target.surface = surface;
    }
    target.effects_precision = enabled;
    target.pending_clip = None;
    target.backdrop_group = false;
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_clear(s: *mut Target) {
    (*s).surface.canvas().clear(Color::TRANSPARENT);
}
#[no_mangle]
pub unsafe extern "C" fn msk_destroy(s: *mut Target) {
    if !s.is_null() {
        drop(Box::from_raw(s));
    }
}
/// Multiplies alpha in a float colour filter (a fragment-shader uniform on Ganesh).
fn alpha_filter(alpha: f32) -> skia_safe::ColorFilter {
    let mut matrix = ColorMatrix::default();
    matrix.set_scale(1., 1., 1., Some(alpha));
    color_filters::matrix(&matrix, None)
}
#[no_mangle]
pub unsafe extern "C" fn msk_save(s: *mut Target, alpha: f32) {
    (*s).depth += 1;
    let mut paint = Paint::default();
    let gpu = (*s).context.is_some();
    if !(*s).effects_precision {
        if gpu && alpha >= 1. {
            (*s).surface.canvas().save();
            return;
        }
        if gpu {
            paint.set_color_filter(alpha_filter(alpha));
        } else {
            paint.set_alpha_f(alpha);
        }
        (*s).surface.canvas().save_layer(
            &SaveLayerRec::default()
                .paint(&paint)
                .flags(skia_safe::canvas::SaveLayerFlags::F16_COLOR_TYPE),
        );
        return;
    }
    if (*s).backdrop_group {
        (*s).backdrop_group = false;
        (*s).depth -= 1;
        let background = (*s).surface.image_snapshot();
        paint.set_blend_mode(skia_safe::BlendMode::Src);
        (*s).effect_surface(paint, ColorType::RGBA8888, 1., false);
        let canvas = (*s).surface.canvas();
        canvas.save();
        canvas.reset_matrix();
        canvas.draw_image(background, (0, 0), None);
        canvas.restore();
        return;
    }
    if alpha >= 1. && (*s).pending_clip.is_none() {
        // The Metal target is already half-float, so an opaque layer adds a texture pass
        // without changing any pixel. Independent opacity/effect surfaces provide the needed precision.
        (*s).surface.canvas().save();
        return;
    }
    if gpu {
        // Ganesh packs paint colours into 8-bit vertex colours (0.5 -> 128/255). A colour
        // matrix keeps layer opacity as a float uniform, like the raster pipeline does.
        paint.set_color_filter(alpha_filter(alpha));
    } else {
        paint.set_alpha_f(alpha);
    }
    if (*s).pending_clip.is_some() {
        (*s).depth -= 1;
        paint.set_alpha_f(1.).set_color_filter(alpha_filter(alpha));
        (*s).effect_surface(paint, ColorType::RGBA8888, alpha, true);
        return;
    }

    (*s).depth -= 1;
    paint.set_alpha_f(1.).set_color_filter(alpha_filter(alpha));
    (*s).effect_surface(paint, ColorType::RGBAF16, alpha, false);
    return;
}
#[no_mangle]
pub unsafe extern "C" fn msk_restore(s: *mut Target) {
    (*s).restore();
}
#[no_mangle]
pub unsafe extern "C" fn msk_translate(s: *mut Target, x: f32, y: f32) {
    (*s).surface.canvas().translate((x, y));
}
#[no_mangle]
pub unsafe extern "C" fn msk_rotate(s: *mut Target, degrees: f32) {
    (*s).surface.canvas().rotate(degrees, None);
}
#[no_mangle]
pub unsafe extern "C" fn msk_scale(s: *mut Target, x: f32, y: f32) {
    (*s).surface.canvas().scale((x, y));
}
#[no_mangle]
pub unsafe extern "C" fn msk_clip(s: *mut Target, w: f32, h: f32) {
    (*s).surface
        .canvas()
        .clip_rect(Rect::from_xywh(0., 0., w, h), None, true);
}
// Use device-space coverage for axis-aligned quads, retaining its 256-step
// precision through floating-point layers. Converting coverage to an alpha byte
// prematurely shifts scaled edges by one channel value against GPU references.
fn axis_bands(start: f32, end: f32) -> Vec<(f32, f32, f32)> {
    if end <= start {
        return vec![];
    }
    if start.floor() == end.floor() {
        return vec![(start.floor(), end.ceil(), end - start)];
    }
    let mut bands = vec![];
    if start.fract() != 0. {
        bands.push((start.floor(), start.ceil(), start.ceil() - start));
    }
    if end.floor() > start.ceil() {
        bands.push((start.ceil(), end.floor(), 1.));
    }
    if end.fract() != 0. {
        bands.push((end.floor(), end.ceil(), end - end.floor()));
    }
    bands
}
fn draw_quad(
    canvas: &skia_safe::Canvas,
    rect: Rect,
    color: u32,
    solid: Option<&RuntimeEffect>,
    byte_blend: Option<&RuntimeEffect>,
    precise: bool,
    effects_precision: bool,
) -> bool {
    let matrix = canvas.local_to_device_as_3x3();
    if !matrix.is_scale_translate() {
        if !effects_precision || solid.is_some() {
            return false;
        }
        let mut points = [
            skia_safe::Point::new(rect.left, rect.top),
            skia_safe::Point::new(rect.right, rect.top),
            skia_safe::Point::new(rect.right, rect.bottom),
            skia_safe::Point::new(rect.left, rect.bottom),
        ];
        matrix.map_points_inplace(&mut points);
        let center = points
            .iter()
            .fold((0., 0.), |p, q| (p.0 + q.x / 4., p.1 + q.y / 4.));
        let mut values = Vec::new();
        for i in 0..4 {
            let p = points[i];
            let q = points[(i + 1) % 4];
            let dx = q.x - p.x;
            let dy = q.y - p.y;
            let length = dx.hypot(dy);
            if length <= 0. {
                return false;
            }
            let mut edge = [-dy / length, dx / length, (dy * p.x - dx * p.y) / length];
            if edge[0] * center.0 + edge[1] * center.1 + edge[2] < 0. {
                for x in &mut edge {
                    *x = -*x;
                }
            }
            values.extend_from_slice(&edge);
        }
        values.extend_from_slice(&[
            ((color >> 16) & 255) as f32 / 255.,
            ((color >> 8) & 255) as f32 / 255.,
            (color & 255) as f32 / 255.,
            (color >> 24) as f32 / 255.,
        ]);
        let effect=shader_effect("uniform float3 e[4];uniform float4 color;half4 main(float2 p){float d=min(min(dot(e[0],float3(p,1)),dot(e[1],float3(p,1))),min(dot(e[2],float3(p,1)),dot(e[3],float3(p,1))));float a=clamp(d+0.5,0.0,1.0)*color.a;return half4(color.rgb*a,a);}").unwrap();
        let bytes: Vec<u8> = values.iter().flat_map(|v| v.to_ne_bytes()).collect();
        let shader = effect
            .make_shader(Data::new_copy(&bytes), &[], None)
            .unwrap();
        let mut paint = Paint::default();
        paint.set_shader(shader);
        let bounds = Rect::new(
            points.iter().map(|p| p.x).fold(f32::INFINITY, f32::min) - 1.,
            points.iter().map(|p| p.y).fold(f32::INFINITY, f32::min) - 1.,
            points.iter().map(|p| p.x).fold(f32::NEG_INFINITY, f32::max) + 1.,
            points.iter().map(|p| p.y).fold(f32::NEG_INFINITY, f32::max) + 1.,
        );
        canvas.save();
        canvas.reset_matrix();
        canvas.draw_rect(bounds, &paint);
        canvas.restore();
        return true;
    }
    let (device, _) = matrix.map_rect(rect);
    let horizontal = axis_bands(device.left, device.right);
    let vertical = axis_bands(device.top, device.bottom);
    canvas.save();
    canvas.reset_matrix();
    for &(left, right, x_coverage) in &horizontal {
        for &(top, bottom, y_coverage) in &vertical {
            // Convex-quad AA uses the closest edge, including at corners.
            let coverage = (x_coverage.min(y_coverage) * 256.).round() / 256.;
            let mut paint = Paint::default();

            if effects_precision && (precise || (coverage < 1. && color >> 24 == 255)) {
                if let Some(effect) = byte_blend {
                    let quantize: f32 = if precise { 1. } else { 0. };
                    paint.set_blender(
                        effect.make_blender(Data::new_copy(&quantize.to_ne_bytes()), None),
                    );
                }
            }
            paint.set_color(Color::new(color));
            // Keep fractional coverage through the floating-point layer. Converting
            // the mask to an alpha byte here would divide by 255 instead of 256.
            let alpha = ((color >> 24) as f32 / 255.) * coverage;
            match solid {
                Some(effect) if alpha < 1. => {
                    let c = Color::new(color);
                    let uniform = [
                        c.r() as f32 / 255.,
                        c.g() as f32 / 255.,
                        c.b() as f32 / 255.,
                        alpha,
                    ];
                    let bytes: Vec<u8> = uniform.iter().flat_map(|v| v.to_ne_bytes()).collect();
                    let Some(shader) = effect.make_shader(Data::new_copy(&bytes), &[], None) else {
                        return false;
                    };
                    paint.set_alpha_f(1.);
                    paint.set_shader(shader);
                }
                _ => {
                    paint.set_alpha_f(alpha);
                }
            }
            canvas.draw_rect(Rect::new(left, top, right, bottom), &paint);
        }
    }
    canvas.restore();
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_rect(
    s: *mut Target,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    radius: f32,
    color: u32,
) {
    let target = &mut *s;
    if radius == 0.
        && draw_quad(
            target.surface.canvas(),
            Rect::from_xywh(x, y, w, h),
            color,
            target.solid.as_ref(),
            target.byte_blend.as_ref(),
            if target.layers.last().is_some_and(|layer| {
                layer.paint.blend_mode_or(skia_safe::BlendMode::SrcOver)
                    == skia_safe::BlendMode::Src
            }) {
                true
            } else {
                false
            },
            target.effects_precision,
        )
    {
        return;
    }
    if target.context.is_some() && radius > 0. {
        msk_solid_rrect(
            target.surface.canvas() as *const skia_safe::Canvas as *const c_void,
            x,
            y,
            w,
            h,
            radius,
            color,
        );
        return;
    }
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    (*s).surface
        .canvas()
        .draw_round_rect(Rect::from_xywh(x, y, w, h), radius, radius, &paint);
}
#[no_mangle]
pub unsafe extern "C" fn msk_svg(
    s: *mut Target,
    bytes: *const u8,
    len: usize,
    w: f32,
    h: f32,
) -> bool {
    if s.is_null()
        || bytes.is_null()
        || len == 0
        || !w.is_finite()
        || !h.is_finite()
        || w <= 0.
        || h <= 0.
    {
        return false;
    }
    let Ok(mut dom) =
        skia_safe::svg::Dom::from_bytes(std::slice::from_raw_parts(bytes, len), FontMgr::default())
    else {
        return false;
    };
    dom.set_container_size((w, h));
    if !(*s).effects_precision {
        let canvas = (*s).surface.canvas();
        canvas.save();
        canvas.clip_rect(Rect::from_wh(w, h), None, true);
        let intrinsic = dom.root().intrinsic_size();
        if intrinsic.width > 0. && intrinsic.height > 0. {
            let scale = (w / intrinsic.width).min(h / intrinsic.height);
            canvas.translate((
                (w - intrinsic.width * scale) / 2.,
                (h - intrinsic.height * scale) / 2.,
            ));
            canvas.scale((scale, scale));
        }
        dom.render(canvas);
        canvas.restore();
        return true;
    }
    let parent = if let Some(context) = (*s).context.as_mut() {
        let info = ImageInfo::new(
            ((*s).surface.width(), (*s).surface.height()),
            ColorType::RGBA8888,
            AlphaType::Premul,
            None,
        );
        let Some(mut child) = gpu::surfaces::render_target(
            context,
            gpu::Budgeted::Yes,
            &info,
            Some(4),
            gpu::SurfaceOrigin::TopLeft,
            None,
            false,
            None,
        ) else {
            return false;
        };
        child.canvas().clear(Color::TRANSPARENT);
        child
            .canvas()
            .draw_image((*s).surface.image_snapshot(), (0, 0), None);
        child
            .canvas()
            .set_matrix(&(*s).surface.canvas().local_to_device());
        Some(std::mem::replace(&mut (*s).surface, child))
    } else {
        None
    };
    let canvas = (*s).surface.canvas();
    canvas.save();
    canvas.clip_rect(Rect::from_xywh(0., 0., w, h), None, true);
    let intrinsic = dom.root().intrinsic_size();
    if intrinsic.width > 0. && intrinsic.height > 0. {
        let scale = (w / intrinsic.width).min(h / intrinsic.height);
        canvas.translate((
            (w - intrinsic.width * scale) / 2.,
            (h - intrinsic.height * scale) / 2.,
        ));
        canvas.scale((scale, scale));
    }

    let proxy = msk_svg_paint_canvas(canvas as *const skia_safe::Canvas as *const c_void);
    dom.render(&*(proxy as *const skia_safe::Canvas));
    msk_svg_paint_canvas_destroy(proxy);

    canvas.restore();
    if let Some(parent) = parent {
        let image = (*s).surface.image_snapshot();
        (*s).surface = parent;
        let canvas = (*s).surface.canvas();
        canvas.save();
        canvas.reset_matrix();
        let mut paint = Paint::default();
        paint.set_blend_mode(skia_safe::BlendMode::Src);
        canvas.draw_image(image, (0, 0), Some(&paint));
        canvas.restore();
    }
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_text(
    s: *mut Target,
    text: *const c_char,
    family: *const c_char,
    size: f32,
    color: u32,
    x: f32,
    y: f32,
) -> bool {
    let Ok(text) = CStr::from_ptr(text).to_str() else {
        return false;
    };
    let Ok(family) = CStr::from_ptr(family).to_str() else {
        return false;
    };
    let Some(face) = FontMgr::new().match_family_style(family, FontStyle::normal()) else {
        return false;
    };
    let font = Font::new(face, size);
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    (*s).surface.canvas().draw_str(text, (x, y), &font, &paint);
    true
}
/// Reads unpremultiplied RGBA8888 rows (the PNG/ffmpeg `rgba` layout) into `dst`.
/// GPU targets are half-float; Skia converts to 8-bit once, here.
#[no_mangle]
pub unsafe extern "C" fn msk_read_rgba(s: *mut Target, dst: *mut u8, len: usize) -> bool {
    let target = &mut *s;
    if target.failed {
        return false;
    }
    let (width, height) = (target.surface.width(), target.surface.height());
    let row = width as usize * 4;
    if dst.is_null() || len != row * height as usize {
        return false;
    }
    if let Some(context) = target.context.as_mut() {
        context.flush_and_submit();
    }
    let info = ImageInfo::new(
        (width, height),
        ColorType::RGBA8888,
        AlphaType::Unpremul,
        None,
    );
    target
        .surface
        .read_pixels(&info, std::slice::from_raw_parts_mut(dst, len), row, (0, 0))
}
/// Resolve the F16 render target into a caller-owned IOSurface-backed BGRA8 texture
/// on the GPU. No pixel mapping/readback occurs. The caller retains the texture until
/// this returns; GPU completion is synchronized before handing it to another framework.
#[no_mangle]
pub unsafe extern "C" fn msk_copy_to_metal_texture(s: *mut Target, texture: *const c_void) -> bool {
    if s.is_null() || texture.is_null() {
        return false;
    }
    let target = &mut *s;
    let Some(context) = target.context.as_mut() else {
        return false;
    };
    let info = gpu::mtl::TextureInfo::new(texture as *mut c_void);
    let backend = gpu::backend_textures::make_mtl(
        (target.surface.width(), target.surface.height()),
        gpu::Mipmapped::No,
        &info,
        "IOSurface output",
    );
    let Some(mut output) = gpu::surfaces::wrap_backend_texture(
        context,
        &backend,
        gpu::SurfaceOrigin::TopLeft,
        None,
        ColorType::BGRA8888,
        None,
        None,
    ) else {
        return false;
    };
    let image = target.surface.image_snapshot();
    if target.resolve.is_none() {
        target.resolve = RuntimeEffect::make_for_shader(
            "uniform shader frame; half4 main(float2 p) { half4 c = frame.eval(p); return half4(c.a > 0 ? c.rgb / c.a : half3(0), 1); }", None).ok();
    }
    let Some(effect) = target.resolve.as_ref() else {
        return false;
    };
    let Some(source) = image.to_shader(None, skia_safe::SamplingOptions::default(), None) else {
        return false;
    };
    let Some(shader) = effect.make_shader(Data::new_empty(), &[source.into()], None) else {
        return false;
    };
    let mut paint = Paint::default();
    // Match raw RGBA video: unpremultiply RGB before dropping alpha (H.264 is opaque).
    paint.set_blend_mode(skia_safe::BlendMode::Src);
    paint.set_shader(shader);
    output.canvas().draw_paint(&paint);
    context.flush_submit_and_sync_cpu();
    !context.abandoned()
}
#[no_mangle]
pub unsafe extern "C" fn msk_png(s: *mut Target, path: *const c_char) -> bool {
    let Ok(path) = CStr::from_ptr(path).to_str() else {
        return false;
    };
    let target = &mut *s;
    if target.failed {
        return false;
    }
    let (width, height) = (target.surface.width(), target.surface.height());
    let image = if target.context.is_some() {
        // Encode the same 8-bit pixels the video path uses.
        let mut pixels = vec![0u8; (width * height * 4) as usize];
        if !msk_read_rgba(s, pixels.as_mut_ptr(), pixels.len()) {
            return false;
        }
        let info = ImageInfo::new(
            (width, height),
            ColorType::RGBA8888,
            AlphaType::Unpremul,
            None,
        );
        let Some(image) =
            images::raster_from_data(&info, Data::new_copy(&pixels), width as usize * 4)
        else {
            return false;
        };
        image
    } else {
        target.surface.image_snapshot()
    };
    let Some(data) = image.encode(None, EncodedImageFormat::PNG, None) else {
        return false;
    };
    std::fs::write(path, data.as_bytes()).is_ok()
}

/// Draw tightly packed premultiplied RGBA pixels. fit: 0 contain, 1 cover, 2 fill.
#[no_mangle]
pub unsafe extern "C" fn msk_image_rgba(
    s: *mut Target,
    bytes: *const u8,
    len: usize,
    iw: i32,
    ih: i32,
    w: f32,
    h: f32,
    fit: i32,
) -> bool {
    if s.is_null()
        || bytes.is_null()
        || iw <= 0
        || ih <= 0
        || !w.is_finite()
        || !h.is_finite()
        || w <= 0.
        || h <= 0.
        || len != iw as usize * ih as usize * 4
    {
        return false;
    }
    let info = ImageInfo::new((iw, ih), ColorType::RGBA8888, AlphaType::Premul, None);
    let data = skia_safe::Data::new_copy(std::slice::from_raw_parts(bytes, len));
    let Some(image) = skia_safe::images::raster_from_data(&info, data, iw as usize * 4) else {
        return false;
    };
    let (sw, sh) = (iw as f32, ih as f32);
    let scale = if fit == 1 {
        (w / sw).max(h / sh)
    } else {
        (w / sw).min(h / sh)
    };
    let (dw, dh) = if fit == 2 {
        (w, h)
    } else {
        (sw * scale, sh * scale)
    };
    let canvas = (*s).surface.canvas();
    canvas.save();
    canvas.clip_rect(Rect::from_xywh(0., 0., w, h), None, true);
    canvas.draw_image_rect(
        &image,
        None,
        Rect::from_xywh((w - dw) / 2., (h - dh) / 2., dw, dh),
        &Paint::default(),
    );
    canvas.restore();
    true
}

// Paragraph and font handles are worker-confined. Paragraphs retain their collection.
use skia_safe::textlayout::{
    FontCollection, Paragraph, ParagraphBuilder, ParagraphStyle, TextAlign, TextStyle,
    TypefaceFontProvider,
};
pub struct Fonts {
    collection: FontCollection,
    provider: TypefaceFontProvider,
}
#[no_mangle]
pub extern "C" fn msk_fonts_create() -> *mut Fonts {
    let mut collection = FontCollection::new();
    collection.set_default_font_manager(FontMgr::default(), Some("Arial"));
    Box::into_raw(Box::new(Fonts {
        collection,
        provider: TypefaceFontProvider::new(),
    }))
}
#[no_mangle]
pub unsafe extern "C" fn msk_fonts_destroy(fonts: *mut Fonts) {
    if !fonts.is_null() {
        drop(Box::from_raw(fonts));
    }
}
#[no_mangle]
pub unsafe extern "C" fn msk_fonts_register(
    fonts: *mut Fonts,
    bytes: *const u8,
    len: usize,
    family: *const c_char,
) -> bool {
    if fonts.is_null() || bytes.is_null() || family.is_null() {
        return false;
    }
    let Some(face) = FontMgr::default().new_from_data(std::slice::from_raw_parts(bytes, len), None)
    else {
        return false;
    };
    let Ok(family) = CStr::from_ptr(family).to_str() else {
        return false;
    };
    let fonts = &mut *fonts;
    fonts.provider.register_typeface(face, Some(family));
    fonts
        .collection
        .set_asset_font_manager(Some(fonts.provider.clone().into()));
    fonts.collection.clear_caches();
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_builder(
    fonts: *mut Fonts,
    align: i32,
) -> *mut ParagraphBuilder {
    if fonts.is_null() {
        return std::ptr::null_mut();
    }
    let mut style = ParagraphStyle::new();
    style.set_text_align(match align {
        1 => TextAlign::Center,
        2 => TextAlign::Right,
        3 => TextAlign::Justify,
        _ => TextAlign::Left,
    });
    Box::into_raw(Box::new(ParagraphBuilder::new(
        &style,
        (*fonts).collection.clone(),
    )))
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_add(
    builder: *mut ParagraphBuilder,
    text: *const c_char,
    families: *const c_char,
    size: f32,
    weight: i32,
    italic: bool,
    color: u32,
    height: f32,
    spacing: f32,
) {
    let mut style = TextStyle::new();
    let families = CStr::from_ptr(families).to_string_lossy();
    let names: Vec<&str> = families
        .split(',')
        .map(|s| s.trim().trim_matches(|c| c == '\'' || c == '"'))
        .collect();
    style
        .set_font_families(&names)
        .set_font_size(size)
        .set_color(Color::from(color))
        .set_letter_spacing(spacing);
    style.set_font_style(FontStyle::new(
        skia_safe::font_style::Weight::from(weight),
        skia_safe::font_style::Width::NORMAL,
        if italic {
            skia_safe::font_style::Slant::Italic
        } else {
            skia_safe::font_style::Slant::Upright
        },
    ));
    if height > 0. {
        style
            .set_height(height)
            .set_height_override(true)
            .set_half_leading(true);
    }
    (*builder).push_style(&style);
    (*builder).add_text(CStr::from_ptr(text).to_string_lossy());
    (*builder).pop();
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_build(builder: *mut ParagraphBuilder) -> *mut Paragraph {
    let mut builder = Box::from_raw(builder);
    Box::into_raw(Box::new(builder.build()))
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_destroy(p: *mut Paragraph) {
    if !p.is_null() {
        drop(Box::from_raw(p));
    }
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_layout(p: *mut Paragraph, width: f32) {
    (*p).layout(width.max(0.));
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_height(p: *mut Paragraph) -> f32 {
    (*p).height()
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_width(p: *mut Paragraph) -> f32 {
    (*p).max_intrinsic_width()
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_baseline(p: *mut Paragraph) -> f32 {
    (*p).alphabetic_baseline()
}
#[no_mangle]
pub unsafe extern "C" fn msk_paragraph_paint(s: *mut Target, p: *mut Paragraph, x: f32, y: f32) {
    (*p).paint((*s).surface.canvas(), (x, y));
}

mod effects;
