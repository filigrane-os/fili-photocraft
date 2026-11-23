// Where the image sits in the canvas: zoom, centre and the part of the document to composite. Pure arithmetic, no Qt.

pub const MIN_ZOOM: f64 = 0.01;
pub const MAX_ZOOM: f64 = 32.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct View {
    pub doc_w: f64,
    pub doc_h: f64,
    pub item_w: f64,
    pub item_h: f64,
    pub dpr: f64,
    pub fit: bool,
    zoom: f64,
    cx: f64,
    cy: f64,
}

impl Default for View {
    fn default() -> Self {
        Self { doc_w: 0.0, doc_h: 0.0, item_w: 0.0, item_h: 0.0, dpr: 1.0, fit: true, zoom: 1.0, cx: 0.0, cy: 0.0 }
    }
}

impl View {
    pub fn set_document(&mut self, w: f64, h: f64) {
        (self.doc_w, self.doc_h) = (w, h);
        self.zoom_fit();
    }

    /// Keeps the zoom and the centre when the size of the document is unchanged (undo, redo, a command)
    pub fn keep_document(&mut self, w: f64, h: f64) {
        if (w, h) != (self.doc_w, self.doc_h) {
            self.set_document(w, h);
        }
    }

    pub fn set_item(&mut self, w: f64, h: f64, dpr: f64) {
        (self.item_w, self.item_h, self.dpr) = (w, h, if dpr > 0.0 { dpr } else { 1.0 });
        self.clamp();
    }

    /// The whole image in the item, never enlarged
    fn fit_zoom(&self) -> f64 {
        if self.doc_w <= 0.0 || self.doc_h <= 0.0 || self.item_w <= 0.0 || self.item_h <= 0.0 {
            return 1.0;
        }
        (self.item_w / self.doc_w).min(self.item_h / self.doc_h).clamp(MIN_ZOOM, 1.0)
    }

    pub fn zoom(&self) -> f64 {
        if self.fit { self.fit_zoom() } else { self.zoom }
    }

    pub fn zoom_fit(&mut self) {
        self.fit = true;
        (self.cx, self.cy) = (self.doc_w / 2.0, self.doc_h / 2.0);
    }

    pub fn zoom_actual(&mut self) {
        self.zoom = 1.0;
        self.fit = false;
        self.clamp();
    }

    /// Zooms by `factor`, the document point under (x, y) of the item staying there
    pub fn zoom_at(&mut self, factor: f64, x: f64, y: f64) {
        let (dx, dy) = self.to_doc(x, y);
        let zoom = (self.zoom() * factor).clamp(MIN_ZOOM, MAX_ZOOM);
        self.zoom = zoom;
        self.fit = false;
        self.cx = dx - (x - self.item_w / 2.0) / zoom;
        self.cy = dy - (y - self.item_h / 2.0) / zoom;
        self.clamp();
    }

    pub fn pan(&mut self, dx: f64, dy: f64) {
        if self.fit {
            self.zoom = self.fit_zoom();
            self.fit = false;
        }
        self.cx -= dx / self.zoom;
        self.cy -= dy / self.zoom;
        self.clamp();
    }

    /// Puts the point (x, y) of the document at the centre of the item (the Navigator)
    pub fn center_on(&mut self, x: f64, y: f64) {
        if self.fit {
            self.zoom = self.fit_zoom();
            self.fit = false;
        }
        self.cx = x;
        self.cy = y;
        self.clamp();
    }

    /// An axis on which the image is smaller than the item stays centred
    fn clamp(&mut self) {
        let zoom = self.zoom();
        let axis = |c: f64, doc: f64, item: f64| {
            let half = item / 2.0 / zoom;
            if doc <= half * 2.0 { doc / 2.0 } else { c.clamp(half, doc - half) }
        };
        self.cx = axis(self.cx, self.doc_w, self.item_w);
        self.cy = axis(self.cy, self.doc_h, self.item_h);
    }

    pub fn to_item(&self, x: f64, y: f64) -> (f64, f64) {
        let zoom = self.zoom();
        ((x - self.cx) * zoom + self.item_w / 2.0, (y - self.cy) * zoom + self.item_h / 2.0)
    }

    pub fn to_doc(&self, x: f64, y: f64) -> (f64, f64) {
        let zoom = self.zoom();
        ((x - self.item_w / 2.0) / zoom + self.cx, (y - self.item_h / 2.0) / zoom + self.cy)
    }

    /// The visible part of the document (x0, y0, x1, y1), and the size to composite it at: device pixels, at most 1:1
    pub fn visible(&self) -> Option<((i32, i32, i32, i32), u32, u32)> {
        let (a, b) = (self.to_doc(0.0, 0.0), self.to_doc(self.item_w, self.item_h));
        let x0 = a.0.floor().max(0.0) as i32;
        let y0 = a.1.floor().max(0.0) as i32;
        let x1 = b.0.ceil().min(self.doc_w) as i32;
        let y1 = b.1.ceil().min(self.doc_h) as i32;
        if x1 <= x0 || y1 <= y0 {
            return None;
        }
        let scale = (self.zoom() * self.dpr).min(1.0);
        let w = ((x1 - x0) as f64 * scale).ceil().max(1.0) as u32;
        let h = ((y1 - y0) as f64 * scale).ceil().max(1.0) as u32;
        Some(((x0, y0, x1, y1), w, h))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn view() -> View {
        let mut v = View::default();
        v.set_item(800.0, 600.0, 1.0);
        v.set_document(4000.0, 3000.0);
        v
    }

    #[test]
    fn fit_shows_the_whole_image_and_never_enlarges() {
        let v = view();
        assert_eq!(v.zoom(), 0.2);
        assert_eq!(v.visible(), Some(((0, 0, 4000, 3000), 800, 600)));
        let mut small = View::default();
        small.set_item(800.0, 600.0, 1.0);
        small.set_document(100.0, 100.0);
        assert_eq!(small.zoom(), 1.0);
    }

    #[test]
    fn zoom_keeps_the_point_under_the_pointer() {
        let mut v = view();
        let before = v.to_doc(200.0, 150.0);
        v.zoom_at(2.0, 200.0, 150.0);
        let after = v.to_doc(200.0, 150.0);
        assert!((before.0 - after.0).abs() < 1e-6 && (before.1 - after.1).abs() < 1e-6);
    }

    #[test]
    fn at_100_percent_only_the_visible_part_is_composited() {
        let mut v = view();
        v.zoom_actual();
        let ((x0, y0, x1, y1), w, h) = v.visible().unwrap();
        assert_eq!(((x1 - x0), (y1 - y0), w, h), (800, 600, 800, 600));
    }

    #[test]
    fn pan_stops_at_the_edges() {
        let mut v = view();
        v.zoom_actual();
        v.pan(1e6, 1e6);
        assert_eq!(v.to_doc(0.0, 0.0), (0.0, 0.0));
    }

    #[test]
    fn device_pixels_are_used_below_100_percent() {
        let mut v = view();
        v.set_item(800.0, 600.0, 2.0);
        assert_eq!(v.visible().unwrap().1, 1600);
    }
}
