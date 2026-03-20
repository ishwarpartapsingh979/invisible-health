import SwiftUI

// MARK: - Data Models

struct EquipmentSubmission: Identifiable, Codable {
    let id: String
    let timestamp: String
    let media_url: String
    let media_type: String
    let filename: String
    let equipment: [Equipment]
    let environment: String
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
}

struct Equipment: Identifiable, Codable {
    var id: String { name + type }
    let name: String
    let type: String
    let quantity: String
    let details: String
    let confidence: String
}

struct EquipmentResponse: Codable {
    let success: Bool
    let message: String?
    let submission: EquipmentSubmission?
    let error: String?
}

struct EquipmentHistoryResponse: Codable {
    let success: Bool
    let equipment_history: [EquipmentSubmission]
    let total_submissions: Int
    let error: String?
}

// MARK: - Main View

struct EquipmentView: View {
    @State private var submissions: [EquipmentSubmission] = []
    @State private var isLoading = false
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var showActionSheet = false
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedSubmission: EquipmentSubmission?

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
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                selectedImage = image
                uploadEquipment(image: image)
            }
        }
        .sheet(isPresented: $showGallery) {
            ImagePicker(sourceType: .photoLibrary) { image in
                selectedImage = image
                uploadEquipment(image: image)
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
    }

    // MARK: - Load History

    func loadEquipmentHistory() {
        isLoading = true

        AgentManager.shared.getEquipmentHistory { result in
            DispatchQueue.main.async {
                isLoading = false

                switch result {
                case .success(let response):
                    if response.success {
                        self.submissions = response.equipment_history
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

    func uploadEquipment(image: UIImage) {
        isUploading = true

        AgentManager.shared.sendEquipmentInput(image: image) { result in
            DispatchQueue.main.async {
                isUploading = false

                switch result {
                case .success(let response):
                    if response.success {
                        // Add new submission to the list
                        if let newSubmission = response.submission {
                            self.submissions.insert(newSubmission, at: 0)
                        }
                    } else {
                        self.errorMessage = response.error ?? "Failed to analyze equipment"
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
            // Image
            AsyncImage(url: URL(string: submission.media_url)) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 120)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        )
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 120)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .cornerRadius(10)

            // Equipment Count
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text("\(submission.total_items) items")
                    .font(.caption)
                    .foregroundColor(.white)
            }

            // Environment Badge
            Text(submission.environment.replacingOccurrences(of: "_", with: " ").capitalized)
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
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    )
                            case .empty:
                                ProgressView()
                                    .frame(height: 200)
                            @unknown default:
                                EmptyView()
                            }
                        }

                        // Info Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Environment:")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(submission.environment.replacingOccurrences(of: "_", with: " ").capitalized)
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

struct ImagePicker: UIViewControllerRepresentable {
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
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
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
