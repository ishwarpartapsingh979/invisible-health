import SwiftUI
import UniformTypeIdentifiers
import AVKit

// MARK: - Data Models

struct EquipmentSubmission: Identifiable, Codable {
    let id: String
    let timestamp: String
    let media_url: String
    let media_type: String
    let filename: String
    let equipment: [Equipment]
    let environment: String?
    let total_items: Int

    var displayDate: String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: timestamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }

    var safeEnvironment: String {
        return environment ?? "unknown"
    }
}

struct Equipment: Identifiable, Codable {
    // Use name + type + details to create unique ID (since multiple items can have same name+type)
    var id: String { name + type + details }
    let name: String
    let type: String
    let quantity: String
    let details: String
    let confidence: String

    // Custom decoding to handle quantity as both Int and String
    enum CodingKeys: String, CodingKey {
        case name, type, quantity, details, confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        details = try container.decode(String.self, forKey: .details)
        confidence = try container.decode(String.self, forKey: .confidence)

        // Handle quantity as either Int or String
        if let quantityInt = try? container.decode(Int.self, forKey: .quantity) {
            quantity = String(quantityInt)
        } else if let quantityString = try? container.decode(String.self, forKey: .quantity) {
            quantity = quantityString
        } else {
            quantity = "1"
        }
    }
}

struct EquipmentResponse: Codable {
    let success: Bool?
    let message: String?
    let submission: EquipmentSubmission?
    let error: String?

    // Default to false if not present
    var isSuccess: Bool {
        return success ?? false
    }
}

struct EquipmentHistoryResponse: Codable {
    let success: Bool?
    let equipment_history: [EquipmentSubmission]?
    let total_submissions: Int?
    let error: String?

    // Default values
    var isSuccess: Bool {
        return success ?? false
    }

    var submissions: [EquipmentSubmission] {
        return equipment_history ?? []
    }

    var count: Int {
        return total_submissions ?? 0
    }
}

struct DeleteEquipmentResponse: Codable {
    let success: Bool?
    let message: String?
    let deleted_id: String?
    let deleted_count: Int?
    let error: String?

    var isSuccess: Bool {
        return success ?? false
    }
}

// MARK: - Main View

