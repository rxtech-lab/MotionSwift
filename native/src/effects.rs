//! Compositing primitives shared by raster and Metal. Parsing/contract validation is in Swift.
use super::*;
use skia_safe::{image_filters, BlendMode, ClipOp, Matrix, Path, RRect, TileMode};

fn blend(value: i32) -> BlendMode {
    match value {
        1 => BlendMode::Multiply,
        2 => BlendMode::Screen,
        3 => BlendMode::Overlay,
        4 => BlendMode::Darken,
        5 => BlendMode::Lighten,
        6 => BlendMode::ColorDodge,
        7 => BlendMode::ColorBurn,
        8 => BlendMode::HardLight,
        9 => BlendMode::SoftLight,
        10 => BlendMode::Difference,
        11 => BlendMode::Exclusion,
        12 => BlendMode::Hue,
        13 => BlendMode::Saturation,
        14 => BlendMode::Color,
        15 => BlendMode::Luminosity,
        _ => BlendMode::SrcOver,
    }
}

fn gaussian(
    sigma: f32,
    input: Option<skia_safe::ImageFilter>,
    tile: TileMode,
) -> Option<skia_safe::ImageFilter> {
    gaussian_bounds(sigma, input, tile, None)
}
fn gaussian_bounds(
    sigma: f32,
    input: Option<skia_safe::ImageFilter>,
    tile: TileMode,
    bounds: Option<Rect>,
) -> Option<skia_safe::ImageFilter> {
    if sigma < 1.0e-6 {
        return input;
    }
    // Large radii use Skia's bounded, downsampled implementation instead of expanding
    // an unbounded runtime shader. Both paths stay on the selected rendering backend.
    if !sigma.is_finite() || sigma < 0. {
        return input;
    }
    if sigma > 16. {
        return image_filters::blur((sigma, sigma), tile, input, None);
    }
    let radius = (sigma * 3.).ceil() as i32;
    let mut kernel: Vec<f32> = (-radius..=radius)
        .map(|x| (-(x * x) as f32 / (2. * sigma * sigma)).exp())
        .collect();
    let sum: f32 = kernel.iter().sum();
    for value in &mut kernel {
        *value /= sum;
    }

    let half = |x: f32| {
        if x == 0. {
            return 0.;
        }
        let step = 2_f32.powi((x.abs().log2().floor() as i32 - 10).max(-24));
        (x / step).round_ties_even() * step
    };
    let original = kernel.clone();
    kernel.fill(0.);
    if radius % 2 == 0 {
        kernel[radius as usize] = half(original[radius as usize]);
    }
    for i in ((1 - radius % 2)..radius).step_by(2) {
        let wi = original[(radius + i) as usize] * if i == 0 { 0.5 } else { 1. };
        let wj = original[(radius + i + 1) as usize];
        let weight = half(wi + wj);
        let fraction = wj / (wi + wj);
        for sign in [-1, 1] {
            kernel[(radius + sign * i) as usize] += weight * (1. - fraction);
            kernel[(radius + sign * (i + 1)) as usize] += weight * fraction;
        }
    }

    let original = input.clone();
    let mut result = input;
    for horizontal in [true, false] {
        let mut identity = vec![0.; kernel.len()];
        identity[radius as usize] = 1.;
        let size = if horizontal {
            (2 * radius + 1, 1)
        } else {
            (1, 2 * radius + 1)
        };
        let offset = if horizontal { (radius, 0) } else { (0, radius) };
        result = image_filters::matrix_convolution(
            size, &identity, 1., 0., offset, tile, true, result, None,
        );
        let taps: String = kernel
            .iter()
            .enumerate()
            .map(|(index, weight)| {
                let delta = index as i32 - radius;
                let (x, y) = if horizontal { (delta, 0) } else { (0, delta) };
                let point = if let Some(b) = bounds {
                    format!(
                        "clamp(p+float2({x},{y}),float2({},{}),float2({},{}))",
                        b.left + 0.5,
                        b.top + 0.5,
                        b.right - 0.5,
                        b.bottom - 0.5
                    )
                } else {
                    format!("p+float2({x},{y})")
                };
                format!(
                    "sum+=(floor(float4(inputImage.eval({point}))*255.0+0.5)/255.0)*{weight:.12};"
                )
            })
            .collect();

        let output = "return half4(floor(clamp(sum,0.0,1.0)*255.0+0.5)/255.0);";
        let source=format!("uniform shader inputImage; half4 main(float2 p) {{ float4 sum=float4(0); {taps} {output} }}");
        let Ok(effect) = shader_effect(&source) else {
            return image_filters::blur((sigma, sigma), tile, original, None);
        };
        let builder = skia_safe::runtime_effect::RuntimeShaderBuilder::new(effect);
        result = image_filters::runtime_shader(&builder, "inputImage", result);
    }
    return result;
}

