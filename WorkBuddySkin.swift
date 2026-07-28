import Cocoa
import UniformTypeIdentifiers
import AVFoundation

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

class StatusCard: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")
    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.05, blue: 0.12, alpha: 0.6).cgColor
        layer?.cornerRadius = 10; layer?.borderWidth = 1
        layer?.borderColor = NSColor.accentPink.withAlphaComponent(0.15).cgColor
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .textHint; titleLabel.alignment = .center; titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        valueLabel.stringValue = "—"
        valueLabel.font = NSFont.boldSystemFont(ofSize: 14)
        valueLabel.textColor = .textBody; valueLabel.alignment = .center; valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            heightAnchor.constraint(equalToConstant: 56)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ value: String, _ ok: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.valueLabel.stringValue = value
            self?.valueLabel.textColor = ok ? .statusOk : .statusErr
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!; var statusItem: NSStatusItem!
    var wbCard: StatusCard!, cdpCard: StatusCard!, daemonCard: StatusCard!, bgCard: StatusCard!
    var startButton: NSButton!, injectButton: NSButton!
    var selectFileButton: NSButton!, clearButton: NSButton!
    var autoTextBtn: NSButton!, textColorWell: NSColorWell!
    var autoTextOn = true
    var opacitySlider: NSSlider!, overlaySlider: NSSlider!
    var opacityValueLabel: NSTextField!, overlayValueLabel: NSTextField!
    var blurPopup: NSPopUpButton!, scalePopup: NSPopUpButton!, positionPopup: NSPopUpButton!, themePopup: NSPopUpButton!
    var filePathLabel: NSTextField!
    var previewView: NSView!
    var previewImageView: NSImageView!
    let daemonURL = "http://localhost:17890"
    var currentConfig: [String: Any] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar(); createWindow(); startDaemonIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshStatus(); self.loadConfig(); self.updateMenuStatus() }
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in self.refreshStatus(); self.updateMenuStatus() }
    }

    func createWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 820), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "WorkBuddy-Skin"; window.titlebarAppearsTransparent = true; window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true

        // 流体玻璃背景
        let blurView = NSVisualEffectView()
        blurView.blendingMode = .behindWindow
        blurView.material = .hudWindow
        blurView.state = .active
        window.contentView = blurView

        let root = NSView()
        blurView.addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: blurView.topAnchor),
            root.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: blurView.bottomAnchor)
        ])

        let main = NSStackView(); main.orientation = .vertical; main.spacing = 14
        main.edgeInsets = NSEdgeInsets(top: 36, left: 24, bottom: 16, right: 24)
        main.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: root.topAnchor),
            main.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        // ── 标题
        let titleLabel = NSTextField(labelWithString: "WorkBuddy-Skin 背景注入管理器 v1.0.0")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 22); titleLabel.textColor = .textTitle; titleLabel.alignment = .center
        main.addArrangedSubview(titleLabel)
        main.setCustomSpacing(24, after: titleLabel)

        // ══ 背景设置 ══
        main.addArrangedSubview(sectionHeader("背景设置"))

        let fileRow = hstack([
            makeBtn("选择文件", "folder", #selector(selectFile)),
            makeBtn("清除背景", "trash", #selector(clearBackground))
        ], equalWidth: true)
        main.addArrangedSubview(fileRow)

        // 预览
        previewView = NSView(); previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.05, blue: 0.12, alpha: 0.5).cgColor; previewView.layer?.cornerRadius = 10
        previewView.layer?.borderWidth = 1; previewView.layer?.borderColor = NSColor.accentPink.withAlphaComponent(0.12).cgColor
        previewView.heightAnchor.constraint(equalToConstant: 50).isActive = true
        main.addArrangedSubview(previewView)
        previewImageView = NSImageView(); previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter; previewImageView.isHidden = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(previewImageView)
        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: previewView.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor)
        ])
        let noPreview = NSTextField(labelWithString: "图片/视频 缩略图预览")
        noPreview.font = NSFont.systemFont(ofSize: 13); noPreview.textColor = .textHint; noPreview.alignment = .center
        noPreview.tag = 999; noPreview.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(noPreview)
        NSLayoutConstraint.activate([noPreview.centerXAnchor.constraint(equalTo: previewView.centerXAnchor), noPreview.centerYAnchor.constraint(equalTo: previewView.centerYAnchor)])

        // 文件路径
        filePathLabel = NSTextField(labelWithString: "未选择文件")
        filePathLabel.font = NSFont.systemFont(ofSize: 12); filePathLabel.textColor = .textHint
        filePathLabel.alignment = .center; filePathLabel.lineBreakMode = .byTruncatingMiddle
        main.addArrangedSubview(filePathLabel)

        // 启动按钮 + 自动配色
        let ctrlRow = NSStackView(); ctrlRow.spacing = 10; ctrlRow.distribution = .fillEqually
        startButton = makeBtn("启动背景", "play.rectangle", #selector(toggleBackground))
        ctrlRow.addArrangedSubview(startButton)
        autoTextBtn = makeBtn("文字自动配色", "checkmark.square.fill", #selector(autoTextToggled))
        ctrlRow.addArrangedSubview(autoTextBtn)
        main.addArrangedSubview(ctrlRow)

        // 取色板（独立行）
        let wellRow = NSStackView(); wellRow.spacing = 8
        textColorWell = NSColorWell(); textColorWell.color = .white; textColorWell.isEnabled = false
        textColorWell.target = self; textColorWell.action = #selector(updateConfig)
        textColorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true
        wellRow.addArrangedSubview(textColorWell)
        let hint = NSTextField(labelWithString: "选色后自动关闭文字自动配色")
        hint.font = NSFont.systemFont(ofSize: 11); hint.textColor = .textHint
        wellRow.addArrangedSubview(hint)
        main.addArrangedSubview(wellRow)

        // 四个下拉
        let d1 = hstack([
            popup(["主题: 暗紫", "主题: 暗蓝", "主题: 暗绿", "主题: 暖橙", "主题: 玫瑰", "主题: 石板", "主题: 午夜"]),
            popup(["模糊: 无", "模糊: 轻微", "模糊: 中等", "模糊: 强烈"])
        ], equalWidth: true)
        themePopup = d1.arrangedSubviews[0] as? NSPopUpButton
        blurPopup = d1.arrangedSubviews[1] as? NSPopUpButton
        main.addArrangedSubview(d1)
        let d2 = hstack([
            popup(["填充: 覆盖", "填充: 包含", "填充: 填充"]),
            popup(["位置: 居中", "位置: 顶部", "位置: 底部", "位置: 左", "位置: 右"])
        ], equalWidth: true)
        scalePopup = d2.arrangedSubviews[0] as? NSPopUpButton
        positionPopup = d2.arrangedSubviews[1] as? NSPopUpButton
        main.addArrangedSubview(d2)

        // 滑块 - 各占一行
        let sv1 = sliderView("背景透明度", 10, 100, 100) as! NSStackView
        opacitySlider = sv1.arrangedSubviews[1] as? NSSlider
        opacityValueLabel = sv1.arrangedSubviews[2] as? NSTextField
        main.addArrangedSubview(sv1)

        let sv2 = sliderView("背景暗色遮罩", 0, 80, 50) as! NSStackView
        overlaySlider = sv2.arrangedSubviews[1] as? NSSlider
        overlayValueLabel = sv2.arrangedSubviews[2] as? NSTextField
        main.addArrangedSubview(sv2)

        // ══ 快速操作 ══
        main.setCustomSpacing(20, after: sv2)
        main.addArrangedSubview(sectionHeader("快速操作"))
        let qRow = hstack([
            { injectButton = $0; return $0 }(makeBtn("CDP 注入启动", "bolt.fill", #selector(startWorkBuddy))),
            makeBtn("刷新状态", "arrow.clockwise", #selector(refreshStatus))
        ], equalWidth: true)
        main.addArrangedSubview(qRow)

        // ══ 状态监测 ══
        main.setCustomSpacing(20, after: qRow)
        main.addArrangedSubview(sectionHeader("状态监测"))
        wbCard = StatusCard(title: "WorkBuddy"); cdpCard = StatusCard(title: "CDP 端口")
        daemonCard = StatusCard(title: "守护进程"); bgCard = StatusCard(title: "背景状态")
        let statusRow = hstack([wbCard, cdpCard, daemonCard, bgCard], equalWidth: true)
        main.addArrangedSubview(statusRow)

        // ══ 页脚 ══
        main.setCustomSpacing(16, after: statusRow)
        let footer = NSTextField(labelWithString: "YiIimini  |  GitHub")
        footer.font = NSFont.systemFont(ofSize: 11); footer.textColor = .textHint; footer.alignment = .center
        let fa = NSMutableAttributedString(string: "YiIimini  |  GitHub")
        fa.addAttribute(.link, value: "https://github.com/YiIimini/WorkBuddy-Skin", range: (fa.string as NSString).range(of: "GitHub"))
        fa.addAttribute(.foregroundColor, value: NSColor.textHint, range: NSRange(location: 0, length: fa.length))
        footer.attributedStringValue = fa; footer.allowsEditingTextAttributes = true; footer.isSelectable = true
        main.addArrangedSubview(footer)
    }

    // ══ UI helpers ══
    func sectionHeader(_ t: String) -> NSView {
        let v = NSStackView(); v.spacing = 8
        let l = NSTextField(labelWithString: t); l.font = NSFont.boldSystemFont(ofSize: 13); l.textColor = .accentPink
        v.addArrangedSubview(l)
        let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = NSColor.accentPink.withAlphaComponent(0.2).cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        v.addArrangedSubview(line)
        return v
    }
    func hstack(_ views: [NSView], equalWidth: Bool) -> NSStackView {
        let s = NSStackView(); s.spacing = 10; s.distribution = equalWidth ? .fillEqually : .fill
        views.forEach { s.addArrangedSubview($0) }
        return s
    }
    func makeBtn(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded; b.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); b.imagePosition = .imageLeading
        return b
    }
    func popup(_ items: [String]) -> NSPopUpButton {
        let p = NSPopUpButton(); p.addItems(withTitles: items); p.font = NSFont.systemFont(ofSize: 11)
        p.target = self; p.action = #selector(updateConfig); return p
    }
    func sliderView(_ title: String, _ min: Double, _ max: Double, _ initVal: Double) -> NSStackView {
        let v = NSStackView(); v.spacing = 6
        let l = NSTextField(labelWithString: title); l.font = NSFont.systemFont(ofSize: 11); l.textColor = .textLabel
        v.addArrangedSubview(l)
        let s = NSSlider(value: initVal, minValue: min, maxValue: max, target: self, action: #selector(sliderChanged))
        s.widthAnchor.constraint(equalToConstant: 280).isActive = true
        v.addArrangedSubview(s)
        let vl = NSTextField(labelWithString: "\(Int(initVal))%")
        vl.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular); vl.textColor = .textLabel
        vl.widthAnchor.constraint(equalToConstant: 40).isActive = true
        v.addArrangedSubview(vl)
        return v
    }

    // ══ 菜单栏 ══
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let icon = NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") { icon.size = NSSize(width: 18, height: 18); btn.image = icon }
            else { btn.title = "✦" }
        }
        let m = NSMenu()
        let o = m.addItem(withTitle: "打开应用窗口", action: #selector(showWindow), keyEquivalent: "o"); o.target = self
        m.addItem(NSMenuItem.separator())
        let i = m.addItem(withTitle: "CDP 注入启动", action: #selector(menuStartWorkBuddy), keyEquivalent: ""); i.target = self
        let t = m.addItem(withTitle: "启用背景", action: #selector(menuToggleBackground), keyEquivalent: ""); t.target = self; t.tag = 100
        m.addItem(NSMenuItem.separator())
        let sm = NSMenu()
        sm.addItem(withTitle: "守护进程: —", action: nil, keyEquivalent: "").tag = 201
        sm.addItem(withTitle: "CDP 端口: —", action: nil, keyEquivalent: "").tag = 202
        sm.addItem(withTitle: "背景状态: —", action: nil, keyEquivalent: "").tag = 203
        let si = m.addItem(withTitle: "状态", action: nil, keyEquivalent: ""); si.submenu = sm
        m.addItem(NSMenuItem.separator())
        let r = m.addItem(withTitle: "刷新状态", action: #selector(menuRefreshStatus), keyEquivalent: ""); r.target = self
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "退出 WorkBuddy-Skin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func menuStartWorkBuddy() { startWorkBuddy() }
    @objc func menuToggleBackground() { autoTextToggled(); updateMenuStatus(); showWindow() }
    @objc func menuRefreshStatus() { refreshStatus(); updateMenuStatus() }
    func updateMenuStatus() {
        DispatchQueue.global().async {
            let daemonOk = self.checkPort(17890), cdpOk = self.checkPort(9222)
            let bgActive = (self.currentConfig["enabled"] as? Bool ?? false) && !(self.currentConfig["source"] as? String ?? "").isEmpty
            DispatchQueue.main.async {
                if let i = self.statusItem.menu?.item(withTag: 201) { i.title = "守护进程: " + (daemonOk ? "✓" : "✗") }
                if let i = self.statusItem.menu?.item(withTag: 202) { i.title = "CDP 端口: " + (cdpOk ? "✓" : "✗") }
                if let i = self.statusItem.menu?.item(withTag: 203) { i.title = "背景状态: " + (bgActive ? "✓" : "✗") }
                if let i = self.statusItem.menu?.item(withTag: 100) { i.title = bgActive ? "停用背景" : "启用背景" }
            }
        }
    }

    // ══ 预览 ══
    func showPreview(_ path: String) {
        previewImageView.image = nil; previewImageView.isHidden = true
        (previewView.viewWithTag(999) as? NSTextField)?.isHidden = false
        let ext = (path as NSString).pathExtension.lowercased()
        if ["mp4","webm","mov","avi","mkv","m4v"].contains(ext) {
            DispatchQueue.global().async {
                let asset = AVURLAsset(url: URL(fileURLWithPath: path))
                let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 712, height: 400)
                do { let cg = try gen.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
                    let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    DispatchQueue.main.async { self.previewImageView.image = img; self.previewImageView.isHidden = false; (self.previewView.viewWithTag(999) as? NSTextField)?.isHidden = true; self.updatePreviewHeight(img.size) }
                } catch { DispatchQueue.main.async { self.previewFailed() } }
            }
        } else if let img = NSImage(contentsOfFile: path) {
            previewImageView.image = img; previewImageView.isHidden = false
            (previewView.viewWithTag(999) as? NSTextField)?.isHidden = true; updatePreviewHeight(img.size)
        } else { previewFailed() }
        filePathLabel.stringValue = path
    }
    func updatePreviewHeight(_ size: NSSize) {
        let maxW: CGFloat = 712, maxH: CGFloat = 200; var h: CGFloat = 50
        if size.width > 0 { h = min(maxW * size.height / size.width, maxH); if h < 50 { h = 50 } }
        previewView.constraints.forEach { if $0.firstAttribute == .height { $0.constant = h } }
    }
    func previewFailed() { (previewView.viewWithTag(999) as? NSTextField)?.stringValue = "无法预览"; (previewView.viewWithTag(999) as? NSTextField)?.isHidden = false; previewImageView.isHidden = true }
    func clearPreview() { previewImageView.image = nil; previewImageView.isHidden = true; (previewView.viewWithTag(999) as? NSTextField)?.stringValue = "图片/视频 缩略图预览"; (previewView.viewWithTag(999) as? NSTextField)?.isHidden = false
        previewView.constraints.forEach { if $0.firstAttribute == .height { $0.constant = 50 } }
        filePathLabel.stringValue = "未选择文件" }

    // ══ 操作 ══
    @objc func toggleBackground() {
        currentConfig["enabled"] = !(currentConfig["enabled"] as? Bool ?? false)
        let on = currentConfig["enabled"] as? Bool ?? false
        startButton.title = on ? "停止背景" : "启动背景"
        startButton.image = NSImage(systemSymbolName: on ? "stop.rectangle" : "play.rectangle", accessibilityDescription: nil)
        updateConfig()
    }
    @objc func autoTextToggled() {
        autoTextOn.toggle()
        autoTextBtn.image = NSImage(systemSymbolName: autoTextOn ? "checkmark.square.fill" : "square", accessibilityDescription: nil)
        textColorWell.isEnabled = !autoTextOn
        if autoTextOn, let src = currentConfig["source"] as? String, !src.isEmpty { analyzeTextColor(src) }
        updateConfig()
    }
    func analyzeTextColor(_ path: String) {
        DispatchQueue.global().async {
            guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let w = min(cg.width, 100), h = min(cg.height, 100)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let d = ctx.data else { return }; let pixels = d.bindMemory(to: UInt8.self, capacity: w*h*4)
            var r: Double = 0, g: Double = 0, b: Double = 0, c: Double = 0
            for i in stride(from: 0, to: w*h*4, by: 4) { r += Double(pixels[i]); g += Double(pixels[i+1]); b += Double(pixels[i+2]); c += 1 }
            let lum = (0.299*r + 0.587*g + 0.114*b) / c / 255
            DispatchQueue.main.async { if self.autoTextOn { self.textColorWell.color = lum > 0.5 ? .black : .white; self.updateConfig() } }
        }
    }
    @objc func startWorkBuddy() {
        injectButton.isEnabled = false; injectButton.title = "启动中..."
        DispatchQueue.global().async {
            let q = Process(); q.launchPath = "/usr/bin/osascript"; q.arguments = ["-e", "tell application \"WorkBuddy\" to quit"]
            q.standardOutput = FileHandle.nullDevice; q.standardError = FileHandle.nullDevice; q.launch(); q.waitUntilExit()
            Thread.sleep(forTimeInterval: 3)
            let t = Process(); t.launchPath = "/bin/bash"; t.arguments = ["\(NSHomeDirectory())/WorkBuddy-Skin/launcher.sh"]
            t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice; t.launch()
            var w = 0; while w < 30 { Thread.sleep(forTimeInterval: 1); w += 1; if self.checkPort(9222) { break } }
            DispatchQueue.main.async { self.injectButton.isEnabled = true; self.injectButton.title = "CDP 注入启动"; self.refreshStatus() }
        }
    }
    @objc func refreshStatus() {
        DispatchQueue.global().async {
            let d = self.checkPort(17890), c = self.checkPort(9222)
            self.daemonCard.update(d ? "运行中" : "未运行", d); self.cdpCard.update(c ? "已开放" : "未开放", c); self.wbCard.update(c ? "运行中" : "未运行", c)
            if let e = self.currentConfig["enabled"] as? Bool, let s = self.currentConfig["source"] as? String { self.bgCard.update(e && !s.isEmpty ? "已启用" : "未启用", e && !s.isEmpty) }
        }
    }
    @objc func selectFile() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = false; p.canChooseDirectories = false; p.canChooseFiles = true
        p.message = "选择背景图片或视频"; p.allowedContentTypes = [UTType.movie, UTType.video, UTType.image]
        p.begin { [weak self] r in guard let self = self, r == .OK, let url = p.url else { return }
            let ext = url.pathExtension.lowercased()
            self.currentConfig["source"] = url.path; self.currentConfig["type"] = ["mp4","webm","mov","avi","mkv","m4v"].contains(ext) ? "video" : "image"
            self.currentConfig["enabled"] = true; self.filePathLabel.stringValue = url.path; self.showPreview(url.path); self.updateConfig() }
    }
    @objc func clearBackground() { currentConfig["enabled"] = false; currentConfig["source"] = ""; clearPreview(); updateConfig() }
    @objc func sliderChanged() {
        opacityValueLabel.stringValue = "\(Int(opacitySlider.doubleValue))%"
        overlayValueLabel.stringValue = "\(Int(overlaySlider.doubleValue))%"
        updateConfig()
    }
    @objc func updateConfig() {
        currentConfig["enabled"] = currentConfig["enabled"] ?? false
        currentConfig["opacity"] = opacitySlider.doubleValue / 100; currentConfig["overlay"] = overlaySlider.doubleValue / 100
        currentConfig["blur"] = ["0px","5px","10px","20px"][blurPopup.indexOfSelectedItem]
        currentConfig["scale"] = ["cover","contain","fill"][scalePopup.indexOfSelectedItem]
        currentConfig["position"] = ["center","top","bottom","left","right"][positionPopup.indexOfSelectedItem]
        currentConfig["autoText"] = autoTextOn
        if autoTextOn { currentConfig["textColor"] = "auto" }
        else { let c = textColorWell.color.usingColorSpace(.sRGB)!; currentConfig["textColor"] = String(format: "#%02x%02x%02x", Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255)) }
        currentConfig["theme"] = ["purple","blue","green","orange","rose","slate","midnight"][themePopup.indexOfSelectedItem]
        saveConfig()
    }
    func loadConfig() {
        guard let url = URL(string: "\(daemonURL)/api/config") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] d, _, _ in guard let self = self, let d = d, let j = try? JSONSerialization.jsonObject(with: d) as? [String:Any] else { return }
            DispatchQueue.main.async {
                self.currentConfig = j
                self.opacitySlider.doubleValue = (j["opacity"] as? Double ?? 1)*100; self.overlaySlider.doubleValue = (j["overlay"] as? Double ?? 0.5)*100
                if let src = j["source"] as? String, !src.isEmpty { self.filePathLabel.stringValue = src; self.showPreview(src) }
                if let b = j["blur"] as? String, let i = ["0px","5px","10px","20px"].firstIndex(of: b) { self.blurPopup.selectItem(at: i) }
                if let s = j["scale"] as? String, let i = ["cover","contain","fill"].firstIndex(of: s) { self.scalePopup.selectItem(at: i) }
                if let p = j["position"] as? String, let i = ["center","top","bottom","left","right"].firstIndex(of: p) { self.positionPopup.selectItem(at: i) }
                let auto = j["autoText"] as? Bool ?? true; self.autoTextOn = auto
                self.autoTextBtn.image = NSImage(systemSymbolName: auto ? "checkmark.square.fill" : "square", accessibilityDescription: nil)
                self.textColorWell.isEnabled = !auto
                if !auto, let tc = j["textColor"] as? String, tc != "auto", tc.hasPrefix("#") { self.textColorWell.color = NSColorFromHex(tc) ?? .white }
                if auto, let src = j["source"] as? String, !src.isEmpty { self.analyzeTextColor(src) }
                if let t = j["theme"] as? String, let i = ["purple","blue","green","orange","rose","slate","midnight"].firstIndex(of: t) { self.themePopup.selectItem(at: i) }
                self.refreshStatus()
            }
        }.resume()
    }
    func saveConfig() { guard let u = URL(string: "\(daemonURL)/api/config") else { return }; var r = URLRequest(url: u); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: currentConfig); URLSession.shared.dataTask(with: r).resume() }
    func startDaemonIfNeeded() {
        if !checkPort(17890) { DispatchQueue.global().async { let t = Process(); t.launchPath = "/Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node"; t.arguments = ["\(NSHomeDirectory())/WorkBuddy-Skin/daemon.js"]; t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice; try? t.run(); Thread.sleep(forTimeInterval: 3); DispatchQueue.main.async { self.loadConfig() } } }
        else { loadConfig() }
    }
    func checkPort(_ p: Int) -> Bool { let t = Process(); t.launchPath = "/usr/bin/nc"; t.arguments = ["-z","-w","1","localhost",String(p)]; t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice; t.launch(); t.waitUntilExit(); return t.terminationStatus == 0 }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

func NSColorFromHex(_ hex: String) -> NSColor? { var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(); if s.hasPrefix("#") { s.removeFirst() }; guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }; return NSColor(srgbRed: CGFloat((n>>16)&0xFF)/255, green: CGFloat((n>>8)&0xFF)/255, blue: CGFloat(n&0xFF)/255, alpha: 1) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
