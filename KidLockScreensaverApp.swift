import SwiftUI
import UIKit
import AudioToolbox

// MARK: - 1. 遥控器按键定义 (支持持久化的组合键元素)
enum RemoteKey: String, Codable, CaseIterable, Identifiable {
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
    case select = "SELECT"
    case playPause = "PLAY_PAUSE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .select: return "确认"
        case .playPause: return "播放/暂停"
        }
    }

    var systemIcon: String {
        switch self {
        case .up: return "arrow.up.circle.fill"
        case .down: return "arrow.down.circle.fill"
        case .left: return "arrow.left.circle.fill"
        case .right: return "arrow.right.circle.fill"
        case .select: return "circle.inset.filled"
        case .playPause: return "playpause.circle.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .up: return .cyan
        case .down: return .blue
        case .left: return .purple
        case .right: return .indigo
        case .select: return .orange
        case .playPause: return .green
        }
    }

    static func from(pressType: UIPress.PressType) -> RemoteKey? {
        switch pressType {
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .select: return .select
        case .playPause: return .playPause
        default: return nil
        }
    }
}

// MARK: - 2. 互动屏保主题定义
enum ScreensaverTheme: String, CaseIterable, Identifiable {
    case ocean = "深海奇遇"
    case space = "星际漫游"
    case candy = "糖果乐园"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .ocean: return "按遥控器召唤发光水母与彩色气泡"
        case .space: return "按遥控器发射星际烟花与小火箭"
        case .candy: return "按遥控器弹出缤纷糖果与音符"
        }
    }

    var centerIcon: String {
        switch self {
        case .ocean: return "tortoise.fill"
        case .space: return "sparkles"
        case .candy: return "balloon.2.fill"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .ocean:
            return [Color(red: 0.02, green: 0.08, blue: 0.22), Color(red: 0.04, green: 0.24, blue: 0.38)]
        case .space:
            return [Color(red: 0.05, green: 0.03, blue: 0.15), Color(red: 0.16, green: 0.06, blue: 0.28)]
        case .candy:
            return [Color(red: 0.18, green: 0.06, blue: 0.22), Color(red: 0.08, green: 0.18, blue: 0.28)]
        }
    }

    var particleSymbols: [String] {
        switch self {
        case .ocean:
            return ["drop.fill", "circle.fill", "seal.fill", "fish.fill", "sparkle"]
        case .space:
            return ["star.fill", "sparkles", "moon.stars.fill", "bolt.fill", "globe.americas.fill"]
        case .candy:
            return ["heart.fill", "star.fill", "music.note", "balloon.fill", "sun.max.fill"]
        }
    }
}

// MARK: - 3. 互动粒子模型 (小孩乱按时触发的视觉反馈)
struct BurstParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let symbol: String
    let color: Color
    let size: CGFloat
    let createdAt: Date = Date()
}

// MARK: - 4. 核心状态管理器 (处理组合键匹配、录制与持久化)
@MainActor
final class KidLockViewModel: ObservableObject {
    enum Mode {
        case unlocked          // 家长设置控制台
        case recordingCombo    // 正在录制自定义组合键
        case locked            // 儿童防误触互动屏保模式
    }

    @Published var mode: Mode = .unlocked {
        didSet {
            // 锁屏期间禁止系统休眠或弹出系统默认屏保
            UIApplication.shared.isIdleTimerDisabled = (mode == .locked)
            inputBuffer.removeAll()
            matchedPrefixCount = 0
        }
    }

    @Published var savedCombo: [RemoteKey] = []
    @Published var recordingBuffer: [RemoteKey] = []
    @Published var matchedPrefixCount: Int = 0
    @Published var selectedTheme: ScreensaverTheme = .ocean
    @Published var soundEffectsEnabled: Bool = true
    @Published var showUnlockHintDots: Bool = true

    // 互动屏保状态
    @Published var particles: [BurstParticle] = []
    @Published var mascotScale: CGFloat = 1.0
    @Published var mascotRotation: Double = 0.0
    @Published var lastPressedKeyName: String = "等待按键..."
    @Published var kidPressCounter: Int = 0
    @Published var statusBanner: String? = nil

