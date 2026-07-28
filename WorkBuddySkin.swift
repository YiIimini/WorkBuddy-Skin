import Cocoa
import UniformTypeIdentifiers
import AVFoundation

// ─── 颜色 ──────────────────────────────────────────────────
extension NSColor {
    static let bgDark = NSColor(srgbRed: 0.05, green: 0.03, blue: 0.08, alpha: 1.0)
    static let bgCard = NSColor(srgbRed: 0.13, green: 0.09, blue: 0.19, alpha: 1.0)
    static let accentPink = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.65, alpha: 1.0)
    static let textTitle = NSColor.labelColor
    static let textBody = NSColor.controlTextColor
    static let textLabel = NSColor.secondaryLabelColor
    static let textHint = NSColor.tertiaryLabelColor
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
    var bg: NSView!
    var statusItem: NSStatusItem!

    var wbCard: StatusCard!
    var cdpCard: StatusCard!
    var daemonCard: StatusCard!
    var bgCard: StatusCard!

    var startButton: NSButton!
    var injectButton: NSButton!
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
    var autoTextCheckbox: NSButton!
    var textColorWell: NSColorWell!
    var themePopup: NSPopUpButton!
    var fileLabel: NSTextField!

    var previewView: NSView!
    var previewImageView: NSImageView!
    var previewHeight: CGFloat = 50
    var previewBaseY: CGFloat = 0
    var belowPreviewViews: [NSView] = []

    let daemonURL = "http://localhost:17890"
    var currentConfig: [String: Any] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        createWindow()
        startDaemonIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshStatus()
            self.loadConfig()
            self.updateMenuStatus()
        }
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.refreshStatus()
            self.updateMenuStatus()
        }
    }

    // ─── 菜单栏 ──────────────────────────────────────────
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let icon = NSImage(contentsOfFile: "\(NSHomeDirectory())/Pictures/暴富喵 apng.png") {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.title = "🎨"
            }
        }
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开管理器", action: #selector(showWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        let injectItem = NSMenuItem(title: "🔌 CDP 注入启动", action: #selector(menuStartWorkBuddy), keyEquivalent: "")
        injectItem.target = self
        menu.addItem(injectItem)

        let toggleBgItem = NSMenuItem(title: "🎬 启用背景", action: #selector(menuToggleBackground), keyEquivalent: "")
        toggleBgItem.target = self
        toggleBgItem.tag = 100
        menu.addItem(toggleBgItem)
        menu.addItem(NSMenuItem.separator())

        let statusMenu = NSMenu()
        let daemonItem = NSMenuItem(title: "守护进程: —", action: nil, keyEquivalent: "")
        daemonItem.tag = 201; statusMenu.addItem(daemonItem)
        let cdpItem = NSMenuItem(title: "CDP 端口: —", action: nil, keyEquivalent: "")
        cdpItem.tag = 202; statusMenu.addItem(cdpItem)
        let bgItem = NSMenuItem(title: "背景状态: —", action: nil, keyEquivalent: "")
        bgItem.tag = 203; statusMenu.addItem(bgItem)

        let statusMenuItem = NSMenuItem(title: "状态", action: nil, keyEquivalent: "")
        statusMenuItem.submenu = statusMenu
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "🔄 刷新状态", action: #selector(menuRefreshStatus), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 WorkBuddy-Skin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func menuStartWorkBuddy() { startWorkBuddy() }

    @objc func menuToggleBackground() {
        enabledCheckbox.state = enabledCheckbox.state == .on ? .off : .on
        updateConfig()
        updateMenuStatus()
        showWindow()
    }

    @objc func menuRefreshStatus() { refreshStatus(); updateMenuStatus() }

    func updateMenuStatus() {
        DispatchQueue.global().async {
            let daemonOk = self.checkPort(17890)
            let cdpOk = self.checkPort(9222)
            let bgActive = (self.currentConfig["enabled"] as? Bool ?? false) && !(self.currentConfig["source"] as? String ?? "").isEmpty
            DispatchQueue.main.async {
                if let item = self.statusItem.menu?.item(withTag: 201) { item.title = "守护进程: " + (daemonOk ? "✓ 运行中" : "✗ 未运行") }
                if let item = self.statusItem.menu?.item(withTag: 202) { item.title = "CDP 端口: " + (cdpOk ? "✓ 已开放" : "✗ 未开放") }
                if let item = self.statusItem.menu?.item(withTag: 203) { item.title = "背景状态: " + (bgActive ? "✓ 已启用" : "— 未启用") }
                if let item = self.statusItem.menu?.item(withTag: 100) { item.title = bgActive ? "⏹️ 停用背景" : "🎬 启用背景" }
            }
        }
    }

    // ─── 窗口 ──────────────────────────────────────────────
    func createWindow() {
        let W: CGFloat = 720
        let H: CGFloat = 920

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "WorkBuddy-Skin"
        window.titlebarAppearsTransparent = true
        window.center()
        window.minSize = NSSize(width: W, height: H)
        window.maxSize = NSSize(width: W, height: H)
        window.appearance = NSAppearance(named: .darkAqua)

        bg = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.bgDark.cgColor
        window.contentView = bg

        let p: CGFloat = 24
        let gap: CGFloat = 10
        var y: CGFloat = H - p - 10

        // ── 标题 ──
        let titleLabel = makeLabel("WorkBuddy-Skin 背景注入管理器 v2.3", size: 22, bold: true, color: .textTitle)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: p, y: y - 30, width: W - p*2, height: 28)
        bg.addSubview(titleLabel)
        y -= 44

        // ━━ 背景设置 ━━
        y = addSection("背景设置", x: p, y: y, w: W - p*2, view: bg)

        // 文件目录
        fileLabel = makeLabel("📄 未选择文件", size: 13, bold: false, color: .textLabel)
        fileLabel.lineBreakMode = .byTruncatingTail
        fileLabel.frame = NSRect(x: p, y: y - 18, width: W - p*2, height: 16)
        bg.addSubview(fileLabel)
        y -= 26

        // 选择文件 + 清除背景
        let btnW = (W - p*2 - gap) / 2
        let btnH: CGFloat = 34

        selectFileButton = makeButton("📁 选择文件", frame: NSRect(x: p, y: y - btnH, width: btnW, height: btnH), action: #selector(selectFile))
        clearButton = makeButton("🗑️ 清除背景", frame: NSRect(x: p + btnW + gap, y: y - btnH, width: btnW, height: btnH), action: #selector(clearBackground))
        bg.addSubview(selectFileButton)
        bg.addSubview(clearButton)
        y -= btnH + 14

        // 预览缩略图
        previewHeight = 50
        previewBaseY = y
        previewView = NSView(frame: NSRect(x: p, y: y - previewHeight, width: W - p*2, height: previewHeight))
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.bgCard.cgColor
        previewView.layer?.cornerRadius = 10
        previewView.layer?.borderWidth = 1
        previewView.layer?.borderColor = NSColor.accentPink.withAlphaComponent(0.12).cgColor
        bg.addSubview(previewView)

        previewImageView = NSImageView(frame: NSRect(x: 0, y: 0, width: previewView.bounds.width, height: previewView.bounds.height))
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.isHidden = true
        previewView.addSubview(previewImageView)

        let noPreviewLabel = makeLabel("选择文件后显示预览", size: 13, bold: false, color: .textHint)
        noPreviewLabel.alignment = .center
        noPreviewLabel.tag = 999
        noPreviewLabel.frame = NSRect(x: 0, y: previewHeight/2 - 10, width: previewView.bounds.width, height: 20)
        previewView.addSubview(noPreviewLabel)
        y -= previewHeight + 14

        // 启动背景按钮 + 文件类型说明
        startButton = makeButton("🎬 启动背景（支持图片 JPG/PNG/GIF、视频 MP4/MOV/WebM）", frame: NSRect(x: p, y: y - btnH, width: W - p*2, height: btnH), action: #selector(toggleBackground))
        bg.addSubview(startButton)
        y -= btnH + 14

        // 启用开关
        enabledCheckbox = NSButton(checkboxWithTitle: "启用背景", target: self, action: #selector(updateConfig))
        enabledCheckbox.frame = NSRect(x: p, y: y - 22, width: 200, height: 22)
        bg.addSubview(enabledCheckbox)
        y -= 30

        // 模糊 + 填充方式 + 位置（一行三个下拉）
        let popupW: CGFloat = (W - p*2 - gap*2) / 3
        blurPopup = makePopupCompact(items: ["模糊: 无", "模糊: 轻微", "模糊: 中等", "模糊: 强烈"], frame: NSRect(x: p, y: y - 26, width: popupW, height: 26))
        bg.addSubview(blurPopup)
        blurPopup.target = self
        blurPopup.action = #selector(updateConfig)

        scalePopup = makePopupCompact(items: ["填充: 覆盖", "填充: 包含", "填充: 填充"], frame: NSRect(x: p + popupW + gap, y: y - 26, width: popupW, height: 26))
        bg.addSubview(scalePopup)
        scalePopup.target = self
        scalePopup.action = #selector(updateConfig)

        positionPopup = makePopupCompact(items: ["位置: 居中", "位置: 顶部", "位置: 底部", "位置: 左侧", "位置: 右侧"], frame: NSRect(x: p + (popupW+gap)*2, y: y - 26, width: popupW, height: 26))
        bg.addSubview(positionPopup)
        positionPopup.target = self
        positionPopup.action = #selector(updateConfig)
        y -= 36

        // 文字颜色 — 自动取色 + 取色板
        autoTextCheckbox = NSButton(checkboxWithTitle: "自动取色 (根据背景反差)", target: self, action: #selector(autoTextChanged))
        autoTextCheckbox.frame = NSRect(x: p, y: y - 22, width: 260, height: 22)
        autoTextCheckbox.state = .on
        bg.addSubview(autoTextCheckbox)

        textColorWell = NSColorWell(frame: NSRect(x: p + 260, y: y - 26, width: 44, height: 26))
        textColorWell.color = NSColor.white
        textColorWell.isEnabled = false
        textColorWell.target = self
        textColorWell.action = #selector(updateConfig)
        bg.addSubview(textColorWell)
        y -= 36

        // 主题配色
        themePopup = makePopupCompact(items: ["主题: 暗紫", "主题: 暗蓝", "主题: 暗绿", "主题: 暖橙", "主题: 玫瑰", "主题: 石板", "主题: 午夜"], frame: NSRect(x: p, y: y - 26, width: popupW, height: 26))
        bg.addSubview(themePopup)
        themePopup.target = self
        themePopup.action = #selector(updateConfig)
        y -= 36

        // 透明度 + 暗色遮罩度（一行两个滑块）
        let sliderW: CGFloat = (W - p*2 - gap) / 2
        opacityValueLabel = makeLabel("100%", size: 12, bold: false, color: .textLabel)
        opacityValueLabel.alignment = .right
        opacitySlider = makeSliderCompact("不透明度", valueLabel: opacityValueLabel, frame: NSRect(x: p, y: y - 36, width: sliderW, height: 36), min: 10, max: 100, initVal: 100)
        opacitySlider.target = self
        opacitySlider.action = #selector(sliderChanged)
        bg.addSubview(opacityValueLabel)
        bg.addSubview(opacitySlider)

        overlayValueLabel = makeLabel("50%", size: 12, bold: false, color: .textLabel)
        overlayValueLabel.alignment = .right
        overlaySlider = makeSliderCompact("暗色遮罩", valueLabel: overlayValueLabel, frame: NSRect(x: p + sliderW + gap, y: y - 36, width: sliderW, height: 36), min: 0, max: 80, initVal: 50)
        overlaySlider.target = self
        overlaySlider.action = #selector(sliderChanged)
        bg.addSubview(overlayValueLabel)
        bg.addSubview(overlaySlider)
        y -= 44

        // ━━ 快速操作 ━━
        y = addSection("快速操作", x: p, y: y, w: W - p*2, view: bg)

        injectButton = makeButton("🔌 CDP 注入启动", frame: NSRect(x: p, y: y - btnH, width: btnW, height: btnH), action: #selector(startWorkBuddy))
        let refreshButton = makeButton("🔄 刷新状态", frame: NSRect(x: p + btnW + gap, y: y - btnH, width: btnW, height: btnH), action: #selector(refreshStatus))
        bg.addSubview(injectButton)
        bg.addSubview(refreshButton)
        y -= btnH + 24

        // ━━ 状态监测 ━━
        y = addSection("状态监测", x: p, y: y, w: W - p*2, view: bg)

        let cardW: CGFloat = (W - p*2 - gap*3) / 4
        let cardH: CGFloat = 56

        wbCard = StatusCard(title: "WorkBuddy", frame: NSRect(x: p, y: y - cardH, width: cardW, height: cardH))
        cdpCard = StatusCard(title: "CDP 端口", frame: NSRect(x: p + (cardW+gap), y: y - cardH, width: cardW, height: cardH))
        daemonCard = StatusCard(title: "守护进程", frame: NSRect(x: p + (cardW+gap)*2, y: y - cardH, width: cardW, height: cardH))
        bgCard = StatusCard(title: "背景状态", frame: NSRect(x: p + (cardW+gap)*3, y: y - cardH, width: cardW, height: cardH))
        bg.addSubview(wbCard)
        bg.addSubview(cdpCard)
        bg.addSubview(daemonCard)
        bg.addSubview(bgCard)

        // 收集预览下方的所有视图
        let previewBottom = previewBaseY - previewHeight
        for sv in bg.subviews {
            if sv !== previewView && sv.frame.origin.y < previewBottom + 5 {
                belowPreviewViews.append(sv)
            }
        }

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
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        return btn
    }

    func addSection(_ title: String, x: CGFloat, y: CGFloat, w: CGFloat, view: NSView) -> CGFloat {
        let label = makeLabel(title, size: 14, bold: true, color: .accentPink)
        label.frame = NSRect(x: x, y: y - 18, width: w, height: 16)
        view.addSubview(label)
        // 分隔线
        let line = NSView(frame: NSRect(x: x, y: y - 22, width: w, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.accentPink.withAlphaComponent(0.2).cgColor
        view.addSubview(line)
        return y - 30
    }

    func makePopupCompact(items: [String], frame: NSRect) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame)
        popup.addItems(withTitles: items)
        popup.font = NSFont.systemFont(ofSize: 11)
        return popup
    }

    func makeSliderCompact(_ title: String, valueLabel: NSTextField, frame: NSRect, min: Double, max: Double, initVal: Double) -> NSSlider {
        let titleLabel = makeLabel(title, size: 12, bold: false, color: .textLabel)
        titleLabel.frame = NSRect(x: 0, y: frame.height - 16, width: 70, height: 14)
        bg.addSubview(titleLabel)
        titleLabel.frame.origin.x = frame.origin.x
        titleLabel.frame.origin.y = frame.origin.y + frame.height - 16

        valueLabel.frame = NSRect(x: frame.origin.x + frame.width - 40, y: frame.origin.y + frame.height - 16, width: 40, height: 14)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let slider = NSSlider(frame: NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: 20))
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = initVal
        return slider
    }

    // ─── 预览 ─────────────────────────────────────────────
    func showPreview(_ path: String) {
        previewImageView.image = nil
        previewImageView.isHidden = true
        if let oldLabel = previewView.viewWithTag(999) { oldLabel.isHidden = false }

        let ext = (path as NSString).pathExtension.lowercased()
        let isVideo = ["mp4", "webm", "mov", "avi", "mkv", "m4v"].contains(ext)

        if isVideo {
            DispatchQueue.global().async {
                let url = URL(fileURLWithPath: path)
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 672, height: 400)
                do {
                    let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    DispatchQueue.main.async {
                        self.previewImageView.image = image
                        self.previewImageView.isHidden = false
                        if let oldLabel = self.previewView.viewWithTag(999) { oldLabel.isHidden = true }
                        self.resizePreview(imageSize: image.size)
                    }
                } catch {
                    DispatchQueue.main.async { self.showNoPreview("🎬 无法生成视频预览") }
                }
            }
        } else {
            if let image = NSImage(contentsOfFile: path) {
                previewImageView.image = image
                previewImageView.isHidden = false
                if let oldLabel = previewView.viewWithTag(999) { oldLabel.isHidden = true }
                resizePreview(imageSize: image.size)
            } else {
                showNoPreview("🖼️ 无法加载图片")
            }
        }
    }

    func resizePreview(imageSize: NSSize) {
        let maxWidth: CGFloat = 672
        let maxHeight: CGFloat = 200
        var newHeight: CGFloat = 50
        if imageSize.width > 0 {
            let ratio = imageSize.height / imageSize.width
            newHeight = min(maxWidth * ratio, maxHeight)
            if newHeight < 50 { newHeight = 50 }
        }
        let delta = newHeight - previewHeight
        previewHeight = newHeight
        previewView.frame = NSRect(x: previewView.frame.origin.x, y: previewBaseY - previewHeight, width: maxWidth, height: previewHeight)
        previewImageView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: previewHeight)
        if let label = previewView.viewWithTag(999) {
            label.frame = NSRect(x: 0, y: previewHeight/2 - 10, width: maxWidth, height: 20)
        }
        for view in belowPreviewViews { view.frame.origin.y -= delta }
    }

    func showNoPreview(_ text: String) {
        previewImageView.image = nil
        previewImageView.isHidden = true
        if let oldLabel = previewView.viewWithTag(999) {
            oldLabel.isHidden = false
            (oldLabel as? NSTextField)?.stringValue = text
        }
    }

    func clearPreview() {
        previewImageView.image = nil
        previewImageView.isHidden = true
        if let oldLabel = previewView.viewWithTag(999) {
            oldLabel.isHidden = false
            (oldLabel as? NSTextField)?.stringValue = "选择文件后显示预览"
        }
        if previewHeight != 50 { resizePreview(imageSize: NSSize(width: 100, height: 10)) }
    }

    // ─── 启动/停止背景 ────────────────────────────────────
    @objc func toggleBackground() {
        if enabledCheckbox.state == .on {
            enabledCheckbox.state = .off
        } else {
            enabledCheckbox.state = .on
        }
        updateConfig()
    }

    // ─── CDP 注入启动 ──────────────────────────────────────
    @objc func startWorkBuddy() {
        injectButton.isEnabled = false
        injectButton.title = "⏳ 启动中..."
        DispatchQueue.global().async {
            let quit = Process()
            quit.launchPath = "/usr/bin/osascript"
            quit.arguments = ["-e", "tell application \"WorkBuddy\" to quit"]
            quit.standardOutput = FileHandle.nullDevice
            quit.standardError = FileHandle.nullDevice
            quit.launch(); quit.waitUntilExit()
            Thread.sleep(forTimeInterval: 3)

            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["\(NSHomeDirectory())/WorkBuddy-Skin/launcher.sh"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.launch()

            var waited = 0
            while waited < 30 {
                Thread.sleep(forTimeInterval: 1); waited += 1
                if self.checkPort(9222) { break }
            }
            DispatchQueue.main.async {
                self.injectButton.isEnabled = true
                self.injectButton.title = "🔌 CDP 注入启动"
                self.refreshStatus()
            }
        }
    }

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

    @objc func autoTextChanged() {
        textColorWell.isEnabled = autoTextCheckbox.state != .on
        if autoTextCheckbox.state == .on, let src = currentConfig["source"] as? String, !src.isEmpty {
            analyzeTextColor(src)
        }
        updateConfig()
    }

    func analyzeTextColor(_ path: String) {
        DispatchQueue.global().async {
            guard let image = NSImage(contentsOfFile: path),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let w = min(cgImage.width, 100), h = min(cgImage.height, 100)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let data = ctx.data else { return }
            let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            var r: Double = 0, g: Double = 0, b: Double = 0, count: Double = 0
            for i in stride(from: 0, to: w * h * 4, by: 4) {
                r += Double(pixels[i]); g += Double(pixels[i+1]); b += Double(pixels[i+2]); count += 1
            }
            let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / count / 255
            DispatchQueue.main.async {
                if self.autoTextCheckbox.state == .on {
                    self.textColorWell.color = luminance > 0.5 ? .black : .white
                    self.updateConfig()
                }
            }
        }
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

        currentConfig["autoText"] = autoTextCheckbox.state == .on
        if autoTextCheckbox.state == .on {
            currentConfig["textColor"] = "auto"
        } else {
            let c = textColorWell.color.usingColorSpace(.sRGB)!
            currentConfig["textColor"] = String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }

        let themeValues = ["purple", "blue", "green", "orange", "rose", "slate", "midnight"]
        currentConfig["theme"] = themeValues[themePopup.indexOfSelectedItem]

        // 更新启动按钮文字
        startButton.title = enabledCheckbox.state == .on ? "⏹️ 停止背景（支持图片 JPG/PNG/GIF、视频 MP4/MOV/WebM）" : "🎬 启动背景（支持图片 JPG/PNG/GIF、视频 MP4/MOV/WebM）"
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
                if let blur = json["blur"] as? String, let idx = blurValues.firstIndex(of: blur) { self.blurPopup.selectItem(at: idx) }
                let scaleValues = ["cover", "contain", "fill"]
                if let scale = json["scale"] as? String, let idx = scaleValues.firstIndex(of: scale) { self.scalePopup.selectItem(at: idx) }
                let positionValues = ["center", "top", "bottom", "left", "right"]
                if let pos = json["position"] as? String, let idx = positionValues.firstIndex(of: pos) { self.positionPopup.selectItem(at: idx) }
                let tc = json["textColor"] as? String ?? ""
                let autoText = json["autoText"] as? Bool ?? true
                self.autoTextCheckbox.state = autoText ? .on : .off
                self.textColorWell.isEnabled = !autoText
                if !autoText && !tc.isEmpty && tc != "auto" && tc.hasPrefix("#") {
                    self.textColorWell.color = NSColorFromHex(tc) ?? .white
                }
                if autoText, let src = json["source"] as? String, !src.isEmpty {
                    self.analyzeTextColor(src)
                }
                let themeValues = ["purple", "blue", "green", "orange", "rose", "slate", "midnight"]
                if let th = json["theme"] as? String, let idx = themeValues.firstIndex(of: th) { self.themePopup.selectItem(at: idx) }
                self.updateConfig()
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
        } else { loadConfig() }
    }

    func checkPort(_ port: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/nc"
        task.arguments = ["-z", "-w", "1", "localhost", String(port)]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.launch(); task.waitUntilExit()
        return task.terminationStatus == 0
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

func NSColorFromHex(_ hex: String) -> NSColor? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((n >> 16) & 0xFF) / 255,
                   green: CGFloat((n >> 8) & 0xFF) / 255,
                   blue: CGFloat(n & 0xFF) / 255, alpha: 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
