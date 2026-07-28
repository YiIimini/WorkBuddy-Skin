import Cocoa
import UniformTypeIdentifiers

// ─── 颜色扩展 ──────────────────────────────────────────────
extension NSColor {
    static let bgDark = NSColor(red: 0.06, green: 0.04, blue: 0.10, alpha: 1.0)
    static let bgCard = NSColor(red: 0.12, green: 0.08, blue: 0.18, alpha: 0.9)
    static let bgCardHover = NSColor(red: 0.16, green: 0.10, blue: 0.24, alpha: 0.9)
    static let accentPink = NSColor(red: 1.0, green: 0.42, blue: 0.65, alpha: 1.0)
    static let accentPurple = NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1.0)
    static let accentBlue = NSColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1.0)
    static let textPrimary = NSColor(red: 0.91, green: 0.88, blue: 0.94, alpha: 1.0)
    static let textSecondary = NSColor(red: 0.54, green: 0.50, blue: 0.63, alpha: 1.0)
    static let statusOk = NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1.0)
    static let statusErr = NSColor(red: 0.97, green: 0.55, blue: 0.55, alpha: 1.0)
    static let statusWarn = NSColor(red: 0.98, green: 0.75, blue: 0.30, alpha: 1.0)
}

// ─── 圆角视图 ──────────────────────────────────────────────
class CardView: NSView {
    var cornerRadius: CGFloat = 12
    var bgColor: NSColor = .bgCard

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = bgColor.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.accentPink.withAlphaComponent(0.12).cgColor
    }
}

// ─── 状态卡片 ──────────────────────────────────────────────
class StatusCard: CardView {
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")

    init(title: String, frame: NSRect) {
        super.init(frame: frame)
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 11)
        titleLabel.textColor = .textSecondary
        titleLabel.alignment = .center

        valueLabel.stringValue = "—"
        valueLabel.font = NSFont.boldSystemFont(ofSize: 15)
        valueLabel.textColor = .textSecondary
        valueLabel.alignment = .center

        addSubview(titleLabel)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 8, y: bounds.height - 22, width: bounds.width - 16, height: 14)
        valueLabel.frame = NSRect(x: 8, y: 12, width: bounds.width - 16, height: 24)
    }

    func update(_ value: String, _ ok: Bool) {
        valueLabel.stringValue = value
        valueLabel.textColor = ok ? .statusOk : .statusErr
    }
}