    private var inputBuffer: [RemoteKey] = []
    private var lastInputTime: Date = .distantPast
    private let comboTimeoutSeconds: TimeInterval = 4.0
    private let storageKey = "com.kidlock.savedRemoteCombo.v1"

    static let defaultCombo: [RemoteKey] = [.up, .up, .down, .down, .playPause]

    init() {
        loadSavedCombo()
    }

    func loadSavedCombo() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RemoteKey].self, from: data),
           decoded.count >= 3 {
            savedCombo = decoded
        } else {
            savedCombo = Self.defaultCombo
        }
    }

    func saveCombo(_ newCombo: [RemoteKey]) {
        guard newCombo.count >= 3 else { return }
        savedCombo = newCombo
        if let data = try? JSONEncoder().encode(newCombo) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        showTemporaryBanner("已保存新组合键（共 \(newCombo.count) 步）")
    }

    func resetToDefaultCombo() {
        saveCombo(Self.defaultCombo)
    }

    func startRecording() {
        recordingBuffer.removeAll()
        mode = .recordingCombo
    }

    func cancelRecording() {
        recordingBuffer.removeAll()
        mode = .unlocked
    }

    func finishRecording() {
        guard recordingBuffer.count >= 3 else { return }
        saveCombo(recordingBuffer)
        recordingBuffer.removeAll()
        mode = .unlocked
    }

    // 处理遥控器按键输入（在锁定模式或录制模式下调用）
    func handleRemotePress(pressType: UIPress.PressType) {
        switch mode {
        case .recordingCombo:
            handleRecordingInput(pressType: pressType)
        case .locked:
            handleLockedInput(pressType: pressType)
        case .unlocked:
            break
        }
    }

    // 处理触摸板滑动手势（让小孩滑动触摸板也有趣味粒子反馈）
    func handleTouchpadSwipe(direction: UISwipeGestureRecognizer.Direction) {
        guard mode == .locked else { return }
        spawnKidFeedback(label: "轻扫互动")
    }

    private func handleRecordingInput(pressType: UIPress.PressType) {
        // 在录制模式下：按返回键(Menu)取消录制
        if pressType == .menu {
            cancelRecording()
            return
        }

        guard let key = RemoteKey.from(pressType: pressType) else { return }

        if soundEffectsEnabled {
            AudioServicesPlaySystemSound(1104)
        }

        if recordingBuffer.count < 8 {
            recordingBuffer.append(key)
        }
    }

    private func handleLockedInput(pressType: UIPress.PressType) {
        // 1. 无论按什么键（包括 Menu 返回键），都给小孩展示有趣的动画反馈
        let keyLabel = RemoteKey.from(pressType: pressType)?.displayName ?? "返回/菜单"
        spawnKidFeedback(label: keyLabel)

        // 2. 如果是 Menu 键，直接拦截，不计入组合键但清空错误前缀
        guard let key = RemoteKey.from(pressType: pressType) else {
            inputBuffer.removeAll()
            matchedPrefixCount = 0
            return
        }

        // 3. 检查两次按键间隔是否超时（超过 4 秒自动重置序列）
        let now = Date()
        if now.timeIntervalSince(lastInputTime) > comboTimeoutSeconds {
            inputBuffer.removeAll()
        }
        lastInputTime = now

        // 4. 将当前按键加入滑动窗口缓冲区
        inputBuffer.append(key)
        if inputBuffer.count > savedCombo.count {
            inputBuffer.removeFirst(inputBuffer.count - savedCombo.count)
        }

        // 5. 计算当前已匹配的前缀长度（方便右上角微光圆点提示家长）
        updateMatchedPrefix()

        // 6. 如果完整匹配组合键，立即解锁！
        if inputBuffer == savedCombo {
            if soundEffectsEnabled {
                AudioServicesPlaySystemSound(1025)
            }
            mode = .unlocked
            showTemporaryBanner("已通过组合键成功解锁")
        }
    }

    private func updateMatchedPrefix() {
        let target = savedCombo
        var bestMatch = 0
        for length in stride(from: min(inputBuffer.count, target.count), through: 1, by: -1) {
            let suffix = Array(inputBuffer.suffix(length))
            let prefix = Array(target.prefix(length))
            if suffix == prefix {
                bestMatch = length
                break
            }
        }
        matchedPrefixCount = bestMatch
    }

    private func spawnKidFeedback(label: String) {
        kidPressCounter += 1
        lastPressedKeyName = label

        if soundEffectsEnabled {
            AudioServicesPlaySystemSound(1103)
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) {
            mascotScale = 1.28
            mascotRotation += Double.random(in: -25...25)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                self?.mascotScale = 1.0
            }
        }

        let palette: [Color] = [.pink, .yellow, .cyan, .green, .orange, .purple, .mint]
        let symbols = selectedTheme.particleSymbols

        // 每次按键生成 4 个趣味粒子
        for _ in 0..<4 {
            let newParticle = BurstParticle(
                x: CGFloat.random(in: 180...1740),
                y: CGFloat.random(in: 140...940),
                symbol: symbols.randomElement() ?? "star.fill",
                color: palette.randomElement() ?? .yellow,
                size: CGFloat.random(in: 42...88)
            )
            particles.append(newParticle)
        }

        // 保持屏幕上最多 36 个粒子，保证动画流畅
        if particles.count > 36 {
            particles.removeFirst(particles.count - 36)
        }
    }

    private func showTemporaryBanner(_ text: String) {
        statusBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.statusBanner == text {
                self?.statusBanner = nil
            }
        }
    }
}

