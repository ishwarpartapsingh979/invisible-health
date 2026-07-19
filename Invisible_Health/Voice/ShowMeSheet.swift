import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - "Show Me" — the user shows the coach what it can't log into
//
// When something is login-gated (Cult classes, a society timetable, a
// nutritionist's PDF), the coach can't browse it. Instead the user SHOWS it:
// a screenshot, a screen-recording (made via Control Center), or a PDF. We upload
// it to the token server's /extract, where Gemini vision reads it into a
// structured, time-bounded schedule stored per user. The coach reads it back
// later. No credentials, no scraping — works for any studio/app.

// MARK: Models (mirror the token server's /extract + /schedules shapes)

/// One row of an extracted schedule. Tolerant: fitness rows use day/time/name,
/// nutrition rows use slot/items — every field is optional.
struct ScheduleItem: Codable, Identifiable {
    var day: String?
    var time: String?
    var name: String?
    var location: String?
    var notes: String?
    var slot: String?
    var items: [String]?

    var id: String { (day ?? slot ?? "") + (time ?? "") + (name ?? "") + (items?.first ?? "") }
    var primary: String { name ?? slot ?? "—" }
    var secondary: String {
        var bits = [day, time].compactMap { $0 }
        if let loc = location, !loc.isEmpty { bits.append(loc) }
        if let list = items, !list.isEmpty { bits.append(list.joined(separator: ", ")) }
        return bits.joined(separator: " · ")
    }
}

/// The structured read of one capture (the jsonb `extracted` column).
struct ScheduleExtract: Codable {
    var title: String?
    var valid_from: String?
    var valid_to: String?
    var items: [ScheduleItem]?
}

/// A stored schedule row (from GET /schedules).
struct UserSchedule: Codable, Identifiable {
    var id: UUID
    var kind: String?
    var title: String?
    var source: String?
    var extracted: ScheduleExtract?
    var valid_from: String?
    var valid_to: String?
    var captured_at: String?
}

struct SchedulesResponse: Codable { var schedules: [UserSchedule] }

/// The /extract reply.
struct ExtractResponse: Codable {
    var ok: Bool?
    var stored: Bool?
    var error: String?
    var extracted: ScheduleExtract?
    var valid_from: String?
    var valid_to: String?
}

/// One picked capture, normalised to bytes so the uploader is uniform.
struct CapturedFile {
    let data: Data
    let mime: String
    let filename: String
    let source: String   // screenshot | recording | upload
}

// MARK: Uploader

enum ShowMeUploader {
    /// POST a capture to /extract (multipart). Long timeout — a screen-recording
    /// goes through Gemini's file API, which needs a processing wait server-side.
    static func upload(_ file: CapturedFile, kind: String, title: String) async throws -> ExtractResponse {
        guard let url = URL(string: VoiceConfig.tokenServerBaseURL + "/extract") else {
            throw URLError(.badURL)
        }
        let boundary = "IH-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 290
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let fields = ["kind": kind, "user_id": "ishwar", "source": file.source, "title": title]
        for (k, v) in fields {
            body.appendStr("--\(boundary)\r\n")
            body.appendStr("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n")
            body.appendStr("\(v)\r\n")
        }
        body.appendStr("--\(boundary)\r\n")
        body.appendStr("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.filename)\"\r\n")
        body.appendStr("Content-Type: \(file.mime)\r\n\r\n")
        body.append(file.data)
        body.appendStr("\r\n--\(boundary)--\r\n")

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 290
        cfg.timeoutIntervalForResource = 300
        let session = URLSession(configuration: cfg)
        let (respData, _) = try await session.upload(for: req, from: body)
        return try JSONDecoder().decode(ExtractResponse.self, from: respData)
    }
}

private extension Data {
    mutating func appendStr(_ s: String) { if let d = s.data(using: .utf8) { append(d) } }
}

// MARK: The sheet

/// Presented when the coach hits a login wall (or from a tab button). Lets the user
/// pick a screenshot / screen-recording / PDF; uploads it; shows what was read.
struct ShowMeSheet: View {
    /// A short line explaining why we're here (e.g. "Cult needs a login").
    let reason: String?
    let onClose: () -> Void

