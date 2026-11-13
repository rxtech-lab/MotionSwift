use skia_safe::{color_filters, gpu, images, surfaces, ColorMatrix, Data, RuntimeEffect, AlphaType, Color, ColorType, EncodedImageFormat, Font, FontMgr, FontStyle, ImageInfo, Paint, Rect, Surface, canvas::{SaveLayerRec, SaveLayerFlags}};
use std::ffi::{c_char, c_void, CStr};

/// One drawing target. A handle is owned by Swift's Canvas and confined to one render
/// worker thread; GPU handles also own their Ganesh context, which is not thread-safe.
/// Field order matters: the surface must be dropped before the context that backs it.
pub struct Target { surface: Surface, context: Option<gpu::DirectContext>, solid: Option<RuntimeEffect>, resolve: Option<RuntimeEffect> }

// Ganesh folds constant paint colours (and colour filters on them) into premultiplied
// byte vertex colours, rounding colour*coverage (81.5 -> 82). A runtime shader with a
// float uniform cannot be folded, so GPU quads keep the raster pipeline's precision.
const SOLID_SKSL: &str = "uniform float4 color; half4 main(float2 p) { return half4(color.rgb * color.a, color.a); }";

fn valid(width: i32, height: i32) -> bool { width > 0 && height > 0 && width <= 16384 && height <= 16384 }
fn boxed(mut surface: Surface, context: Option<gpu::DirectContext>) -> *mut Target {
    surface.canvas().clear(Color::TRANSPARENT);
    let solid = if context.is_some() {
        match RuntimeEffect::make_for_shader(SOLID_SKSL, None) { Ok(effect) => Some(effect), Err(_) => return std::ptr::null_mut() }
    } else { None };
    Box::into_raw(Box::new(Target { surface, context, solid, resolve: None }))
}

