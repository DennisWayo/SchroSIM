use eframe::egui;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions::default();

    eframe::run_native(
        "SchroSIM",
        options,
        Box::new(|_cc| Ok(Box::new(SchroSimApp::default()))),
    )
}

#[derive(Default)]
struct SchroSimApp;

impl eframe::App for SchroSimApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("SchroSIM GUI");
            ui.label("Phase 2: GUI bootstrap");
        });
    }
}