// MARK: - 5. UIKit 底层遥控器事件拦截器 (彻底解决 SwiftUI onMoveCommand 漏键与 Menu 退出问题)
struct RemoteKeyInterceptorView: UIViewControllerRepresentable {
    var onKeyPress: (UIPress.PressType) -> Void
    var onSwipe: (UISwipeGestureRecognizer.Direction) -> Void

    func makeUIViewController(context: Context) -> RemoteCaptureViewController {
        let controller = RemoteCaptureViewController()
        controller.onKeyPress = onKeyPress
        controller.onSwipe = onSwipe
        return controller
    }

    func updateUIViewController(_ uiViewController: RemoteCaptureViewController, context: Context) {
        uiViewController.onKeyPress = onKeyPress
        uiViewController.onSwipe = onSwipe
        uiViewController.ensureFirstResponder()
    }
}

final class RemoteCaptureViewController: UIViewController {
    var onKeyPress: ((UIPress.PressType) -> Void)?
    var onSwipe: ((UISwipeGestureRecognizer.Direction) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // 拦截 Menu (返回) 键，防止系统将应用退回 Apple TV 主屏幕
        let menuTap = UITapGestureRecognizer(target: self, action: #selector(handleMenuButton))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(menuTap)

        // 支持触摸板四向滑动互动
        let directions: [UISwipeGestureRecognizer.Direction] = [.up, .down, .left, .right]
        for direction in directions {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ensureFirstResponder()
    }

    func ensureFirstResponder() {
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }

    @objc private func handleMenuButton() {
        onKeyPress?(.menu)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        onSwipe?(gesture.direction)
    }

    // 拦截方向键、确认键、播放/暂停键等所有物理按键，不向系统传递
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            onKeyPress?(press.type)
        }
        // 注意：故意不调用 super.pressesBegan，防止系统默认焦点跳转或退出应用
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // 吞掉按键结束事件
    }
}

// MARK: - 6. 主界面视图 (根据状态切换家长控制台、录制器与童锁屏保)
struct ContentView: View {
    @StateObject private var viewModel = KidLockViewModel()