fn matrix_filter(matrices: &[f32]) -> skia_safe::ColorFilter {
    let count = matrices.len() / 20;
    let stages: String = (0..count)
        .map(|stage| {
            let channels: Vec<String> = (0..4)
                .map(|row| {
                    let j = stage * 20 + row * 5;
                    format!(
                        "dot(c,float4(m[{j}],m[{}],m[{}],m[{}]))+m[{}]",
                        j + 1,
                        j + 2,
                        j + 3,
                        j + 4
                    )
                })
                .collect();
            format!("c=clamp(float4({}),0.0,1.0);", channels.join(","))
        })
        .collect();
    let source = format!("uniform float m[{}]; half4 main(half4 inputColor) {{ float4 c=floor(float4(inputColor)*255.0+0.5)/255.0; if(c.a>0.0) c.rgb/=c.a; {stages} c.rgb*=c.a; return half4(floor(c*255.0+0.5)/255.0); }}",matrices.len());
    let effect = color_effect(&source).unwrap();
    let bytes: Vec<u8> = matrices.iter().flat_map(|v| v.to_ne_bytes()).collect();
    effect
        .make_color_filter(Data::new_copy(&bytes), None)
        .unwrap()
}

/// Filter entries are 21 floats: kind (0 blur, 1 color matrix), then 20 matrix values.
#[no_mangle]
pub unsafe extern "C" fn msk_effect_layer(
    s: *mut Target,
    alpha: f32,
    mode: i32,
    entries: *const f32,
    count: usize,
    width: f32,
    height: f32,
) {
    let mut filter = None;
    let mut matrices = Vec::new();
    for index in 0..count {
        let v = std::slice::from_raw_parts(entries.add(index * 21), 21);

        if v[0] == 1. {
            matrices.extend_from_slice(&v[1..]);
            if index + 1 == count {
                filter = image_filters::color_filter(matrix_filter(&matrices), filter, None);
            }
            continue;
        }
        if !matrices.is_empty() {
            filter = image_filters::color_filter(matrix_filter(&matrices), filter, None);
            matrices.clear();
        }

        filter = if v[0] == 0. {
            gaussian(v[1], filter, TileMode::Decal)
        } else if v[0] == 2. {
            image_filters::drop_shadow(
                (v[1], v[2]),
                (v[3], v[3]),
                skia_safe::Color4f::new(v[4], v[5], v[6], v[7]),
                None,
                filter,
                None,
            )
        } else {
            let matrix: &[f32; 20] = v[1..].try_into().unwrap();
            let color_filter = matrix_filter(matrix);
            image_filters::color_filter(color_filter, filter, None)
        };
    }
    let mut paint = Paint::default();
    paint
        .set_blend_mode(blend(mode))
        .set_color_filter(alpha_filter(alpha))
        .set_image_filter(filter);

    let (bounds, _) = (*s)
        .surface
        .canvas()
        .local_to_device_as_3x3()
        .map_rect(Rect::from_wh(width, height));
    let origin = (bounds.left.floor() - 1., bounds.top.floor() - 1.);
    (*s).effect_surface(paint, ColorType::RGBA8888, alpha, true);
    (*s).dither_origin = origin;
    return;
}

#[no_mangle]
pub unsafe extern "C" fn msk_backdrop(s: *mut Target, w: f32, h: f32, radius: f32, sigma: f32) {
    if sigma >= 1.0e-6 && sigma.is_finite() {
        (*s).backdrop_group = Some((w, h, radius, sigma));
    }
}

