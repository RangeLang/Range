use gpui::{
    App, Application, Bounds, Context, PathBuilder, Window, WindowBounds, WindowOptions, canvas,
    div, linear_color_stop, linear_gradient, point, prelude::*, px, rgb, size,
};

struct RangeViewRoot {
    values: Vec<RangeViewValue>,
}

#[derive(Clone, Copy)]
#[repr(C)]
pub struct RangeViewPointRecord {
    x: i32,
    y: i32,
}

#[derive(Clone, Copy)]
#[repr(C)]
pub struct RangeViewValueRecord {
    kind: i32,
    point_data: *const RangeViewPointRecord,
    point_count: usize,
    terminal_kind: i32,
    color_kind: i32,
    first_color: i32,
    second_color: i32,
    angle: i32,
    strength: i32,
    text_data: *const u8,
    text_count: usize,
}

enum RangeViewValue {
    Shape {
        points: Vec<RangeViewPointRecord>,
        terminal_kind: i32,
        color_kind: i32,
        first_color: i32,
        second_color: i32,
        angle: i32,
        strength: i32,
    },
    Text(String),
}

impl Render for RangeViewRoot {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let mut root = div()
            .relative()
            .size_full()
            .bg(rgb(0x111318))
            .overflow_hidden();
        let mut text_ordinal = 0;
        for value in &self.values {
            match value {
                RangeViewValue::Shape {
                    points,
                    terminal_kind,
                    color_kind,
                    first_color,
                    second_color,
                    angle,
                    strength,
                } => {
                    let points = points.clone();
                    let terminal_kind = *terminal_kind;
                    let color_kind = *color_kind;
                    let first_color = *first_color;
                    let second_color = *second_color;
                    let angle = *angle;
                    let strength = *strength;
                    root = root.child(
                        canvas(
                            |_, _, _| {},
                            move |_, _, window, _| {
                                let mut path = PathBuilder::fill();
                                for (ordinal, value) in points.iter().enumerate() {
                                    let position = point(px(value.x as f32), px(value.y as f32));
                                    if ordinal == 0 {
                                        path.move_to(position);
                                    } else {
                                        path.line_to(position);
                                    }
                                }
                                path.close();
                                if let Ok(path) = path.build() {
                                    if terminal_kind == 4 && color_kind == 3 {
                                        window.paint_path(
                                            path,
                                            linear_gradient(
                                                angle as f32,
                                                linear_color_stop(
                                                    rgb(emitted_rgb(first_color, strength)),
                                                    0.0,
                                                ),
                                                linear_color_stop(
                                                    rgb(emitted_rgb(second_color, strength)),
                                                    1.0,
                                                ),
                                            ),
                                        );
                                    }
                                }
                            },
                        )
                            .absolute()
                            .size_full(),
                    );
                }
                RangeViewValue::Text(text) => {
                    root = root.child(
                        div()
                            .absolute()
                            .left(px(28.0))
                            .top(px(24.0 + text_ordinal as f32 * 34.0))
                            .text_color(rgb(0xf4f7ff))
                            .text_xl()
                            .child(text.clone()),
                    );
                    text_ordinal += 1;
                }
            }
        }
        root
    }
}

fn emitted_rgb(color: i32, strength: i32) -> u32 {
    let color = color.max(0) as u32;
    let strength = strength.max(0) as u32;
    let channel = |shift: u32| -> u32 {
        ((((color >> shift) & 0xff) * strength) / 100).min(0xff)
    };
    (channel(16) << 16) | (channel(8) << 8) | channel(0)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rangeGPUIRun(
    title_data: *const u8,
    title_count: usize,
    value_data: *const RangeViewValueRecord,
    value_count: usize,
) -> i32 {
    if title_data.is_null() || (value_count != 0 && value_data.is_null()) {
        return 64;
    }
    let title_bytes = unsafe { std::slice::from_raw_parts(title_data, title_count) };
    let Ok(title) = std::str::from_utf8(title_bytes) else {
        return 65;
    };
    let title = title.to_owned();
    let records = if value_count == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(value_data, value_count) }
    };
    let mut values = Vec::with_capacity(value_count);
    for record in records {
        if record.kind == 1 {
            if record.point_data.is_null()
                || record.point_count < 3
                || record.terminal_kind != 4
                || record.color_kind != 3
                || record.strength < 0
            {
                return 64;
            }
            let points = unsafe {
                std::slice::from_raw_parts(record.point_data, record.point_count)
            };
            values.push(RangeViewValue::Shape {
                points: points.to_vec(),
                terminal_kind: record.terminal_kind,
                color_kind: record.color_kind,
                first_color: record.first_color,
                second_color: record.second_color,
                angle: record.angle,
                strength: record.strength,
            });
        } else if record.kind == 2 {
            if record.text_data.is_null() {
                return 64;
            }
            let bytes = unsafe {
                std::slice::from_raw_parts(record.text_data, record.text_count)
            };
            let Ok(text) = std::str::from_utf8(bytes) else {
                return 65;
            };
            values.push(RangeViewValue::Text(text.to_owned()));
        } else {
            return 66;
        }
    }

    if std::env::var_os("RANGE_GPUI_LINK_PROBE").is_some() {
        return 0;
    }

    Application::new().run(move |cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(800.0), px(520.0)), cx);
        let view_title = title.clone();
        let result = cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            move |window, cx| {
                window.set_window_title(&view_title);
                cx.new(|_| RangeViewRoot { values })
            },
        );
        if result.is_ok() {
            cx.activate(true);
        } else {
            cx.quit();
        }
    });
    0
}