    var body: some View {
        ZStack {
            switch viewModel.mode {
            case .unlocked:
                ParentDashboardView(viewModel: viewModel)
            case .recordingCombo:
                ComboRecorderOverlayView(viewModel: viewModel)
            case .locked:
                LockedScreensaverView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - 7. 家长设置控制台视图
struct ParentDashboardView: View {
    @ObservedObject var viewModel: KidLockViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.12, green: 0.16, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 34) {
                // 顶部标题栏
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 46))
                                .foregroundColor(.cyan)
                            Text("Apple TV 童锁与防误触互动屏保")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("开启后将拦截遥控器方向键、确认键、播放键与返回键，仅按您的专属组合键才可解锁")
                            .font(.system(size: 23))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()

                    if let banner = viewModel.statusBanner {
                        Text(banner)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }

                // 当前组合键展示卡片
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("当前解锁组合键序列（依序按下即可解锁）：")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Text("共 \(viewModel.savedCombo.count) 步 · 4 秒内连按有效")
                            .font(.system(size: 20))
                            .foregroundColor(.cyan)
                    }

                    HStack(spacing: 18) {
                        ForEach(Array(viewModel.savedCombo.enumerated()), id: \.offset) { index, key in
                            HStack(spacing: 12) {
                                KeyBadgeView(key: key, stepNumber: index + 1)
                                if index < viewModel.savedCombo.count - 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                        }
                    }
                }
                .padding(30)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                // 核心操作按钮区
                HStack(spacing: 28) {
                    Button {
                        viewModel.mode = .locked
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 32))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("立即开启童锁屏保")
                                    .font(.system(size: 28, weight: .bold))
                                Text("或随时按遥控器【播放/暂停键】快速锁屏")
                                    .font(.system(size: 18))
                                    .opacity(0.8)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 22)
                    }

                    Button {
                        viewModel.startRecording()
                    } label: {
                        Label("自定义组合键", systemImage: "slider.horizontal.3")
                            .font(.system(size: 26, weight: .semibold))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 22)
                    }

                    Button {
                        viewModel.resetToDefaultCombo()
                    } label: {
                        Label("恢复默认组合", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 24))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 22)
                    }
                }

                // 屏保主题与辅助设置区
                HStack(spacing: 28) {
                    ForEach(ScreensaverTheme.allCases) { theme in
                        Button {
                            viewModel.selectedTheme = theme
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: theme.centerIcon)
                                        .font(.system(size: 28))
                                        .foregroundColor(.yellow)
                                    Text(theme.rawValue)
                                        .font(.system(size: 25, weight: .bold))
                                    Spacer()
                                    if viewModel.selectedTheme == theme {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 26))
                                            .foregroundColor(.green)
                                    }
                                }
                                Text(theme.subtitle)
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(2)
                            }
                            .frame(width: 360, alignment: .leading)
                            .padding(20)
                        }
                    }

                    VStack(spacing: 16) {
                        Button {
                            viewModel.soundEffectsEnabled.toggle()
                        } label: {
                            HStack {
                                Image(systemName: viewModel.soundEffectsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                Text(viewModel.soundEffectsEnabled ? "按键音效：开启" : "按键音效：静音")
                            }
                            .font(.system(size: 22))
                            .frame(width: 280)
                            .padding(.vertical, 10)
                        }

                        Button {
                            viewModel.showUnlockHintDots.toggle()
                        } label: {
                            HStack {
                                Image(systemName: viewModel.showUnlockHintDots ? "eye.fill" : "eye.slash.fill")
                                Text(viewModel.showUnlockHintDots ? "解锁进度点：显示" : "解锁进度点：隐藏")
                            }
                            .font(.system(size: 22))
                            .frame(width: 280)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(60)
        }
        // 在家长界面按播放/暂停键也可以一键快速进入锁屏
        .onPlayPauseCommand {
            viewModel.mode = .locked
        }
    }
}