pub(super) fn apply_backdrop(s: &mut Target, w: f32, h: f32, radius: f32, sigma: f32, alpha: f32) {
    let backdrop = image_filters::crop(Rect::from_wh(w, h), TileMode::Clamp, None);
    let Some(filter) = gaussian_bounds(sigma, backdrop, TileMode::Clamp, Some(Rect::from_wh(w, h)))
    else {
        return;
    };
    let rrect = RRect::new_rect_xy(Rect::from_wh(w, h), radius, radius);
    if alpha >= 1. {
        let canvas = s.surface.canvas();
        canvas.save();
        canvas.clip_rrect(rrect, None, true);
        canvas.save_layer(&SaveLayerRec::default().backdrop(&filter));
        canvas.restore();
        canvas.restore();
        let background = s.surface.image_snapshot();
        let mut paint = Paint::default();
        paint.set_blend_mode(BlendMode::Src);
        s.effect_surface(paint, ColorType::RGBA8888, 1., false);
        let child = s.surface.canvas();
        child.save();
        child.reset_matrix();
        child.draw_image(background, (0, 0), None);
        child.restore();
        return;
    }
    if alpha <= 0. {
        let mut paint = Paint::default();
        paint.set_alpha_f(0.);
        s.effect_surface(paint, ColorType::RGBA8888, 0., false);
        return;
    }
    let unblurred = s.surface.image_snapshot();
    let matrix = s.surface.canvas().local_to_device();
    let mut paint = Paint::default();
    if s.context.is_some() {
        paint.set_color_filter(alpha_filter(alpha));
    } else {
        paint.set_alpha_f(alpha);
    }
    s.effect_surface(paint, ColorType::RGBA8888, alpha, false);
    let info = ImageInfo::new(
        (s.surface.width(), s.surface.height()),
        ColorType::RGBA8888,
        AlphaType::Premul,
        None,
    );
    let Some(mut temp) = s.surface.new_surface(&info) else {
        s.failed = true;
        return;
    };
    temp.canvas().clear(Color::TRANSPARENT);
    temp.canvas().draw_image(&unblurred, (0, 0), None);
    temp.canvas().set_matrix(&matrix);
    temp.canvas().save();
    temp.canvas().clip_rrect(rrect, None, true);
    temp.canvas()
        .save_layer(&SaveLayerRec::default().backdrop(&filter));
    temp.canvas().restore();
    temp.canvas().restore();
    let blurred = temp.image_snapshot();
    let child = s.surface.canvas();
    child.save();
    child.clip_rrect(rrect, None, true);
    child.reset_matrix();
    child.draw_image(&blurred, (0, 0), None);
    child.restore();
}

#[no_mangle]
pub unsafe extern "C" fn msk_concat(s: *mut Target, values: *const f32) {
    let v = std::slice::from_raw_parts(values, 9);
    (*s).surface.canvas().concat(&Matrix::new_all(
        v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8],
    ));
}

#[no_mangle]
pub unsafe extern "C" fn msk_clip_path(s: *mut Target, svg: *const c_char) -> bool {
    if !(*s).effects_precision {
        let Ok(text) = CStr::from_ptr(svg).to_str() else {
            return false;
        };
        let Some(path) = Path::from_svg(text) else {
            return false;
        };
        (*s).surface.canvas().clip_path(&path, None, true);
        return true;
    }
    if let Ok(text) = CStr::from_ptr(svg).to_str() {
        if let Some(path) = Path::from_svg(text) {
            if let Some((rect, _, _)) = path.is_rect() {
                (*s).surface.canvas().clip_rect(rect, None, true);
                return true;
            }
        }
    }

    let target = &mut *s;
    let (w, h) = (target.surface.width(), target.surface.height());
    let mut bytes = vec![0u8; w as usize * h as usize * 4];
    let matrix = target.surface.canvas().local_to_device_as_3x3();
    let values = [
        matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5], matrix[6], matrix[7],
        matrix[8],
    ];
    if !msk_path_coverage(svg, values.as_ptr(), bytes.as_mut_ptr(), w, h) {
        return false;
    }
    let info = ImageInfo::new((w, h), ColorType::RGBA8888, AlphaType::Premul, None);
    let image = images::raster_from_data(&info, Data::new_copy(&bytes), w as usize * 4).unwrap();
    target.pending_clip = image.to_shader(None, skia_safe::SamplingOptions::default(), None);
    return true;
}

