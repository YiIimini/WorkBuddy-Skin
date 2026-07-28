import Cocoa
import UniformTypeIdentifiers
import AVFoundation

// ─── 颜色（高对比度，确保可读）──────────────────────────────
extension NSColor {
    static let bgDark = NSColor(srgbRed: 0.05, green: 0.03, blue: 0.08, alpha: 1.0)
    static let bgCard = NSColor(srgbRed: 0.13, green: 0.09, blue: 0.19, alpha: 1.0)
    static let accentPink = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.65, alpha: 1.0)
    // 使用系统自适应颜色，确保深色模式下可读
    static let textTitle = NSColor.labelColor  // 纯白（深色模式）
    static let textBody = NSColor.controlTextColor  // 接近白色
    static let textLabel = NSColor.secondaryLabelColor  // 浅灰
    static let textHint = NSColor.tertiaryLabelColor  // 中灰
    static let statusOk = NSColor(srgbRed: 0.30, green: 0.90, blue: 0.55, alpha: 1.0)
    static let statusErr = NSColor(srgbRed: 1.0, green: 0.50, blue: 0.50, alpha: 1.0)
}

// ─── 状态卡片 ──────────────────────────────────────────────
class StatusCard: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")

    init(title: String, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.bgCard.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.accentPink.withAlphaComponent(0.15).cgColor

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .textHint
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 8, y: bounds.height - 20, width: bounds.width - 16, height: 14)
        addSubview(titleLabel)

        valueLabel.stringValue = "—"
        valueLabel.font = NSFont.boldSystemFont(ofSize: 14)
        valueLabel.textColor = .textBody
        valueLabel.alignment = .center
        valueLabel.frame = NSRect(x: 8, y: 12, width: bounds.width - 16, height: 22)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ value: String, _ ok: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.valueLabel.stringValue = value
            self?.valueLabel.textColor = ok ? .statusOk : .statusErr
        }
    }
}

