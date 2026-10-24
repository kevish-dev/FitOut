import SwiftUI
import UIKit

struct ExerciseArtwork: View {
    let exercise: ExerciseDefinition?
    var size: CGFloat = 56
    var expanded = false

    private var artwork: UIImage? {
        exercise?.imageAssetName.flatMap { UIImage(named: $0) }
    }
    private var presentationRatio: CGFloat {
        guard let artwork else { return 1.5 }
        // Portraits get more height; wide multi-pose guides remain fully visible.
        return min(2.5, max(0.85, artwork.size.width / artwork.size.height))
    }
    var body: some View {
        ZStack {
            FitTheme.surface
            if let artwork {
                Image(uiImage: artwork).resizable().scaledToFit().padding(expanded ? 8 : 2)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: exercise?.category.symbol ?? "dumbbell")
                        .font(.system(size: expanded ? 48 : 22, weight: .regular))
                        .foregroundStyle(FitTheme.dashboardAccent)
                    if expanded {
                        Text(exercise?.isCustom == true ? "Custom exercise" : "Exercise image coming soon").font(FitTheme.medium(13))
                            .foregroundStyle(FitTheme.textSecondary)
                    }
                }
            }
        }
        .frame(width: expanded ? nil : size, height: expanded ? nil : size)
        .aspectRatio(expanded ? presentationRatio : 1, contentMode: .fit)
        .frame(maxWidth: expanded ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 20 : 12))
        .overlay { RoundedRectangle(cornerRadius: expanded ? 20 : 12).strokeBorder(FitTheme.textPrimary.opacity(0.08), lineWidth: 1) }
        .accessibilityHidden(!expanded)
        .accessibilityLabel(artwork == nil ? "Exercise image not yet available" : "\(exercise?.name ?? "Exercise") reference image")
    }
}

/// Outside selection rows, an image can open a fitted, zoomable reference.
/// Library/picker thumbnails stay static so tapping a row still selects the exercise.
struct ExerciseImageButton: View {
    enum Style { case reference, detail, thumbnail(CGFloat), workoutStage(CGFloat) }
    let exercise: ExerciseDefinition?
    var style: Style = .reference
    @State private var showingImage = false

    var body: some View {
        if let exercise, let image = exercise.imageAssetName.flatMap({ UIImage(named: $0) }) {
            Button { showingImage = true } label: {
                switch style {
                case .reference:
                    Label("View exercise image", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(FitTheme.medium(13)).frame(minHeight: 44)
                case .detail:
                    VStack(spacing: 10) {
                        ExerciseArtwork(exercise: exercise, expanded: true)
                        Label("Tap to explore the image", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(FitTheme.medium(12)).padding(.bottom, 4)
                    }
                case .workoutStage(let height):
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity).frame(height: height).padding(.horizontal, 12)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12)).frame(width: 44, height: 44)
                                .dashboardGlass(in: Circle()).padding(10)
                        }
                case .thumbnail(let size):
                    ExerciseArtwork(exercise: exercise, size: size)
                }
            }
            .buttonStyle(.borderless).tint(FitTheme.dashboardAccent)
            .accessibilityLabel("View image for \(exercise.name)")
            .accessibilityHint("Opens a full-screen image you can zoom and pan")
            .fullScreenCover(isPresented: $showingImage) {
                ExerciseImageViewer(exercise: exercise, image: image)
            }
        } else {
            switch style {
            case .reference: EmptyView()
            case .detail: ExerciseArtwork(exercise: exercise, expanded: true)
            case .workoutStage(let height):
                VStack(spacing: 14) {
                    Image(systemName: exercise?.category.symbol ?? "dumbbell").font(.system(size: 52, weight: .light))
                        .foregroundStyle(FitTheme.dashboardAccent)
                    Text("No illustration available").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }.frame(maxWidth: .infinity).frame(height: height)
            case .thumbnail(let size): ExerciseArtwork(exercise: exercise, size: size)
            }
        }
    }
}

private struct ExerciseImageViewer: View {
    let exercise: ExerciseDefinition
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZoomableExerciseImage(image: image, label: "\(exercise.name) reference image")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Pinch to zoom · Drag to explore · Double-tap to reset or zoom")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                    .multilineTextAlignment(.center).padding(FitTheme.pageInset)
            }
            .background(FitTheme.dashboardBackground)
            .navigationTitle(exercise.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(FitTheme.dashboardAccent)
    }
}

private struct ZoomableExerciseImage: UIViewRepresentable {
    let image: UIImage
    let label: String

    func makeUIView(context: Context) -> ExerciseImageScrollView {
        let view = ExerciseImageScrollView()
        view.setImage(image, label: label)
        return view
    }
    func updateUIView(_ view: ExerciseImageScrollView, context: Context) {
        view.setImage(image, label: label)
    }
}

private final class ExerciseImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var fittedSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1; maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Zoom in", target: self, selector: #selector(zoomIn)),
            UIAccessibilityCustomAction(name: "Zoom out", target: self, selector: #selector(zoomOut)),
            UIAccessibilityCustomAction(name: "Reset zoom", target: self, selector: #selector(resetZoom))
        ]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage, label: String) {
        accessibilityLabel = label
        guard imageView.image !== image else { return }
        setZoomScale(1, animated: false)
        imageView.image = image; fittedSize = .zero
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        if fittedSize != bounds.size {
            setZoomScale(1, animated: false)
            let scale = min(max(1, bounds.width - 32) / image.size.width,
                            max(1, bounds.height - 32) / image.size.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            contentSize = imageView.bounds.size
            fittedSize = bounds.size
        }
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        imageView.center = CGPoint(x: max(bounds.width, contentSize.width) / 2,
                                   y: max(bounds.height, contentSize.height) / 2)
    }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1, animated: true); return }
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: true)
    }
    @objc private func zoomIn() -> Bool { setZoomScale(min(maximumZoomScale, zoomScale * 1.5), animated: true); return true }
    @objc private func zoomOut() -> Bool { setZoomScale(max(minimumZoomScale, zoomScale / 1.5), animated: true); return true }
    @objc private func resetZoom() -> Bool { setZoomScale(1, animated: true); return true }
}

struct ExerciseLibraryRow: View {
    let exercise: ExerciseDefinition
    var artworkSize: CGFloat = 56
    var body: some View {
        HStack(spacing: 12) {
            ExerciseArtwork(exercise: exercise, size: artworkSize)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(exercise.name).font(FitTheme.section(15)).foregroundStyle(.primary)
                    if exercise.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(FitTheme.dashboardAccent) }
                }
                Text(exercise.muscles.map(\.title).joined(separator: ", "))
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                Text(exercise.equipment == "None" ? "No equipment" : exercise.equipment)
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }
}