/// mode 0 background, 1 alpha mask (DstIn on an isolated layer).
#[no_mangle]
pub unsafe extern "C" fn msk_gradient(
    s: *mut Target,
    w: f32,
    h: f32,
    radius: f32,
    kind: i32,
    geometry: *const f32,
    colors: *const u32,
    stops: *const f32,
    count: usize,
    mode: i32,
) -> bool {
    if count < 2 || count > 256 {
        return false;
    }
    let colors: Vec<Color> = std::slice::from_raw_parts(colors, count)
        .iter()
        .map(|c| Color::new(*c))
        .collect();
    // Rasterize the CSS gradient in full float precision before the 8-bit
    // ordered dither used by Chrome. A half-valued child shader loses that precision.
    let matrix = (*s).surface.canvas().local_to_device_as_3x3();
    let dither_matrix = Matrix::concat(
        &Matrix::translate((-(*s).dither_origin.0, -(*s).dither_origin.1)),
        &matrix,
    );
    let coordinate = if kind == 0 {
        "float2 delta=geometry.zw-geometry.xy; float t=dot(p-geometry.xy,delta)/dot(delta,delta)+0.00001;"
    } else {
        "float t=length((p-geometry.xy)/geometry.zw);"
    };
    let mask_quantize = if mode == 1 {
        "c.a=floor(c.a*255.0+0.5)/255.0;"
    } else {
        ""
    };
    let source = format!("uniform float3x3 device; uniform float4 geometry; uniform float4 colors[{count}]; uniform float stops[{count}]; half4 main(float2 p) {{ {coordinate} float4 c=colors[0]; for(int i=1;i<{count};++i) {{ float u=clamp((t-stops[i-1])/max(0.0000001,stops[i]-stops[i-1]),0.0,1.0); c=mix(c,colors[i],u); }} float3 q=device*float3(p,1); float2 xy=floor(q.xy/q.z); float x=xy.x; float y=xy.y; float m=mod(y,2.0)*32.0+mod(x,2.0)*16.0+mod(floor(y/2.0),2.0)*8.0+mod(floor(x/2.0),2.0)*4.0+mod(floor(y/4.0),2.0)*2.0+mod(floor(x/4.0),2.0); float d=(floor((m/64.0-63.0/128.0+0.5)*255.0+0.5)/255.0-0.5)/255.0; c.rgb=floor(clamp(c.rgb+d,0.0,c.a)*255.0+0.5)/255.0; {mask_quantize} return half4(c); }}");
    let Ok(effect) = shader_effect(&source) else {
        return false;
    };
    let m = dither_matrix;
    let mut values = vec![
        m.scale_x(),
        m.skew_y(),
        m.persp_x(),
        m.skew_x(),
        m.scale_y(),
        m.persp_y(),
        m.translate_x(),
        m.translate_y(),
        m[8],
    ];
    values.extend_from_slice(std::slice::from_raw_parts(geometry, 4));
    for color in &colors {
        let alpha = color.a() as f32 / 255.;
        values.extend_from_slice(&[
            color.r() as f32 / 255. * alpha,
            color.g() as f32 / 255. * alpha,
            color.b() as f32 / 255. * alpha,
            alpha,
        ]);
    }
    values.extend_from_slice(std::slice::from_raw_parts(stops, count));
    let bytes: Vec<u8> = values.iter().flat_map(|v| v.to_ne_bytes()).collect();
    let Some(shader) = effect.make_shader(Data::new_copy(&bytes), &[], None) else {
        return false;
    };
    if mode == 1 && !(*s).layers.is_empty() {
        let mask = shader.with_local_matrix(&matrix);
        (*s).layers.last_mut().unwrap().mask = Some(mask);
        return true;
    }
    let mut paint = Paint::default();
    paint
        .set_shader(shader)
        .set_anti_alias(true)
        .set_dither(false);
    if mode == 1 {
        paint.set_blend_mode(BlendMode::DstIn);
    }
    (*s).surface
        .canvas()
        .draw_round_rect(Rect::from_wh(w, h), radius, radius, &paint);
    true
}