struct EquipmentView: View {
    @State private var submissions: [EquipmentSubmission] = []
    @State private var isLoading = false
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var showVideoCamera = false
    @State private var showVideoLibrary = false
    @State private var showActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedSubmission: EquipmentSubmission?
    @State private var showDeleteAllConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("EQUIPMENT")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)

                    Spacer()

                    // Delete All button (only show if there are items)
                    if !submissions.isEmpty && !isLoading && !isUploading {
                        Button(action: { showDeleteAllConfirmation = true }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    }

                    Button(action: { showActionSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .padding(.top, 40)

                // Loading State
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(1.5)
                    Text("Loading equipment...")
                        .foregroundColor(.gray)
                        .padding(.top)
                    Spacer()
                }
                // Uploading State
                else if isUploading {
                    Spacer()
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .scaleEffect(1.5)
                        Text("Analyzing equipment...")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("This may take a few seconds")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    Spacer()
                }
                // Empty State
                else if submissions.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("No equipment logged yet")
                            .foregroundColor(.gray)
                            .font(.headline)

                        Text("Tap + to add your gym equipment")
                            .foregroundColor(.gray.opacity(0.7))
                            .font(.caption)
                    }
                    Spacer()
                }
                // Grid View
                else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 15),
                            GridItem(.flexible(), spacing: 15)
                        ], spacing: 15) {
                            ForEach(submissions) { submission in
                                EquipmentCard(submission: submission)
                                    .onTapGesture {
                                        selectedSubmission = submission
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteEquipment(submissionId: submission.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .onAppear {
            loadEquipmentHistory()
        }
        .actionSheet(isPresented: $showActionSheet) {
            ActionSheet(
                title: Text("Add Equipment"),
                message: Text("Choose a source"),
                buttons: [
                    .default(Text("Take Photo")) {
                        showCamera = true
                    },
                    .default(Text("Choose from Gallery")) {
                        showGallery = true
                    },
                    .default(Text("Record Video")) {
                        showVideoCamera = true
                    },
                    .default(Text("Choose Video")) {
                        showVideoLibrary = true
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showCamera) {
            EquipmentImagePicker(sourceType: .camera) { image in
                selectedImage = image
                uploadEquipment(image: image)
            }
        }
        .sheet(isPresented: $showGallery) {
            EquipmentImagePicker(sourceType: .photoLibrary) { image in
                selectedImage = image
                uploadEquipment(image: image)
            }
        }
        .sheet(isPresented: $showVideoCamera) {
            EquipmentVideoPicker(sourceType: .camera) { videoURL in
                selectedVideoURL = videoURL
                uploadEquipment(videoURL: videoURL)
            }
        }
        .sheet(isPresented: $showVideoLibrary) {
            EquipmentVideoPicker(sourceType: .photoLibrary) { videoURL in
                selectedVideoURL = videoURL
                uploadEquipment(videoURL: videoURL)
            }
        }
        .sheet(item: $selectedSubmission) { submission in
            EquipmentDetailView(submission: submission)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
        .alert("Delete All Equipment", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllEquipment()
            }
        } message: {
            Text("Are you sure you want to delete all \(submissions.count) equipment submissions? This cannot be undone.")
        }
    }

    // MARK: - Load History

    func loadEquipmentHistory() {
        isLoading = true

        AgentManager.shared.getEquipmentHistory { result in
            DispatchQueue.main.async {
                isLoading = false

                switch result {
                case .success(let response):
                    if response.isSuccess {
                        self.submissions = response.submissions
                    } else {
                        self.errorMessage = response.error ?? "Failed to load equipment"
                        self.showError = true
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    // MARK: - Upload Equipment

    func uploadEquipment(image: UIImage? = nil, videoURL: URL? = nil) {
        isUploading = true

        AgentManager.shared.sendEquipmentInput(image: image, videoURL: videoURL) { result in
            DispatchQueue.main.async {
                isUploading = false

                switch result {
                case .success(let response):
                    if response.isSuccess {
                        // Add new submission to the list
                        if let newSubmission = response.submission {
                            print("✅ New submission added - Media URL: \(newSubmission.media_url)")
                            print("   Media Type: \(newSubmission.media_type)")
                            print("   Equipment count: \(newSubmission.total_items)")
                            self.submissions.insert(newSubmission, at: 0)
                        }
                    } else {
                        self.errorMessage = response.error ?? "Failed to analyze equipment"
                        self.showError = true
                    }
                case .failure(let error):
                    print("❌ Upload failed: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    // MARK: - Delete Equipment

    func deleteEquipment(submissionId: String) {
        isDeleting = true

        AgentManager.shared.deleteEquipment(submissionId: submissionId) { result in
            DispatchQueue.main.async {
                isDeleting = false

                switch result {
                case .success(let response):
                    if response.isSuccess {
                        // Remove from local array
                        self.submissions.removeAll { $0.id == submissionId }
                    } else {
                        self.errorMessage = response.error ?? "Failed to delete equipment"
                        self.showError = true
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    func deleteAllEquipment() {
        isDeleting = true

        AgentManager.shared.deleteAllEquipment { result in
            DispatchQueue.main.async {
                isDeleting = false

                switch result {
                case .success(let response):
                    if response.isSuccess {
                        // Clear local array
                        self.submissions.removeAll()
                    } else {
                        self.errorMessage = response.error ?? "Failed to delete all equipment"
                        self.showError = true
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
}

// MARK: - Equipment Card

struct EquipmentCard: View {
    let submission: EquipmentSubmission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image or Video
            if submission.media_type == "video" {
                // Video thumbnail
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 120)

                    VStack {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                        Text("VIDEO")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
                .cornerRadius(10)
            } else {
                // Image with better error handling
                let cleanedURL = submission.media_url.trimmingCharacters(in: CharacterSet(charactersIn: "?"))

                AsyncImage(url: URL(string: cleanedURL)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 120)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            )
                            .onAppear {
                                print("⏳ Loading image: \(cleanedURL)")
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .onAppear {
                                print("✅ Image loaded successfully: \(cleanedURL)")
                            }
                    case .failure(let error):
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 120)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                    Text("Failed to load")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text("Tap to retry")
                                        .font(.caption2)
                                        .foregroundColor(.gray.opacity(0.7))
                                }
                            )
                            .onAppear {
                                print("❌ Image failed to load")
                                print("   Original URL: \(submission.media_url)")
                                print("   Cleaned URL: \(cleanedURL)")
                                print("   Error: \(error)")

                                // Check if URL is valid
                                if URL(string: cleanedURL) == nil {
                                    print("   ⚠️ INVALID URL FORMAT")
                                }
                            }
                            .onTapGesture {
                                // User can tap to open in browser for debugging
                                if let url = URL(string: cleanedURL) {
                                    print("🔗 Opening URL in browser: \(cleanedURL)")
                                }
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(10)
            }

            // Equipment Count & Media Type
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text("\(submission.total_items) items")
                    .font(.caption)
                    .foregroundColor(.white)

                Spacer()

                // Media type badge
                HStack(spacing: 3) {
                    Image(systemName: submission.media_type == "video" ? "video.fill" : "photo.fill")
                        .font(.caption2)
                    Text(submission.media_type.uppercased())
                        .font(.caption2)
                }
                .foregroundColor(.orange)
            }

            // Environment Badge
            Text(submission.safeEnvironment.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption2)
                .foregroundColor(.gray)

            // Date
            Text(submission.displayDate)
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Equipment Detail View

struct EquipmentDetailView: View {
    let submission: EquipmentSubmission
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Image or Video
                        if submission.media_type == "video" {
                            if let url = URL(string: submission.media_url) {
                                VideoPlayer(player: AVPlayer(url: url))
                                    .frame(height: 300)
                                    .cornerRadius(15)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 300)
                                    .overlay(
                                        Text("Invalid video URL")
                                            .foregroundColor(.gray)
                                    )
                                    .cornerRadius(15)
                            }
                        } else {
                            // Image
                            AsyncImage(url: URL(string: submission.media_url)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .cornerRadius(15)
                                case .failure:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 200)
                                        .overlay(
                                            VStack {
                                                Image(systemName: "exclamationmark.triangle")
                                                    .foregroundColor(.orange)
                                                Text("Failed to load image")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        )
                                case .empty:
                                    ProgressView()
                                        .frame(height: 200)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }

                        // Info Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Environment:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(submission.safeEnvironment.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                            }

                            HStack {
                                Text("Total Items:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(submission.total_items)")
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                            }

                            HStack {
                                Text("Logged:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(submission.displayDate)
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)

                        // Equipment List
                        Text("Equipment")
                            .font(.headline)
                            .foregroundColor(.white)

                        ForEach(submission.equipment) { equipment in
                            EquipmentRow(equipment: equipment)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Equipment Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Equipment Row

struct EquipmentRow: View {
    let equipment: Equipment

    var typeIcon: String {
        switch equipment.type {
        case "cardio": return "figure.run"
        case "strength": return "figure.strengthtraining.traditional"
        case "free_weights": return "dumbbell.fill"
        case "machine": return "square.grid.3x3.fill"
        case "bench": return "rectangle.fill"
        default: return "circle.fill"
        }
    }

    var confidenceColor: Color {
        switch equipment.confidence {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 30)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(equipment.name)
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Qty: \(equipment.quantity)")
                    .font(.caption)
                    .foregroundColor(.gray)

                if !equipment.details.isEmpty {
                    Text(equipment.details)
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                }

                // Confidence Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 6, height: 6)

                    Text("\(equipment.confidence) confidence")
                        .font(.caption2)
                        .foregroundColor(confidenceColor)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Image Picker for Equipment

struct EquipmentImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    var onImagePicked: (UIImage) -> Void

    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.allowsEditing = false
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: EquipmentImagePicker

        init(_ parent: EquipmentImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Video Picker for Equipment

struct EquipmentVideoPicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    var onVideoPicked: (URL) -> Void

    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = [UTType.movie.identifier] // Only allow videos
        picker.videoQuality = .typeMedium // Balance quality and size
        picker.videoMaximumDuration = 60 // Max 60 seconds
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: EquipmentVideoPicker

        init(_ parent: EquipmentVideoPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[.mediaURL] as? URL {
                parent.onVideoPicked(videoURL)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