// ─── 应用委托 ──────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    // 状态卡片
    var wbCard: StatusCard!
    var cdpCard: StatusCard!
    var daemonCard: StatusCard!
    var bgCard: StatusCard!

    // 控件
    var startButton: NSButton!
    var refreshButton: NSButton!
    var openWebButton: NSButton!
    var selectFileButton: NSButton!
    var clearButton: NSButton!
    var enabledCheckbox: NSButton!
    var opacitySlider: NSSlider!
    var overlaySlider: NSSlider!
    var blurPopup: NSPopUpButton!
    var scalePopup: NSPopUpButton!
    var positionPopup: NSPopUpButton!
    var fileLabel: NSTextField!
    var opacityValueLabel: NSTextField!
    var overlayValueLabel: NSTextField!

    let daemonURL = "http://localhost:17890"
    var currentConfig: [String: Any] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow()
        startDaemonIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshStatus()
            self.loadConfig()
        }
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.refreshStatus()
        }
    }

    // ─── 窗口创建 ──────────────────────────────────────────
    func createWindow() {
        let W: CGFloat = 720
        let H: CGFloat = 860

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.center()
        window.minSize = NSSize(width: W, height: H)
        window.maxSize = NSSize(width: W, height: H)

        let bg = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.bgDark.cgColor
        window.contentView = bg

        let padding: CGFloat = 24
        var y: CGFloat = H - padding

        // ── 标题区 ──
        let titleLabel = NSTextField(labelWithString: "WorkBuddy-Skin")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 30)
        titleLabel.textColor = .textPrimary
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: padding, y: y - 40, width: W - padding * 2, height: 40)
        bg.addSubview(titleLabel)
        y -= 48

        let versionLabel = NSTextField(labelWithString: "背景注入管理器 v2.1")
        versionLabel.font = NSFont.systemFont(ofSize: 13)
        versionLabel.textColor = .textSecondary
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: padding, y: y - 18, width: W - padding * 2, height: 16)
        bg.addSubview(versionLabel)
        y -= 36

        // ── 状态卡片 ──
        let cardW: CGFloat = (W - padding * 2 - 30) / 4
        let cardH: CGFloat = 72
        let gap: CGFloat = 10

        wbCard = StatusCard(title: "WorkBuddy", frame: NSRect(x: padding, y: y - cardH, width: cardW, height: cardH))
        bg.addSubview(wbCard)

        cdpCard = StatusCard(title: "CDP 端口", frame: NSRect(x: padding + cardW + gap, y: y - cardH, width: cardW, height: cardH))
        bg.addSubview(cdpCard)

        daemonCard = StatusCard(title: "守护进程", frame: NSRect(x: padding + (cardW + gap) * 2, y: y - cardH, width: cardW, height: cardH))
        bg.addSubview(daemonCard)

        bgCard = StatusCard(title: "背景状态", frame: NSRect(x: padding + (cardW + gap) * 3, y: y - cardH, width: cardW, height: cardH))
        bg.addSubview(bgCard)

        y -= cardH + 24

        // ── 快速操作 ──
        y = addSectionTitle("快速操作", x: padding, y: y, width: W - padding * 2, view: bg)

        let btnW: CGFloat = (W - padding * 2 - gap * 2) / 3
        let btnH: CGFloat = 38

        startButton = createButton("🚀 启动", frame: NSRect(x: padding, y: y - btnH, width: btnW, height: btnH), action: #selector(startWorkBuddy), primary: true)
        bg.addSubview(startButton)

        refreshButton = createButton("🔄 刷新", frame: NSRect(x: padding + btnW + gap, y: y - btnH, width: btnW, height: btnH), action: #selector(refreshStatus), primary: false)
        bg.addSubview(refreshButton)

        openWebButton = createButton("🌐 Web 面板", frame: NSRect(x: padding + (btnW + gap) * 2, y: y - btnH, width: btnW, height: btnH), action: #selector(openWebPanel), primary: false)
        bg.addSubview(openWebButton)

        y -= btnH + 24

        // ── 背景设置 ──
        y = addSectionTitle("背景设置", x: padding, y: y, width: W - padding * 2, view: bg)

        // 文件选择区
        let fileCard = CardView(frame: NSRect(x: padding, y: y - 50, width: W - padding * 2, height: 50))
        fileCard.cornerRadius = 8
        bg.addSubview(fileCard)

        fileLabel = NSTextField(labelWithString: "📄 未选择文件")
        fileLabel.font = NSFont.systemFont(ofSize: 13)
        fileLabel.textColor = .textSecondary
        fileLabel.lineBreakMode = .byTruncatingTail
        fileLabel.frame = NSRect(x: 12, y: 16, width: fileCard.bounds.width - 24, height: 18)
        fileCard.addSubview(fileLabel)

        y -= 58

        // 文件操作按钮
        selectFileButton = createButton("📁 选择文件", frame: NSRect(x: padding, y: y - btnH, width: btnW, height: btnH), action: #selector(selectFile), primary: false)
        bg.addSubview(selectFileButton)

        clearButton = createButton("🗑️ 清除", frame: NSRect(x: padding + btnW + gap, y: y - btnH, width: btnW, height: btnH), action: #selector(clearBackground), primary: false)
        bg.addSubview(clearButton)

        y -= btnH + 16

        // 启用开关
        enabledCheckbox = NSButton(checkboxWithTitle: "启用背景", target: self, action: #selector(updateConfig))
        enabledCheckbox.frame = NSRect(x: padding, y: y - 24, width: 200, height: 24)
        styleCheckbox(enabledCheckbox)
        bg.addSubview(enabledCheckbox)
        y -= 36

        // 滑块和下拉菜单
        y = addSliderRow("不透明度", x: padding, y: y, width: W - padding * 2, view: bg,
                         slider: &opacitySlider, valueLabel: &opacityValueLabel,
                         minValue: 10, maxValue: 100, initialValue: 100, action: #selector(sliderChanged))

        y = addSliderRow("暗色遮罩", x: padding, y: y, width: W - padding * 2, view: bg,
                         slider: &overlaySlider, valueLabel: &overlayValueLabel,
                         minValue: 0, maxValue: 80, initialValue: 50, action: #selector(sliderChanged))

        y = addPopupRow("模糊", x: padding, y: y, width: W - padding * 2, view: bg,
                        popup: &blurPopup, items: ["无", "轻微 (5px)", "中等 (10px)", "强烈 (20px)"],
                        action: #selector(updateConfig))

        y = addPopupRow("填充方式", x: padding, y: y, width: W - padding * 2, view: bg,
                        popup: &scalePopup, items: ["覆盖", "包含", "填充"],
                        action: #selector(updateConfig))

        y = addPopupRow("位置", x: padding, y: y, width: W - padding * 2, view: bg,
                        popup: &positionPopup, items: ["居中", "顶部", "底部", "左侧", "右侧"],
                        action: #selector(updateConfig))

        window.makeKeyAndOrderFront(nil)
    }

    // ─── UI 辅助方法 ────────────────────────────────────────
    func addSectionTitle(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, view: NSView) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 15)
        label.textColor = .accentPink
        label.frame = NSRect(x: x, y: y - 22, width: width, height: 20)
        view.addSubview(label)
        return y - 30
    }

    func createButton(_ title: String, frame: NSRect, action: Selector, primary: Bool) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.title = title
        btn.bezelStyle = .rounded
        btn.target = self
        btn.action = action
        btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        if primary {
            btn.keyEquivalent = "\r"
        }
        return btn
    }

    func styleCheckbox(_ checkbox: NSButton) {
        // 使用系统默认样式即可
    }

    func addSliderRow(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, view: NSView,
                      slider: inout NSSlider, valueLabel: inout NSTextField,
                      minValue: Double, maxValue: Double, initialValue: Double, action: Selector) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .textPrimary
        label.frame = NSRect(x: x, y: y - 20, width: 100, height: 18)
        view.addSubview(label)

        valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .textSecondary
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: x + width - 60, y: y - 20, width: 60, height: 18)
        view.addSubview(valueLabel)

        slider = NSSlider(frame: NSRect(x: x + 110, y: y - 22, width: width - 180, height: 22))
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = initialValue
        slider.target = self
        slider.action = action
        view.addSubview(slider)

        return y - 36
    }

    func addPopupRow(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, view: NSView,
                     popup: inout NSPopUpButton, items: [String], action: Selector) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .textPrimary
        label.frame = NSRect(x: x, y: y - 20, width: 100, height: 18)
        view.addSubview(label)

        popup = NSPopUpButton(frame: NSRect(x: x + 110, y: y - 24, width: 180, height: 26))
        popup.addItems(withTitles: items)
        popup.target = self
        popup.action = action
        popup.font = NSFont.systemFont(ofSize: 12)
        view.addSubview(popup)

        return y - 36
    }

    // ─── 启动 WorkBuddy ────────────────────────────────────
    @objc func startWorkBuddy() {
        startButton.isEnabled = false
        startButton.title = "⏳ 启动中..."

        DispatchQueue.global().async {
            // 先退出 WorkBuddy
            let quitTask = Process()
            quitTask.launchPath = "/usr/bin/osascript"
            quitTask.arguments = ["-e", "tell application \"WorkBuddy\" to quit"]
            quitTask.standardOutput = FileHandle.nullDevice
            quitTask.standardError = FileHandle.nullDevice
            quitTask.launch()
            quitTask.waitUntilExit()
            Thread.sleep(forTimeInterval: 3)

            // 启动 launcher
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["\(NSHomeDirectory())/WorkBuddy-Skin/launcher.sh"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.launch()

            // 等待 CDP 端口开放
            var waited = 0
            while waited < 30 {
                Thread.sleep(forTimeInterval: 1)
                waited += 1
                if self.checkPort(9222) { break }
            }

            DispatchQueue.main.async {
                self.startButton.isEnabled = true
                self.startButton.title = "🚀 启动"
                self.refreshStatus()
            }
        }
    }

    // ─── 刷新状态 ──────────────────────────────────────────
    @objc func refreshStatus() {
        DispatchQueue.global().async {
            let daemonOk = self.checkPort(17890)
            let cdpOk = self.checkPort(9222)

            DispatchQueue.main.async {
                self.daemonCard.update(daemonOk ? "运行中" : "未运行", daemonOk)
                self.cdpCard.update(cdpOk ? "已开放" : "未开放", cdpOk)
                self.wbCard.update(cdpOk ? "运行中" : "未运行", cdpOk)

                if let enabled = self.currentConfig["enabled"] as? Bool,
                   let source = self.currentConfig["source"] as? String {
                    let bgActive = enabled && !source.isEmpty
                    self.bgCard.update(bgActive ? "已启用" : "未启用", bgActive)
                } else {
                    self.bgCard.update("未配置", false)
                }
            }
        }
    }

    // ─── 打开 Web 面板 ─────────────────────────────────────
    @objc func openWebPanel() {
        NSWorkspace.shared.open(URL(string: daemonURL)!)
    }

    // ─── 选择文件 ──────────────────────────────────────────
    @objc func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择背景图片或视频"

        let videoTypes: [UTType] = [UTType.movie, UTType.video, UTType.mpeg4Movie, UTType.quickTimeMovie, UTType.avi]
        let imageTypes: [UTType] = [UTType.image, UTType.jpeg, UTType.png, UTType.gif]
        panel.allowedContentTypes = videoTypes + imageTypes

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                let ext = url.pathExtension.lowercased()
                let isVideo = ["mp4", "webm", "mov", "avi", "mkv", "m4v"].contains(ext)
                self.currentConfig["source"] = url.path
                self.currentConfig["type"] = isVideo ? "video" : "image"
                self.currentConfig["enabled"] = true
                self.enabledCheckbox.state = .on
                self.fileLabel.stringValue = (isVideo ? "🎬 " : "🖼️ ") + url.lastPathComponent
                self.updateConfig()
            }
        }
    }

    // ─── 清除背景 ──────────────────────────────────────────
    @objc func clearBackground() {
        currentConfig["enabled"] = false
        currentConfig["source"] = ""
        enabledCheckbox.state = .off
        fileLabel.stringValue = "📄 未选择文件"
        updateConfig()
    }

    // ─── 滑块变化 ──────────────────────────────────────────
    @objc func sliderChanged() {
        let opacity = Int(opacitySlider.doubleValue)
        let overlay = Int(overlaySlider.doubleValue)
        opacityValueLabel.stringValue = "\(opacity)%"
        overlayValueLabel.stringValue = "\(overlay)%"
        updateConfig()
    }

    // ─── 更新配置 ──────────────────────────────────────────
    @objc func updateConfig() {
        currentConfig["enabled"] = enabledCheckbox.state == .on
        currentConfig["opacity"] = opacitySlider.doubleValue / 100
        currentConfig["overlay"] = overlaySlider.doubleValue / 100

        let blurValues = ["0px", "5px", "10px", "20px"]
        currentConfig["blur"] = blurValues[blurPopup.indexOfSelectedItem]

        let scaleValues = ["cover", "contain", "fill"]
        currentConfig["scale"] = scaleValues[scalePopup.indexOfSelectedItem]

        let positionValues = ["center", "top", "bottom", "left", "right"]
        currentConfig["position"] = positionValues[positionPopup.indexOfSelectedItem]

        saveConfig()
    }

    // ─── 加载配置 ──────────────────────────────────────────
    func loadConfig() {
        guard let url = URL(string: "\(daemonURL)/api/config") else { return }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                self.currentConfig = json
                self.enabledCheckbox.state = (json["enabled"] as? Bool ?? false) ? .on : .off
                self.opacitySlider.doubleValue = (json["opacity"] as? Double ?? 1.0) * 100
                self.overlaySlider.doubleValue = (json["overlay"] as? Double ?? 0.5) * 100
                self.opacityValueLabel.stringValue = "\(Int(self.opacitySlider.doubleValue))%"
                self.overlayValueLabel.stringValue = "\(Int(self.overlaySlider.doubleValue))%"

                if let source = json["source"] as? String, !source.isEmpty {
                    let isVideo = (json["type"] as? String) == "video"
                    self.fileLabel.stringValue = (isVideo ? "🎬 " : "🖼️ ") + (source as NSString).lastPathComponent
                }

                let blurValues = ["0px", "5px", "10px", "20px"]
                if let blur = json["blur"] as? String, let idx = blurValues.firstIndex(of: blur) {
                    self.blurPopup.selectItem(at: idx)
                }

                let scaleValues = ["cover", "contain", "fill"]
                if let scale = json["scale"] as? String, let idx = scaleValues.firstIndex(of: scale) {
                    self.scalePopup.selectItem(at: idx)
                }

                let positionValues = ["center", "top", "bottom", "left", "right"]
                if let pos = json["position"] as? String, let idx = positionValues.firstIndex(of: pos) {
                    self.positionPopup.selectItem(at: idx)
                }

                self.refreshStatus()
            }
        }
        task.resume()
    }

    // ─── 保存配置 ──────────────────────────────────────────
    func saveConfig() {
        guard let url = URL(string: "\(daemonURL)/api/config") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: currentConfig)
        URLSession.shared.dataTask(with: request).resume()
    }

    // ─── 守护进程 ──────────────────────────────────────────
    func startDaemonIfNeeded() {
        if !checkPort(17890) {
            DispatchQueue.global().async {
                let task = Process()
                task.launchPath = "/Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node"
                task.arguments = ["\(NSHomeDirectory())/WorkBuddy-Skin/daemon.js"]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                Thread.sleep(forTimeInterval: 3)
                DispatchQueue.main.async { self.loadConfig() }
            }
        } else {
            loadConfig()
        }
    }

    // ─── 端口检查 ──────────────────────────────────────────
    func checkPort(_ port: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/nc"
        task.arguments = ["-z", "-w", "1", "localhost", String(port)]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// ─── 入口 ──────────────────────────────────────────────────
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