#[no_mangle]
pub unsafe extern "C" fn msk_shadow(
    s: *mut Target,
    w: f32,
    h: f32,
    radius: f32,
    dx: f32,
    dy: f32,
    sigma: f32,
    spread: f32,
    color: u32,
    inset: bool,
) {
    if sigma > 0. {
        let info = ImageInfo::new(
            ((*s).surface.width(), (*s).surface.height()),
            ColorType::RGBA8888,
            AlphaType::Premul,
            None,
        );
        let Some(mut mask) = (*s).surface.new_surface(&info) else {
            (*s).failed = true;
            return;
        };
        mask.canvas().clear(Color::TRANSPARENT);
        mask.canvas()
            .set_matrix(&(*s).surface.canvas().local_to_device());
        let rect = if inset {
            Rect::from_xywh(dx + spread, dy + spread, w - 2. * spread, h - 2. * spread)
        } else {
            Rect::from_xywh(dx - spread, dy - spread, w + 2. * spread, h + 2. * spread)
        };
        let r = if inset {
            (radius - spread).max(0.)
        } else {
            (radius + spread).max(0.)
        };
        let mut paint = Paint::default();
        paint
            .set_color(Color::WHITE)
            .set_anti_alias(inset)
            .set_image_filter(gaussian(sigma, None, TileMode::Decal));
        if inset {
            let mut path = skia_safe::PathBuilder::new();
            let extent = sigma * 2.;
            path.add_rect(
                Rect::new(
                    -extent + dx.min(0.),
                    -extent + dy.min(0.),
                    w + extent + dx.max(0.),
                    h + extent + dy.max(0.),
                ),
                None,
                None,
            );
            path.add_rrect(RRect::new_rect_xy(rect, r, r), None, None);
            path.set_fill_type(skia_safe::PathFillType::EvenOdd);
            mask.canvas().draw_path(&path.detach(), &paint);
        } else {
            msk_rrect_mask(
                mask.canvas() as *const skia_safe::Canvas as *const c_void,
                rect.left,
                rect.top,
                rect.right,
                rect.bottom,
                r,
            );
            let image = mask.image_snapshot();
            let Some(mut filtered) = mask.new_surface(&info) else {
                (*s).failed = true;
                return;
            };
            filtered.canvas().clear(Color::TRANSPARENT);
            filtered.canvas().draw_image(image, (0, 0), Some(&paint));
            mask = filtered;
        }
        let mask = mask
            .image_snapshot()
            .to_shader(None, skia_safe::SamplingOptions::default(), None)
            .unwrap();
        let backdrop = (*s)
            .surface
            .image_snapshot()
            .to_shader(None, skia_safe::SamplingOptions::default(), None)
            .unwrap();
        let effect=RuntimeEffect::make_for_shader("uniform shader mask;uniform shader backdrop;uniform float4 color;uniform float inset;half4 main(float2 p){float a=float(mask.eval(p).a);if(inset>0.5)a=1.0-a;a*=color.a;float4 dst=floor(float4(backdrop.eval(p))*255.0+0.5)/255.0;return half4(floor((float4(color.rgb*a,a)+dst*(1.0-a))*255.0+0.5)/255.0);}",None).unwrap();
        let values = [
            ((color >> 16) & 255) as f32 / 255.,
            ((color >> 8) & 255) as f32 / 255.,
            (color & 255) as f32 / 255.,
            (color >> 24) as f32 / 255.,
            0.,
        ];
        let bytes: Vec<u8> = values.iter().flat_map(|v| v.to_ne_bytes()).collect();
        let shader = effect
            .make_shader(
                Data::new_copy(&bytes),
                &[mask.into(), backdrop.into()],
                None,
            )
            .unwrap();
        let canvas = (*s).surface.canvas();
        canvas.save();
        canvas.clip_rrect(
            RRect::new_rect_xy(Rect::from_wh(w, h), radius, radius),
            if inset {
                ClipOp::Intersect
            } else {
                ClipOp::Difference
            },
            true,
        );
        canvas.reset_matrix();
        paint
            .set_image_filter(None)
            .set_shader(shader)
            .set_blend_mode(BlendMode::Src);
        canvas.draw_paint(&paint);
        canvas.restore();
        return;
    }
    let canvas = (*s).surface.canvas();
    let box_shape = RRect::new_rect_xy(Rect::from_wh(w, h), radius, radius);
    canvas.save();
    let mut paint = Paint::default();
    paint.set_color(Color::new(color)).set_anti_alias(true);
    if sigma > 0. {
        paint.set_image_filter(gaussian(sigma, None, TileMode::Decal));
    }
    if inset {
        canvas.clip_rrect(box_shape, None, true);
        let hole = RRect::new_rect_xy(
            Rect::from_xywh(dx + spread, dy + spread, w - 2. * spread, h - 2. * spread),
            (radius - spread).max(0.),
            (radius - spread).max(0.),
        );
        let mut path = skia_safe::PathBuilder::new();
        let extent = w.max(h) + sigma * 10. + dx.abs() + dy.abs() + spread.abs();
        path.add_rect(
            Rect::new(
                -extent + dx.min(0.),
                -extent + dy.min(0.),
                w + extent + dx.max(0.),
                h + extent + dy.max(0.),
            ),
            None,
            None,
        );
        path.add_rrect(hole, None, None);
        path.set_fill_type(skia_safe::PathFillType::EvenOdd);
        canvas.draw_path(&path.detach(), &paint);
    } else {
        canvas.clip_rrect(box_shape, ClipOp::Difference, true);
        canvas.draw_round_rect(
            Rect::from_xywh(dx - spread, dy - spread, w + 2. * spread, h + 2. * spread),
            (radius + spread).max(0.),
            (radius + spread).max(0.),
            &paint,
        );
    }
    canvas.restore();
}

#[no_mangle]
pub unsafe extern "C" fn msk_save_state(s: *mut Target) {
    (*s).depth += 1;
    (*s).surface.canvas().save();
}
