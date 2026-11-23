// The composite runs on its own thread: the window never waits for it. Only the latest request is kept, so a fast zoom or pan
// skips the frames nobody would see.
use std::sync::{Arc, Condvar, Mutex};
use std::time::Instant;

use photocraft_engine::doc::Document;

pub struct Request {
    pub generation: u64,
    pub doc: Arc<Document>,
    pub rect: (i32, i32, i32, i32),
    pub w: u32,
    pub h: u32,
}

pub struct Frame {
    pub generation: u64,
    pub rect: (i32, i32, i32, i32),
    pub w: i32,
    pub h: i32,
    pub pixels: Vec<u8>,
    pub opaque: bool,
    pub ms: u128,
}

pub fn composite(request: &Request) -> Frame {
    let start = Instant::now();
    let (x0, y0, x1, y1) = request.rect;
    let rect = photocraft_engine::doc::Rect::new(x0, y0, x1, y1);
    let image = photocraft_compose::render_reduced_rect(&request.doc, rect, request.w, request.h).to_rgba8();
    let opaque = image.pixels.chunks_exact(4).all(|p| p[3] == 255);
    Frame {
        generation: request.generation,
        rect: request.rect,
        w: image.width as i32,
        h: image.height as i32,
        pixels: image.pixels,
        opaque,
        ms: start.elapsed().as_millis(),
    }
}

pub struct Renderer {
    slot: Arc<(Mutex<Option<Request>>, Condvar)>,
}

impl Renderer {
    /// `done` receives each frame on the render thread; the thread ends when it returns false
    pub fn start(done: impl Fn(Frame) -> bool + Send + 'static) -> Self {
        let slot = Arc::new((Mutex::new(None::<Request>), Condvar::new()));
        let worker = slot.clone();
        std::thread::spawn(move || {
            loop {
                let request = {
                    let (lock, ready) = &*worker;
                    let Ok(mut pending) = lock.lock() else { return };
                    while pending.is_none() {
                        let Ok(next) = ready.wait(pending) else { return };
                        pending = next;
                    }
                    pending.take()
                };
                if let Some(request) = request
                    && !done(composite(&request))
                {
                    return;
                }
            }
        });
        Self { slot }
    }

    pub fn request(&self, request: Request) {
        let (lock, ready) = &*self.slot;
        if let Ok(mut pending) = lock.lock() {
            *pending = Some(request);
            ready.notify_one();
        }
    }
}
