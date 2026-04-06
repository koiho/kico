import SwiftUI
import AVFoundation
import Combine
import CoreMotion

// MARK: - Camera Preview
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onPreviewLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        view.onPreviewLayerReady = onPreviewLayerReady
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.session = session
        uiView.onPreviewLayerReady = onPreviewLayerReady
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        var session: AVCaptureSession? {
            didSet {
                previewLayer.session = session
                previewLayer.videoGravity = .resizeAspectFill
            }
        }

        var onPreviewLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)? {
            didSet {
                onPreviewLayerReady?(previewLayer)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onPreviewLayerReady?(previewLayer)
        }
    }
}

// MARK: - Device Orientation Observer
class DeviceOrientationObserver: ObservableObject {
    var rotationAngle: Double = 0 {
        willSet { objectWillChange.send() }
    }

    private let motionManager = CMMotionManager()
    private var smoothAngle: Double = 0

    init() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        startUpdates()
    }

    private func startUpdates() {
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion, let self else { return }

            let g = motion.gravity
            let horizontalMag = sqrt(g.x * g.x + g.y * g.y)
            guard horizontalMag > 0.4 else {
                // Phone is flat — reset rotation to nearest equivalent of 0
                let target = round(self.rotationAngle / 360) * 360
                if abs(target - self.rotationAngle) > 0.01 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.rotationAngle = target
                    }
                    self.smoothAngle = 0
                }
                return
            }

            let raw = atan2(-g.x, -g.y) * 180.0 / .pi

            // 圆周低通滤波：用向量平均避免 ±180° 边界处跳变
            let α = 0.08
            let sRad = self.smoothAngle * .pi / 180.0
            let rRad = raw * .pi / 180.0
            let nx = cos(sRad) * (1 - α) + cos(rRad) * α
            let ny = sin(sRad) * (1 - α) + sin(rRad) * α
            self.smoothAngle = atan2(ny, nx) * 180.0 / .pi

            // 吸附到最近的 90° 整数倍
            let snapped = round(self.smoothAngle / 90.0) * 90.0

            // 找到与当前累计角度最接近的等价角度
            let current = self.rotationAngle
            let base = round(current / 360) * 360
            let candidates = [base + snapped, base + snapped + 360, base + snapped - 360]
            let target = candidates.min(by: { abs($0 - current) < abs($1 - current) })!

            guard abs(target - current) > 0.01 else { return }

            withAnimation(.easeInOut(duration: 0.3)) {
                self.rotationAngle = target
            }
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - Camera Screen
struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var orientationObserver = DeviceOrientationObserver()
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var referenceImageStore: ReferenceImageStore
    @State private var isFocusIndicatorVisible = false
    @State private var focusIndicatorScale: CGFloat = 1
    @State private var focusAnimationToken = UUID()
    @State private var sliderGestureBaseEV: Float?
    @State private var previewDragBaseEV: Float?
    @State private var isAdjustingExposure = false
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var isFocusing = false
    @State private var flashPhase: Double = 0
    @State private var showGallery = false
    @State private var showProfile = false
    @State private var showImportReference = false
    private var rotationAngle: Double {
        orientationObserver.rotationAngle
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                // Camera preview — 4:3, pinned to screen top
                ZStack(alignment: .bottomTrailing) {
                    GeometryReader { previewGeo in
                        CameraPreviewView(
                            session: viewModel.camera.session,
                            onPreviewLayerReady: { layer in
                                DispatchQueue.main.async {
                                    viewModel.attachPreviewLayer(layer)
                                    if previewLayer !== layer {
                                        previewLayer = layer
                                    }
                                }
                            }
                        )
                            .frame(width: previewGeo.size.width, height: previewGeo.size.height)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        let location = value.location
                                        let indicatorPoint = CGPoint(
                                            x: location.x / max(previewGeo.size.width, 1),
                                            y: location.y / max(previewGeo.size.height, 1)
                                        )

                                        viewModel.focus(indicatorPoint: indicatorPoint, devicePoint: indicatorPoint)
                                        isAdjustingExposure = false
                                        previewDragBaseEV = nil
                                        showFocusIndicatorTemporarily()
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        guard isFocusIndicatorVisible,
                                              viewModel.state.focusPointInPreview != nil else { return }

                                        isAdjustingExposure = true

                                        if previewDragBaseEV == nil {
                                            previewDragBaseEV = viewModel.state.exposureEV
                                        }

                                        let rotation = rotationAngle.truncatingRemainder(dividingBy: 360)
                                        let verticalDrag: CGFloat

                                        if rotation == 0 || rotation == 360 || rotation == -360 {
                                            verticalDrag = -value.translation.height
                                        } else if rotation == 90 || rotation == -270 {
                                            verticalDrag = value.translation.width
                                        } else if rotation == -90 || rotation == 270 {
                                            verticalDrag = -value.translation.width
                                        } else {
                                            verticalDrag = -value.translation.height
                                        }

                                        let raw = Float(verticalDrag / 220.0)
                                        let damped = dampedExposureDelta(raw)
                                        let range = viewModel.state.exposureMaxEV - viewModel.state.exposureMinEV
                                        let base = previewDragBaseEV ?? viewModel.state.exposureEV
                                        viewModel.setExposureEV(base + damped * range)
                                    }
                                    .onEnded { _ in
                                        guard isFocusIndicatorVisible else { return }
                                        isAdjustingExposure = false
                                        previewDragBaseEV = nil
                                        showFocusIndicatorTemporarily()
                                    }
                            )
                    }
                    .frame(width: geo.size.width,
                           height: geo.size.height * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    if viewModel.state.isSwitchingCamera {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black)
                            .frame(width: geo.size.width, height: geo.size.height * 0.75)
                            .transition(.opacity)
                    }

                    if let focusPoint = viewModel.state.focusPointInPreview {
                        focusIndicator(at: focusPoint, scale: focusIndicatorScale, opacity: flashPhase)
                            .id("\(focusPoint.x)_\(focusPoint.y)")
                            .opacity(isFocusIndicatorVisible ? 1 : 0)
                            .animation(.easeOut(duration: 0.15), value: focusIndicatorScale)
                            .animation(.linear(duration: 0.03), value: flashPhase)
                    }

                    HStack(alignment: .center) {
                        HStack(spacing: 4) {
                            ForEach(viewModel.camera.supportedZoomFactors, id: \.self) { factor in
                                zoomButton(factor: factor)
                            }
                        }
                        .padding(4)
                        .background(Color(white: 0.38).opacity(0.85), in: Capsule())

                        Spacer(minLength: 0)

                        VStack(spacing: 8) {
                            Button(action: {
                                showProfile = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 32, height: 32)

                                    // Show user avatar if available, otherwise show default icon
                                    if let avatarImage = authManager.avatarImage {
                                        Image(uiImage: avatarImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                }
                                .rotationEffect(.degrees(rotationAngle))
                                .frame(width: 32, height: 32)
                            }
                        }
                        .frame(width: 60, alignment: .center)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(width: geo.size.width,
                       height: geo.size.height * 0.75 + geo.safeAreaInsets.top)
                .offset(y: -geo.safeAreaInsets.top)

                // Bottom controls — top row near edge, second row centered
                ZStack {
                    HStack(spacing: 0) {
                        thumbnailView
                            .frame(width: 60)

                        Spacer(minLength: 0)

                        shutterButton
                            .frame(width: 60)

                        Spacer(minLength: 0)

                        filterButton
                            .frame(width: 60)
                    }
                    .offset(y: 15)

                    VStack {
                        HStack(spacing: 0) {
                            edgeIconButton(systemName: viewModel.state.flashMode.systemName, iconSize: 22, rotate: true) {
                                viewModel.toggleFlash()
                            }
                                .frame(width: 60)
                                .opacity(viewModel.camera.isFlashAvailable() ? 1.0 : 0.3)
                                .disabled(!viewModel.camera.isFlashAvailable())

                            Spacer(minLength: 0)

                            edgeIconButton(systemName: "sparkles", iconSize: 22, rotate: true) {}
                                .frame(width: 60)

                            Spacer(minLength: 0)

                            edgeIconButton(systemName: "arrow.clockwise", iconSize: 22, rotate: true) { viewModel.flipCamera() }
                                .frame(width: 60)
                        }
                        .padding(.top, 4)

                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: geo.size.height - geo.size.height * 0.75, alignment: .top)
                .padding(.bottom, 40)
                .offset(y: geo.size.height * 0.75 + 14)
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            ToastHost()
        }
        .fullScreenCover(isPresented: $showGallery) {
            GalleryView(photos: viewModel.state.photos)
        }
        .fullScreenCover(isPresented: $showProfile) {
            ProfileView()
        }
        .fullScreenCover(isPresented: $showImportReference) {
            ImportReferenceView()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: viewModel.toastErrorMessage) { _, message in
            guard let message else { return }
            toastCenter.showError(message, source: .camera)
            viewModel.toastErrorMessage = nil
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnailView: some View {
        Button {
            showGallery = true
        } label: {
            ZStack {
                if let photo = viewModel.state.lastPhotoThumbnail {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .rotationEffect(.degrees(rotationAngle))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                }
            }
        }
    }

    private var shutterButton: some View {
        let requiresReference = CaptureWorkflowConfiguration.mode == .renderTest
            && CaptureWorkflowConfiguration.renderRequiresReferenceImage
        let canCapture = viewModel.state.isSessionReady
            && (!requiresReference || referenceImageStore.selectedImage != nil)

        return Button(action: { viewModel.capturePhoto(referenceImage: referenceImageStore.selectedImage) }) {
            ZStack {
                Circle()
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(canCapture ? Color.white : Color.gray.opacity(0.5))
                    .frame(width: 64, height: 64)
            }
        }
        .disabled(!canCapture)
    }

    // MARK: - Subviews

    // MARK: - Zoom Buttons

    // MARK: - Zoom Buttons

    /// 精确判断哪个缩放按钮应该被激活
    private func isZoomButtonActive(factor: CGFloat, currentZoom: CGFloat) -> Bool {
        let factors = viewModel.camera.supportedZoomFactors.sorted()
        guard let idx = factors.firstIndex(where: { abs($0 - factor) < 0.01 }) else { return false }
        let next = idx + 1 < factors.count ? factors[idx + 1] : CGFloat.infinity
        return currentZoom >= factor && currentZoom < next
    }

    private func zoomButton(factor: CGFloat) -> some View {
        let displayZoom = viewModel.state.displayZoomFactor
        let isActive = isZoomButtonActive(factor: factor, currentZoom: displayZoom)
        let label = isActive ? zoomLabel(for: displayZoom) : zoomLabel(for: factor)

        return Button(action: {
            viewModel.selectZoom(factor)
        }) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isActive ? Color(red: 1, green: 0.3, blue: 0.3) : .white)
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(rotationAngle))
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(isActive ? AnyView(Capsule().fill(Color(white: 0.18))) : AnyView(Color.clear))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func zoomLabel(for factor: CGFloat) -> String {
        // Truncate to 1 decimal place (don't round up, e.g. 0.96 → "0.9" not "1.0")
        let truncated = (factor * 10).rounded(.down) / 10
        let s = String(format: "%.1f", truncated)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "×"
    }

    private func focusIndicator(at point: CGPoint, scale: CGFloat = 1, opacity: Double = 1) -> some View {
        GeometryReader { container in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white, lineWidth: 1.8)
                    .opacity(opacity)
                    .frame(width: 62, height: 62)

                focusExposureSlider
            }
            .rotationEffect(.degrees(rotationAngle))
            .scaleEffect(scale, anchor: .center)
            .position(x: point.x * container.size.width, y: point.y * container.size.height)
        }
    }

    private var focusExposureSlider: some View {
        GeometryReader { gaugeGeo in
            VStack(spacing: 0) {
                // Top segment (positive exposure)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: gaugeGeo.size.height * 0.4)

                // EV value in middle - no background
                Text(evDisplayString)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(height: 16)

                // Bottom segment (negative exposure)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: gaugeGeo.size.height * 0.4)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isFocusIndicatorVisible else { return }

                        isAdjustingExposure = true

                        if sliderGestureBaseEV == nil {
                            sliderGestureBaseEV = viewModel.state.exposureEV
                        }

                        // Calculate drag distance in the correct direction based on device rotation
                        let rotation = rotationAngle.truncatingRemainder(dividingBy: 360)
                        let verticalDrag: CGFloat

                        if rotation == 0 || rotation == 360 || rotation == -360 {
                            // Portrait: use height directly
                            verticalDrag = -value.translation.height
                        } else if rotation == 90 || rotation == -270 {
                            // Landscape rotated 90°: width becomes height (inverted)
                            verticalDrag = value.translation.width
                        } else if rotation == -90 || rotation == 270 {
                            // Landscape rotated -90°/270°: negative width becomes height
                            verticalDrag = -value.translation.width
                        } else {
                            // Fallback for intermediate angles
                            verticalDrag = -value.translation.height
                        }

                        let raw = Float(verticalDrag / 220.0)
                        let damped = dampedExposureDelta(raw)
                        let range = viewModel.state.exposureMaxEV - viewModel.state.exposureMinEV
                        let base = sliderGestureBaseEV ?? viewModel.state.exposureEV
                        viewModel.setExposureEV(base + damped * range)
                    }
                    .onEnded { _ in
                        guard isFocusIndicatorVisible else { return }
                        isAdjustingExposure = false
                        sliderGestureBaseEV = nil
                        showFocusIndicatorTemporarily()
                    }
            )
        }
        .frame(width: 24, height: 80)
    }

    private var evDisplayString: String {
        formatExposureEV(viewModel.state.exposureEV, alwaysShowSign: true)
    }

    private var exposureNormalizedValue: CGFloat {
        let minEV = viewModel.state.exposureMinEV
        let maxEV = viewModel.state.exposureMaxEV
        guard maxEV > minEV else { return 0.5 }
        let normalized = (viewModel.state.exposureEV - minEV) / (maxEV - minEV)
        return CGFloat(Swift.max(0, Swift.min(1, normalized)))
    }

    private func dampedExposureDelta(_ raw: Float) -> Float {
        let sign: Float = raw >= 0 ? 1 : -1
        let magnitude = abs(raw)
        let dampedMagnitude = pow(min(magnitude, 1.8), 0.78)
        return sign * dampedMagnitude
    }

    private func formatExposureEV(_ value: Float, alwaysShowSign: Bool = false) -> String {
        let normalized = abs(value) < 0.05 ? 0 : value
        if alwaysShowSign, normalized != 0 {
            return String(format: "%+.1f", normalized)
        }
        return String(format: "%.1f", normalized)
    }

    private func showFocusIndicatorTemporarily() {
        let token = UUID()
        focusAnimationToken = token

        focusIndicatorScale = 1.15
        isFocusIndicatorVisible = true
        isFocusing = true

        Task { @MainActor in
            // Quick scale-down animation like system camera
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard focusAnimationToken == token else { return }
            focusIndicatorScale = 1.0

            // Animate flash during focus (750ms focus time)
            let focusStartTime = Date()
            while isFocusing && Date().timeIntervalSince(focusStartTime) < 0.75 {
                let elapsed = Date().timeIntervalSince(focusStartTime)
                // Slower, more natural opacity pulse: 0.7 to 1.0
                flashPhase = 0.7 + 0.3 * sin(elapsed * 8)
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30fps
            }

            // Focus complete
            guard focusAnimationToken == token else { return }
            isFocusing = false
            flashPhase = 1.0

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard focusAnimationToken == token else { return }
            guard !isAdjustingExposure else { return }
            isFocusIndicatorVisible = false
            sliderGestureBaseEV = nil
            previewDragBaseEV = nil
        }
    }

    private func triggerFocusFlash() {
        // Flash effect is now handled in showFocusIndicatorTemporarily
    }

    private var exposureControl: some View {
        VStack(spacing: 4) {
            Text("EV \(formatExposureEV(viewModel.state.exposureEV, alwaysShowSign: true))")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)

            HStack(spacing: 6) {
                circleButton(systemName: "minus", size: 28, iconSize: 11) {
                    let next = max(viewModel.state.exposureMinEV, viewModel.state.exposureEV - 0.2)
                    viewModel.setExposureEV(next)
                }
                circleButton(systemName: "plus", size: 28, iconSize: 11) {
                    let next = min(viewModel.state.exposureMaxEV, viewModel.state.exposureEV + 0.2)
                    viewModel.setExposureEV(next)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func circleButton(systemName: String,
                               size: CGFloat = 44,
                               iconSize: CGFloat = 16,
                               rotate: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(rotate ? rotationAngle : 0))
                .frame(width: size, height: size)
        }
    }

    private func edgeIconButton(systemName: String,
                                iconSize: CGFloat = 20,
                                rotate: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(rotate ? rotationAngle : 0))
                .frame(width: 36, height: 36)
        }
    }

    private var filterButton: some View {
        Button(action: {
            showImportReference = true
        }) {
            VStack(spacing: 4) {
                if let referenceImage = referenceImageStore.selectedImage {
                    Image(uiImage: referenceImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }

                Text(referenceImageStore.selectedImage == nil ? "导入参考" : "参考已选")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
            }
            .rotationEffect(.degrees(rotationAngle))
            .frame(width: 60, height: 60)
            .background(Color.gray.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Zoom Gesture Helpers

    /// Snap to standard zoom values when close
    /// Standard values: 0.5, 1.0, 2.0, 3.0
    private func snapToStandardZoom(_ zoom: CGFloat, aggressive: Bool = false) -> CGFloat {
        let standardValues: [CGFloat] = [0.5, 1.0, 2.0, 3.0]

        // Snap radius: how close to trigger snap
        let snapRadius: CGFloat = aggressive ? 0.15 : 0.08

        for standard in standardValues {
            if abs(zoom - standard) < snapRadius {
                return standard
            }
        }

        // Not close enough to snap, return original
        return zoom
    }
}