// MARK: - 8. 自定义组合键录制弹窗视图
struct ComboRecorderOverlayView: View {
    @ObservedObject var viewModel: KidLockViewModel

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.12)
                .ignoresSafeArea()

            // 底层挂载按键捕获器，直接读取遥控器输入
            RemoteKeyInterceptorView(
                onKeyPress: { pressType in
                    viewModel.handleRemotePress(pressType: pressType)
                },
                onSwipe: { _ in }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)

            VStack(spacing: 36) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.red)

                Text("请依次按下遥控器按键录制新组合")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)

                Text("支持：上、下、左、右、中间确认键、播放/暂停键（建议录制 4~6 步）")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.75))

                // 实时显示已录制的按键序列
                HStack(spacing: 18) {
                    if viewModel.recordingBuffer.isEmpty {
                        Text("等待按下第一个键...")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.vertical, 28)
                    } else {
                        ForEach(Array(viewModel.recordingBuffer.enumerated()), id: \.offset) { index, key in
                            KeyBadgeView(key: key, stepNumber: index + 1)
                        }
                    }
                }
                .padding(32)
                .frame(minWidth: 900, minHeight: 150)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                // 底部提示（自动满 5 步或手动保存说明）
                VStack(spacing: 14) {
                    if viewModel.recordingBuffer.count >= 3 {
                        Text("已满 \(viewModel.recordingBuffer.count) 步！将在停止按键 2.5 秒后自动保存，或继续按键（最多 8 步）")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.green)
                    } else {
                        Text("至少需要录制 3 个按键（当前 \(viewModel.recordingBuffer.count) / 3）")
                            .font(.system(size: 24))
                            .foregroundColor(.yellow)
                    }

                    Text("随时按遥控器【返回键 (< / MENU)】可取消本次录制")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(60)
        }
        .onChange(of: viewModel.recordingBuffer) { newBuffer in
            // 当录制达到至少 4 步且停顿 2.5 秒未继续按键，或满 8 步时自动完成保存
            guard newBuffer.count >= 4 else { return }
            if newBuffer.count >= 8 {
                viewModel.finishRecording()
                return
            }
            let snapshotCount = newBuffer.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if viewModel.mode == .recordingCombo && viewModel.recordingBuffer.count == snapshotCount {
                    viewModel.finishRecording()
                }
            }
        }
    }
}

// MARK: - 9. 防误触儿童互动屏保视图 (锁定状态)
struct LockedScreensaverView: View {
    @ObservedObject var viewModel: KidLockViewModel

    var body: some View {
        ZStack {
            // 主题渐变背景
            LinearGradient(
                colors: viewModel.selectedTheme.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 挂载全屏遥控器按键与手势拦截器
            RemoteKeyInterceptorView(
                onKeyPress: { pressType in
                    viewModel.handleRemotePress(pressType: pressType)
                },
                onSwipe: { direction in
                    viewModel.handleTouchpadSwipe(direction: direction)
                }
            )
            .ignoresSafeArea()

            // 绽放的趣味粒子层
            ForEach(viewModel.particles) { particle in
                Image(systemName: particle.symbol)
                    .font(.system(size: particle.size))
                    .foregroundColor(particle.color.opacity(0.85))
                    .position(x: particle.x, y: particle.y)
                    .transition(.scale.combined(with: .opacity))
            }

            // 中心互动吉祥物与趣味计数
            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 260, height: 260)

                    Image(systemName: viewModel.selectedTheme.centerIcon)
                        .font(.system(size: 120))
                        .foregroundColor(.yellow)
                        .scaleEffect(viewModel.mascotScale)
                        .rotationEffect(.degrees(viewModel.mascotRotation))
                }

                Text(viewModel.selectedTheme.rawValue)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)

                Text("宝贝互动次数：\(viewModel.kidPressCounter) 次 · 最近触发：\(viewModel.lastPressedKeyName)")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.25))
                    .clipShape(Capsule())
            }

            // 右上角极低调的家长组合键解锁进度指示器
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18))
                        Text("童锁保护中")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.25))
                    .clipShape(Capsule())

                    Spacer()

                    if viewModel.showUnlockHintDots {
                        HStack(spacing: 10) {
                            ForEach(0..<viewModel.savedCombo.count, id: \.self) { index in
                                Circle()
                                    .fill(index < viewModel.matchedPrefixCount ? Color.green : Color.white.opacity(0.22))
                                    .frame(width: 14, height: 14)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                    }
                }
                .padding(44)
                Spacer()
            }
        }
    }
}

// MARK: - 10. 组合键步骤徽章组件
struct KeyBadgeView: View {
    let key: RemoteKey
    let stepNumber: Int

    var body: some View {
        VStack(spacing: 8) {
            Text("第 \(stepNumber) 步")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.65))

            Image(systemName: key.systemIcon)
                .font(.system(size: 40))
                .foregroundColor(.white)

            Text(key.displayName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 120, height: 125)
        .background(key.badgeColor.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - 11. 应用入口
@main
struct KidLockScreensaverApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