// ─── 应用委托 ──────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    var wbCard: StatusCard!
    var cdpCard: StatusCard!
    var daemonCard: StatusCard!
    var bgCard: StatusCard!

    var startButton: NSButton!
    var selectFileButton: NSButton!
    var clearButton: NSButton!
    var enabledCheckbox: NSButton!
    var opacitySlider: NSSlider!
    var overlaySlider: NSSlider!
    var opacityValueLabel: NSTextField!
    var overlayValueLabel: NSTextField!
    var blurPopup: NSPopUpButton!
    var scalePopup: NSPopUpButton!
    var positionPopup: NSPopUpButton!
    var fileLabel: NSTextField!

    // 预览
    var previewView: NSView!
    var previewImageView: NSImageView!

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

    // ─── 窗口 ──────────────────────────────────────────────
    func createWindow() {
        let W: CGFloat = 720
        let H: CGFloat = 880

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WorkBuddy-Skin"
        window.titlebarAppearsTransparent = true
        window.center()
        window.minSize = NSSize(width: W, height: H)
        window.maxSize = NSSize(width: W, height: H)
        // 强制深色外观
        window.appearance = NSAppearance(named: .darkAqua)

        let bg = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.bgDark.cgColor
        window.contentView = bg

        let p: CGFloat = 24
        var y: CGFloat = H - p - 10

        // 标题
        let titleLabel = makeLabel("WorkBuddy-Skin", size: 28, bold: true, color: .textTitle)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: p, y: y - 36, width: W - p*2, height: 34)
        bg.addSubview(titleLabel)
        y -= 44

        let subLabel = makeLabel("背景注入管理器 v2.2", size: 13, bold: false, color: .textHint)
        subLabel.alignment = .center
        subLabel.frame = NSRect(x: p, y: y - 16, width: W - p*2, height: 14)
        bg.addSubview(subLabel)
        y -= 28

        // ── 预览区 ──
        let previewH: CGFloat = 180
        previewView = NSView(frame: NSRect(x: p, y: y - previewH, width: W - p*2, height: previewH))
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.bgCard.cgColor
        previewView.layer?.cornerRadius = 12
        previewView.layer?.borderWidth = 1
        previewView.layer?.borderColor = NSColor.accentPink.withAlphaComponent(0.15).cgColor
        bg.addSubview(previewView)

        previewImageView = NSImageView(frame: NSRect(x: 0, y: 0, width: previewView.bounds.width, height: previewView.bounds.height))
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewView.addSubview(previewImageView)

        let noPreviewLabel = makeLabel("选择文件后显示预览", size: 14, bold: false, color: .textHint)
        noPreviewLabel.alignment = .center
        noPreviewLabel.tag = 999
        noPreviewLabel.frame = NSRect(x: 0, y: previewH/2 - 10, width: previewView.bounds.width, height: 20)
        previewView.addSubview(noPreviewLabel)

        y -= previewH + 20

        // ── 状态卡片 ──
        let cardW: CGFloat = (W - p*2 - 30) / 4
        let cardH: CGFloat = 60
        let gap: CGFloat = 10

        wbCard = StatusCard(title: "WorkBuddy", frame: NSRect(x: p, y: y - cardH, width: cardW, height: cardH))
        cdpCard = StatusCard(title: "CDP 端口", frame: NSRect(x: p + (cardW+gap), y: y - cardH, width: cardW, height: cardH))
        daemonCard = StatusCard(title: "守护进程", frame: NSRect(x: p + (cardW+gap)*2, y: y - cardH, width: cardW, height: cardH))
        bgCard = StatusCard(title: "背景状态", frame: NSRect(x: p + (cardW+gap)*3, y: y - cardH, width: cardW, height: cardH))
        bg.addSubview(wbCard)
        bg.addSubview(cdpCard)
        bg.addSubview(daemonCard)
        bg.addSubview(bgCard)
        y -= cardH + 20

        // ── 快速操作 ──
        y = addSection("快速操作", x: p, y: y, w: W - p*2, view: bg)
        let btnW = (W - p*2 - gap) / 2
        let btnH: CGFloat = 36

        startButton = makeButton("🚀 启动 WorkBuddy", frame: NSRect(x: p, y: y - btnH, width: btnW, height: btnH), action: #selector(startWorkBuddy))
        let refreshButton = makeButton("🔄 刷新状态", frame: NSRect(x: p + btnW + gap, y: y - btnH, width: btnW, height: btnH), action: #selector(refreshStatus))
        bg.addSubview(startButton)
        bg.addSubview(refreshButton)
        y -= btnH + 20

        // ── 背景设置 ──
        y = addSection("背景设置", x: p, y: y, w: W - p*2, view: bg)

        fileLabel = makeLabel("📄 未选择文件", size: 13, bold: false, color: .textLabel)
        fileLabel.lineBreakMode = .byTruncatingTail
        fileLabel.frame = NSRect(x: p, y: y - 18, width: W - p*2, height: 16)
        bg.addSubview(fileLabel)
        y -= 26

        selectFileButton = makeButton("📁 选择文件", frame: NSRect(x: p, y: y - btnH, width: btnW, height: btnH), action: #selector(selectFile))
        clearButton = makeButton("🗑️ 清除背景", frame: NSRect(x: p + btnW + gap, y: y - btnH, width: btnW, height: btnH), action: #selector(clearBackground))
        bg.addSubview(selectFileButton)
        bg.addSubview(clearButton)
        y -= btnH + 14

        enabledCheckbox = NSButton(checkboxWithTitle: "启用背景", target: self, action: #selector(updateConfig))
        enabledCheckbox.frame = NSRect(x: p, y: y - 22, width: 200, height: 22)
        styleCheckbox(enabledCheckbox)
        bg.addSubview(enabledCheckbox)
        y -= 32

        // 滑块行
        opacityValueLabel = makeLabel("100%", size: 12, bold: false, color: .textLabel)
        opacityValueLabel.alignment = .right
        opacitySlider = makeSliderRow("不透明度", valueLabel: opacityValueLabel, x: p, y: y, w: W - p*2, view: bg, min: 10, max: 100, initVal: 100)
        opacitySlider.target = self
        opacitySlider.action = #selector(sliderChanged)
        y -= 34

        overlayValueLabel = makeLabel("50%", size: 12, bold: false, color: .textLabel)
        overlayValueLabel.alignment = .right
        overlaySlider = makeSliderRow("暗色遮罩", valueLabel: overlayValueLabel, x: p, y: y, w: W - p*2, view: bg, min: 0, max: 80, initVal: 50)
        overlaySlider.target = self
        overlaySlider.action = #selector(sliderChanged)
        y -= 34

        blurPopup = makePopupRow("模糊", items: ["无", "轻微 (5px)", "中等 (10px)", "强烈 (20px)"], x: p, y: y, w: W - p*2, view: bg)
        blurPopup.target = self
        blurPopup.action = #selector(updateConfig)
        y -= 32

        scalePopup = makePopupRow("填充方式", items: ["覆盖", "包含", "填充"], x: p, y: y, w: W - p*2, view: bg)
        scalePopup.target = self
        scalePopup.action = #selector(updateConfig)
        y -= 32

        positionPopup = makePopupRow("位置", items: ["居中", "顶部", "底部", "左侧", "右侧"], x: p, y: y, w: W - p*2, view: bg)
        positionPopup.target = self
        positionPopup.action = #selector(updateConfig)

        window.makeKeyAndOrderFront(nil)
    }

    // ─── UI 辅助 ───────────────────────────────────────────
    func makeLabel(_ text: String, size: CGFloat, bold: Bool, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = color
        return label
    }

    func makeButton(_ title: String, frame: NSRect, action: Selector) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.title = title
        btn.bezelStyle = .rounded
        btn.target = self
        btn.action = action
        btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        return btn
    }

    func styleCheckbox(_ cb: NSButton) {
        // 系统默认
    }

    func addSection(_ title: String, x: CGFloat, y: CGFloat, w: CGFloat, view: NSView) -> CGFloat {
        let label = makeLabel(title, size: 15, bold: true, color: .accentPink)
        label.frame = NSRect(x: x, y: y - 20, width: w, height: 18)
        view.addSubview(label)
        return y - 28
    }

    func makeSliderRow(_ title: String, valueLabel: NSTextField, x: CGFloat, y: CGFloat, w: CGFloat, view: NSView, min: Double, max: Double, initVal: Double) -> NSSlider {
        let titleLabel = makeLabel(title, size: 13, bold: false, color: .textLabel)
        titleLabel.frame = NSRect(x: x, y: y - 18, width: 90, height: 16)
        view.addSubview(titleLabel)

        valueLabel.frame = NSRect(x: x + w - 50, y: y - 18, width: 50, height: 16)
        view.addSubview(valueLabel)

        let slider = NSSlider(frame: NSRect(x: x + 100, y: y - 20, width: w - 160, height: 20))
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = initVal
        view.addSubview(slider)
        return slider
    }

    func makePopupRow(_ title: String, items: [String], x: CGFloat, y: CGFloat, w: CGFloat, view: NSView) -> NSPopUpButton {
        let titleLabel = makeLabel(title, size: 13, bold: false, color: .textLabel)
        titleLabel.frame = NSRect(x: x, y: y - 18, width: 90, height: 16)
        view.addSubview(titleLabel)

        let popup = NSPopUpButton(frame: NSRect(x: x + 100, y: y - 22, width: 180, height: 24))
        popup.addItems(withTitles: items)
        popup.font = NSFont.systemFont(ofSize: 12)
        view.addSubview(popup)
        return popup
    }

    // ─── 预览 ─────────────────────────────────────────────
    func showPreview(_ path: String) {
        // 移除旧预览
        previewImageView.image = nil
        if let oldLabel = previewView.viewWithTag(999) {
            oldLabel.removeFromSuperview()
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let isVideo = ["mp4", "webm", "mov", "avi", "mkv", "m4v"].contains(ext)

        if isVideo {
            // 生成视频缩略图
            DispatchQueue.global().async {
                let url = URL(fileURLWithPath: path)
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 200)

                do {
                    let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    DispatchQueue.main.async {
                        self.previewImageView.image = image
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showNoPreview("🎬 无法生成视频预览")
                    }
                }
            }
        } else {
            // 图片直接显示
            if let image = NSImage(contentsOfFile: path) {
                previewImageView.image = image
            } else {
                showNoPreview("🖼️ 无法加载图片")
            }
        }
    }

    func showNoPreview(_ text: String) {
        let label = makeLabel(text, size: 14, bold: false, color: .textHint)
        label.alignment = .center
        label.tag = 999
        label.frame = NSRect(x: 0, y: previewView.bounds.height/2 - 10, width: previewView.bounds.width, height: 20)
        previewView.addSubview(label)
    }

    func clearPreview() {
        previewImageView.image = nil
        showNoPreview("选择文件后显示预览")
    }

    // ─── 启动 WorkBuddy ────────────────────────────────────
    @objc func startWorkBuddy() {
        startButton.isEnabled = false
        startButton.title = "⏳ 启动中..."

        DispatchQueue.global().async {
            let quit = Process()
            quit.launchPath = "/usr/bin/osascript"
            quit.arguments = ["-e", "tell application \"WorkBuddy\" to quit"]
            quit.standardOutput = FileHandle.nullDevice
            quit.standardError = FileHandle.nullDevice
            quit.launch()
            quit.waitUntilExit()
            Thread.sleep(forTimeInterval: 3)

            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["\(NSHomeDirectory())/WorkBuddy-Skin/launcher.sh"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.launch()

            var waited = 0
            while waited < 30 {
                Thread.sleep(forTimeInterval: 1)
                waited += 1
                if self.checkPort(9222) { break }
            }

            DispatchQueue.main.async {
                self.startButton.isEnabled = true
                self.startButton.title = "🚀 启动 WorkBuddy"
                self.refreshStatus()
            }
        }
    }

    // ─── 刷新状态 ──────────────────────────────────────────
    @objc func refreshStatus() {
        DispatchQueue.global().async {
            let daemonOk = self.checkPort(17890)
            let cdpOk = self.checkPort(9222)

            self.daemonCard.update(daemonOk ? "运行中" : "未运行", daemonOk)
            self.cdpCard.update(cdpOk ? "已开放" : "未开放", cdpOk)
            self.wbCard.update(cdpOk ? "运行中" : "未运行", cdpOk)

            if let enabled = self.currentConfig["enabled"] as? Bool,
               let source = self.currentConfig["source"] as? String {
                let bgActive = enabled && !source.isEmpty
                self.bgCard.update(bgActive ? "已启用" : "未启用", bgActive)
            }
        }
    }

    // ─── 选择文件 ──────────────────────────────────────────
    @objc func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择背景图片或视频"
        panel.allowedContentTypes = [UTType.movie, UTType.video, UTType.image]

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
                self.showPreview(url.path)
                self.updateConfig()
            }
        }
    }

    @objc func clearBackground() {
        currentConfig["enabled"] = false
        currentConfig["source"] = ""
        enabledCheckbox.state = .off
        fileLabel.stringValue = "📄 未选择文件"
        clearPreview()
        updateConfig()
    }

    @objc func sliderChanged() {
        opacityValueLabel.stringValue = "\(Int(opacitySlider.doubleValue))%"
        overlayValueLabel.stringValue = "\(Int(overlaySlider.doubleValue))%"
        updateConfig()
    }

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

    func loadConfig() {
        guard let url = URL(string: "\(daemonURL)/api/config") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
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
                    self.showPreview(source)
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
        }.resume()
    }

    func saveConfig() {
        guard let url = URL(string: "\(daemonURL)/api/config") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: currentConfig)
        URLSession.shared.dataTask(with: request).resume()
    }

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// ─── 入口 ──────────────────────────────────────────────────
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