#[no_mangle]
pub extern "C" fn msk_create(width: i32, height: i32) -> *mut Target {
    if !valid(width, height) { return std::ptr::null_mut(); }
    surfaces::raster_n32_premul((width, height)).map(|s| boxed(s, None)).unwrap_or(std::ptr::null_mut())
}
/// Creates a Metal-backed Ganesh surface. `device` and `queue` are borrowed
/// `id<MTLDevice>` / `id<MTLCommandQueue>` pointers; Skia retains its own references.
#[no_mangle]
pub unsafe extern "C" fn msk_create_gpu(width: i32, height: i32, device: *const c_void, queue: *const c_void) -> *mut Target {
    if !valid(width, height) || device.is_null() || queue.is_null() { return std::ptr::null_mut(); }
    let backend = gpu::mtl::BackendContext::new(device, queue);
    let Some(mut context) = gpu::direct_contexts::make_metal(&backend, None) else { return std::ptr::null_mut(); };
    // Blend in half-float and round to 8 bits once, on readback, like the raster backend's
    // F16 layers. This also makes opaque layers unnecessary on the GPU (see msk_save).
    let info = ImageInfo::new((width, height), ColorType::RGBAF16, AlphaType::Premul, None);
    gpu::surfaces::render_target(&mut context, gpu::Budgeted::Yes, &info, None, gpu::SurfaceOrigin::TopLeft, None, false, None)
        .map(|s| boxed(s, Some(context))).unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn msk_clear(s: *mut Target) { (*s).surface.canvas().clear(Color::TRANSPARENT); }
#[no_mangle]
pub unsafe extern "C" fn msk_destroy(s: *mut Target) { if !s.is_null() { drop(Box::from_raw(s)); } }
/// Multiplies alpha in a float colour filter (a fragment-shader uniform on Ganesh).
fn alpha_filter(alpha: f32) -> skia_safe::ColorFilter {
    let mut matrix = ColorMatrix::default();
    matrix.set_scale(1., 1., 1., Some(alpha));
    color_filters::matrix(&matrix, None)
}
#[no_mangle]
pub unsafe extern "C" fn msk_save(s: *mut Target, alpha: f32) {
    let mut paint = Paint::default();
    let gpu = (*s).context.is_some();
    if gpu && alpha >= 1. {
        // The Metal target is already half-float, so an opaque layer adds a texture pass
        // without changing any pixel. The raster backend keeps its F16 layers for precision.
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
    let layer = SaveLayerRec::default().paint(&paint).flags(SaveLayerFlags::F16_COLOR_TYPE);
    (*s).surface.canvas().save_layer(&layer);
}
#[no_mangle]
pub unsafe extern "C" fn msk_restore(s: *mut Target) { (*s).surface.canvas().restore(); }
#[no_mangle]
pub unsafe extern "C" fn msk_translate(s: *mut Target, x: f32, y: f32) { (*s).surface.canvas().translate((x,y)); }
#[no_mangle]
pub unsafe extern "C" fn msk_rotate(s: *mut Target, degrees: f32) { (*s).surface.canvas().rotate(degrees, None); }
#[no_mangle]
pub unsafe extern "C" fn msk_scale(s: *mut Target, x: f32, y: f32) { (*s).surface.canvas().scale((x,y)); }
#[no_mangle]
pub unsafe extern "C" fn msk_clip(s: *mut Target, w: f32, h: f32) {
    (*s).surface.canvas().clip_rect(Rect::from_xywh(0.,0.,w,h), None, true);
}
// Use device-space coverage for axis-aligned quads, retaining its 256-step
// precision through floating-point layers. Converting coverage to an alpha byte
// prematurely shifts scaled edges by one channel value against GPU references.
fn axis_bands(start: f32, end: f32) -> Vec<(f32, f32, f32)> {
    if end <= start { return vec![]; }
    if start.floor() == end.floor() { return vec![(start.floor(), end.ceil(), end-start)]; }
    let mut bands = vec![];
    if start.fract() != 0. { bands.push((start.floor(), start.ceil(), start.ceil()-start)); }
    if end.floor() > start.ceil() { bands.push((start.ceil(), end.floor(), 1.)); }
    if end.fract() != 0. { bands.push((end.floor(), end.ceil(), end-end.floor())); }
    bands
}
fn draw_quad(canvas: &skia_safe::Canvas, rect: Rect, color: u32, solid: Option<&RuntimeEffect>) -> bool {
    let matrix = canvas.local_to_device_as_3x3();
    if !matrix.is_scale_translate() { return false; }
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
            paint.set_color(Color::new(color));
            // Keep fractional coverage through the floating-point layer. Converting
            // the mask to an alpha byte here would divide by 255 instead of 256.
            let alpha = ((color >> 24) as f32 / 255.) * coverage;
            match solid {
                Some(effect) if alpha < 1. => {
                    let c = Color::new(color);
                    let uniform = [c.r() as f32 / 255., c.g() as f32 / 255., c.b() as f32 / 255., alpha];
                    let bytes: Vec<u8> = uniform.iter().flat_map(|v| v.to_ne_bytes()).collect();
                    let Some(shader) = effect.make_shader(Data::new_copy(&bytes), &[], None) else { return false; };
                    paint.set_alpha_f(1.);
                    paint.set_shader(shader);
                }
                _ => { paint.set_alpha_f(alpha); }
            }
            canvas.draw_rect(Rect::new(left, top, right, bottom), &paint);
        }
    }
    canvas.restore();
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_rect(s: *mut Target, x: f32, y: f32, w: f32, h: f32, radius: f32, color: u32) {
    let target = &mut *s;
    if radius == 0. && draw_quad(target.surface.canvas(), Rect::from_xywh(x,y,w,h), color, target.solid.as_ref()) { return; }
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    (*s).surface.canvas().draw_round_rect(Rect::from_xywh(x,y,w,h), radius, radius, &paint);
}
#[no_mangle]
pub unsafe extern "C" fn msk_svg(s: *mut Target, bytes: *const u8, len: usize, w: f32, h: f32) -> bool {
    if s.is_null() || bytes.is_null() || len == 0 || !w.is_finite() || !h.is_finite() || w <= 0. || h <= 0. { return false; }
    let Ok(mut dom) = skia_safe::svg::Dom::from_bytes(std::slice::from_raw_parts(bytes, len), FontMgr::default()) else { return false; };
    dom.set_container_size((w, h));
    let canvas = (*s).surface.canvas();
    canvas.save();
    canvas.clip_rect(Rect::from_xywh(0., 0., w, h), None, true);
    let intrinsic = dom.root().intrinsic_size();
    if intrinsic.width > 0. && intrinsic.height > 0. {
        let scale = (w / intrinsic.width).min(h / intrinsic.height);
        canvas.translate(((w - intrinsic.width * scale) / 2., (h - intrinsic.height * scale) / 2.));
        canvas.scale((scale, scale));
    }
    dom.render(canvas);
    canvas.restore();
    true
}
#[no_mangle]
pub unsafe extern "C" fn msk_text(s: *mut Target, text: *const c_char, family: *const c_char, size: f32, color: u32, x: f32, y: f32) -> bool {
    let Ok(text) = CStr::from_ptr(text).to_str() else { return false; };
    let Ok(family) = CStr::from_ptr(family).to_str() else { return false; };
    let Some(face) = FontMgr::new().match_family_style(family, FontStyle::normal()) else { return false; };
    let font = Font::new(face, size);
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    (*s).surface.canvas().draw_str(text, (x,y), &font, &paint);
    true
}
/// Reads unpremultiplied RGBA8888 rows (the PNG/ffmpeg `rgba` layout) into `dst`.
/// GPU targets are half-float; Skia converts to 8-bit once, here.
#[no_mangle]
pub unsafe extern "C" fn msk_read_rgba(s: *mut Target, dst: *mut u8, len: usize) -> bool {
    let target = &mut *s;
    let (width, height) = (target.surface.width(), target.surface.height());
    let row = width as usize * 4;
    if dst.is_null() || len != row * height as usize { return false; }
    if let Some(context) = target.context.as_mut() { context.flush_and_submit(); }
    let info = ImageInfo::new((width, height), ColorType::RGBA8888, AlphaType::Unpremul, None);
    target.surface.read_pixels(&info, std::slice::from_raw_parts_mut(dst, len), row, (0, 0))
}
/// Resolve the F16 render target into a caller-owned IOSurface-backed BGRA8 texture
/// on the GPU. No pixel mapping/readback occurs. The caller retains the texture until
/// this returns; GPU completion is synchronized before handing it to another framework.
#[no_mangle]
pub unsafe extern "C" fn msk_copy_to_metal_texture(s: *mut Target, texture: *const c_void) -> bool {
    if s.is_null() || texture.is_null() { return false; }
    let target = &mut *s;
    let Some(context) = target.context.as_mut() else { return false; };
    let info = gpu::mtl::TextureInfo::new(texture as *mut c_void);
    let backend = gpu::backend_textures::make_mtl(
        (target.surface.width(), target.surface.height()), gpu::Mipmapped::No, &info, "IOSurface output");
    let Some(mut output) = gpu::surfaces::wrap_backend_texture(
        context, &backend, gpu::SurfaceOrigin::TopLeft, None, ColorType::BGRA8888, None, None
    ) else { return false; };
    let image = target.surface.image_snapshot();
    if target.resolve.is_none() {
        target.resolve = RuntimeEffect::make_for_shader(
            "uniform shader frame; half4 main(float2 p) { half4 c = frame.eval(p); return half4(c.a > 0 ? c.rgb / c.a : half3(0), 1); }", None).ok();
    }
    let Some(effect) = target.resolve.as_ref() else { return false; };
    let Some(source) = image.to_shader(None, skia_safe::SamplingOptions::default(), None) else { return false; };
    let Some(shader) = effect.make_shader(Data::new_empty(), &[source.into()], None) else { return false; };
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
    let Ok(path) = CStr::from_ptr(path).to_str() else { return false; };
    let target = &mut *s;
    let (width, height) = (target.surface.width(), target.surface.height());
    let image = if target.context.is_some() {
        // Encode the same 8-bit pixels the video path uses.
        let mut pixels = vec![0u8; (width * height * 4) as usize];
        if !msk_read_rgba(s, pixels.as_mut_ptr(), pixels.len()) { return false; }
        let info = ImageInfo::new((width, height), ColorType::RGBA8888, AlphaType::Unpremul, None);
        let Some(image) = images::raster_from_data(&info, Data::new_copy(&pixels), width as usize * 4) else { return false; };
        image
    } else {
        target.surface.image_snapshot()
    };
    let Some(data) = image.encode(None, EncodedImageFormat::PNG, None) else { return false; };
    std::fs::write(path, data.as_bytes()).is_ok()
}

/// Draw tightly packed premultiplied RGBA pixels. fit: 0 contain, 1 cover, 2 fill.
#[no_mangle]
pub unsafe extern "C" fn msk_image_rgba(s: *mut Target, bytes: *const u8, len: usize, iw: i32, ih: i32, w: f32, h: f32, fit: i32) -> bool {
    if s.is_null() || bytes.is_null() || iw <= 0 || ih <= 0 || !w.is_finite() || !h.is_finite() || w <= 0. || h <= 0. || len != iw as usize * ih as usize * 4 { return false; }
    let info = ImageInfo::new((iw, ih), ColorType::RGBA8888, AlphaType::Premul, None);
    let data = skia_safe::Data::new_copy(std::slice::from_raw_parts(bytes, len));
    let Some(image) = skia_safe::images::raster_from_data(&info, data, iw as usize * 4) else { return false; };
    let (sw, sh) = (iw as f32, ih as f32);
    let scale = if fit == 1 { (w / sw).max(h / sh) } else { (w / sw).min(h / sh) };
    let (dw, dh) = if fit == 2 { (w, h) } else { (sw * scale, sh * scale) };
    let canvas = (*s).surface.canvas();
    canvas.save();
    canvas.clip_rect(Rect::from_xywh(0., 0., w, h), None, true);
    canvas.draw_image_rect(&image, None, Rect::from_xywh((w-dw)/2., (h-dh)/2., dw, dh), &Paint::default());
    canvas.restore();
    true
}