    @State private var kind: String
    @State private var title: String = ""
    @State private var stage: Stage = .idle
    @State private var pickImages = false
    @State private var pickVideos = false
    @State private var pickDocs = false

    private enum Stage {
        case idle, uploading, done(ExtractResponse), failed(String)
    }

    /// `initialKind` ("fitness"/"nutrition") seeds the picker; the coach passes it
    /// when it opens the sheet on a login wall.
    init(initialKind: String = "fitness", reason: String? = nil, onClose: @escaping () -> Void) {
        self.reason = reason
        self.onClose = onClose
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let reason, !reason.isEmpty {
                        Label(reason, systemImage: "lock.fill")
                            .font(.subheadline).foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text("Show me the schedule and I'll remember it for you — you won't have to open that app again.")
                        .font(.subheadline).foregroundColor(.secondary)

                    Picker("Type", selection: $kind) {
                        Text("Fitness / classes").tag("fitness")
                        Text("Nutrition / diet").tag("nutrition")
                    }
                    .pickerStyle(.segmented)

                    TextField(kind == "nutrition" ? "Name (e.g. My diet chart)" : "Name (e.g. Cult Shantiniketan)",
                              text: $title)
                        .textFieldStyle(.roundedBorder)

                    switch stage {
                    case .uploading:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading it… (a screen-recording can take a moment)")
                                .font(.subheadline).foregroundColor(.secondary)
                        }.padding(.vertical, 8)
                    case .done(let resp):
                        resultView(resp)
                    case .failed(let msg):
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundColor(.red)
                        captureButtons
                    case .idle:
                        captureButtons
                    }

                    Text("Tip: to capture a whole timetable, record your screen (swipe Control Centre ▸ Record) while scrolling through it, then pick “Screen recording”.")
                        .font(.caption2).foregroundColor(.gray)
                }
                .padding(20)
            }
            .navigationTitle("Show the coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
        // Screenshot / photo
        .sheet(isPresented: $pickImages) {
            PhotoVideoPicker(filter: .images) { picked in
                pickImages = false
                if let picked { Task { await handle(picked) } }
            }
        }
        // Screen recording / video
        .sheet(isPresented: $pickVideos) {
            PhotoVideoPicker(filter: .videos) { picked in
                pickVideos = false
                if let picked { Task { await handle(picked) } }
            }
        }
        // PDF / file
        .sheet(isPresented: $pickDocs) {
            DocPicker { picked in
                pickDocs = false
                if let picked { Task { await handle(picked) } }
            }
        }
    }

    private var captureButtons: some View {
        VStack(spacing: 12) {
            captureButton("Screenshot / photo", "photo") { pickImages = true }
            captureButton("Screen recording", "record.circle") { pickVideos = true }
            captureButton("PDF / file", "doc") { pickDocs = true }
        }
    }

    private func captureButton(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.headline).frame(maxWidth: .infinity).padding()
                .background(Color.white.opacity(0.10))
                .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func resultView(_ resp: ExtractResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Got it — saved.", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundColor(.green)
            if let vf = resp.valid_from ?? resp.extracted?.valid_from {
                let vt = resp.valid_to ?? resp.extracted?.valid_to
                Text("Covers \(vf)\(vt.map { " → \($0)" } ?? "")")
                    .font(.caption).foregroundColor(.secondary)
            }
            let items = resp.extracted?.items ?? []
            if items.isEmpty {
                Text("I couldn't read clear rows — try a sharper capture or a screen recording.")
                    .font(.caption).foregroundColor(.orange)
            } else {
                ForEach(items.prefix(12)) { it in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.primary).font(.subheadline.weight(.semibold))
                        if !it.secondary.isEmpty {
                            Text(it.secondary).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if items.count > 12 {
                    Text("+ \(items.count - 12) more").font(.caption).foregroundColor(.gray)
                }
            }
            Button("Add another") { stage = .idle }
                .font(.subheadline).padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func handle(_ file: CapturedFile) async {
        stage = .uploading
        do {
            let resp = try await ShowMeUploader.upload(file, kind: kind, title: title)
            if resp.ok == true {
                stage = .done(resp)
            } else {
                stage = .failed(resp.error ?? "Couldn't read that — try again.")
            }
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}

// MARK: Pickers (UIKit bridges)

/// PHPicker for one image OR one video, normalised to a CapturedFile.
struct PhotoVideoPicker: UIViewControllerRepresentable {
    let filter: PHPickerFilter
    let onPick: (CapturedFile?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = filter
        cfg.selectionLimit = 1
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (CapturedFile?) -> Void
        init(onPick: @escaping (CapturedFile?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { return onPick(nil) }

            // Image → re-encode to JPEG (Gemini-friendly, avoids HEIC issues).
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage, let data = img.jpegData(compressionQuality: 0.85) {
                        self.onPick(CapturedFile(data: data, mime: "image/jpeg",
                                                 filename: "capture.jpg", source: "screenshot"))
                    } else { self.onPick(nil) }
                }
                return
            }
            // Video → copy the file, read its bytes.
            let movieType = UTType.movie.identifier
            if provider.hasItemConformingToTypeIdentifier(movieType) {
                provider.loadFileRepresentation(forTypeIdentifier: movieType) { url, _ in
                    guard let url, let data = try? Data(contentsOf: url) else { return self.onPick(nil) }
                    let ext = url.pathExtension.lowercased()
                    let mime = ext == "mov" ? "video/quicktime" : "video/mp4"
                    self.onPick(CapturedFile(data: data, mime: mime,
                                             filename: "recording.\(ext.isEmpty ? "mp4" : ext)",
                                             source: "recording"))
                }
                return
            }
            onPick(nil)
        }
    }
}

/// Document picker for a PDF (or image file).
struct DocPicker: UIViewControllerRepresentable {
    let onPick: (CapturedFile?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image], asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (CapturedFile?) -> Void
        init(onPick: @escaping (CapturedFile?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return onPick(nil) }
            let ext = url.pathExtension.lowercased()
            let mime = ext == "pdf" ? "application/pdf" : "image/jpeg"
            onPick(CapturedFile(data: data, mime: mime,
                                filename: url.lastPathComponent, source: "upload"))
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

// MARK: Schedules section (read-back on the Workout / Nutrition tabs)

/// Shows the user's captured schedules for a kind, plus a button to add one.
/// Drop into a tab; it loads itself from /schedules.
struct SchedulesSection: View {
    let kind: String              // "fitness" | "nutrition"
    @State private var schedules: [UserSchedule] = []
    @State private var loading = false
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind == "nutrition" ? "MY DIET CHARTS" : "MY SCHEDULES")
                    .font(.caption2).tracking(1.5).foregroundColor(.gray)
                Spacer()
                Button { showSheet = true } label: {
                    Label("Show the coach", systemImage: "plus.viewfinder").font(.caption)
                }
            }

            if schedules.isEmpty {
                Text(kind == "nutrition"
                     ? "Show me your diet chart (screenshot / PDF) and I'll plan around it."
                     : "Show me your class timetable (screenshot / screen-recording) and I'll build it in.")
                    .font(.caption).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(schedules) { s in scheduleCard(s) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
        .onAppear { Task { await refresh() } }
        .sheet(isPresented: $showSheet, onDismiss: { Task { await refresh() } }) {
            ShowMeSheet(initialKind: kind) { showSheet = false }
        }
    }

    private func scheduleCard(_ s: UserSchedule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.title ?? s.extracted?.title ?? (kind == "nutrition" ? "Diet chart" : "Schedule"))
                    .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Spacer()
                if let vt = s.valid_to ?? s.extracted?.valid_to {
                    Text("until \(vt)").font(.caption2).foregroundColor(.gray)
                }
            }
            let items = s.extracted?.items ?? []
            ForEach(items.prefix(5)) { it in
                Text("• \(it.primary)\(it.secondary.isEmpty ? "" : " — \(it.secondary)")")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if items.count > 5 {
                Text("+ \(items.count - 5) more").font(.caption2).foregroundColor(.gray)
            }
        }
        .padding(.vertical, 6)
    }

    private func refresh() async {
        guard let url = URL(string: VoiceConfig.tokenServerBaseURL + "/schedules?user_id=ishwar&kind=\(kind)")
        else { return }
        loading = true; defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            schedules = try JSONDecoder().decode(SchedulesResponse.self, from: data).schedules
        } catch {
            // keep whatever we had
        }
    }
}
