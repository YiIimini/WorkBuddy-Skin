import Cocoa
import UniformTypeIdentifiers
import AVFoundation
import Darwin

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

// MARK: - 系统监测模块

enum MetricKind: String, CaseIterable {
    case cpu = "CPU"; case gpu = "GPU"; case ram = "RAM"; case ssd = "SSD"; case net = "NET"
}

func runCmd(_ launchPath: String, _ args: [String]) -> String? {
    let p = Process(); p.launchPath = launchPath; p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    p.launch(); p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}

class SystemMonitor {
    private var cpuPrev: host_cpu_load_info?
    private var netPrevIn: UInt64 = 0, netPrevOut: UInt64 = 0, netPrevT: TimeInterval = 0
    private var netIface: String = "en0"
    let cpuModel: String
    let memTotalBytes: UInt64
    let coreCount: Int
    let physicalCores: Int

    init() {
        cpuModel = Self.sysctlStr("machdep.cpu.brand_string")
        memTotalBytes = Self.sysctlU64("hw.memsize")
        coreCount = Self.sysctlInt("hw.ncpu")
        physicalCores = Self.sysctlInt("hw.physicalcpu")
        netIface = Self.primaryInterface()
    }

    private static func sysctlStr(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }
    private static func sysctlInt(_ name: String) -> Int {
        var val: Int = 0; var size = MemoryLayout<Int>.size
        sysctlbyname(name, &val, &size, nil, 0); return val
    }
    private static func sysctlU64(_ name: String) -> UInt64 {
        var val: UInt64 = 0; var size = MemoryLayout<UInt64>.size
        sysctlbyname(name, &val, &size, nil, 0); return val
    }
    private static func primaryInterface() -> String {
        if let o = runCmd("/sbin/route", ["-n", "get", "default"]),
           let r = o.range(of: "interface: ") {
            let rest = o[r.upperBound...]
            if let e = rest.firstIndex(of: "\n") {
                return String(rest[..<e]).trimmingCharacters(in: .whitespaces)
            }
        }
        return "en0"
    }

    func cpuUsage() -> (total: Double, user: Double, system: Double, nice: Double) {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let ret = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, ptr, &count)
            }
        }
        guard ret == KERN_SUCCESS else { return (0,0,0,0) }
        let u = Double(info.cpu_ticks.0), s = Double(info.cpu_ticks.1)
        let i = Double(info.cpu_ticks.2), n = Double(info.cpu_ticks.3)
        let tot = u + s + i + n
        if let prev = cpuPrev {
            let dTot = tot - Double(prev.cpu_ticks.0 + prev.cpu_ticks.1 + prev.cpu_ticks.2 + prev.cpu_ticks.3)
            let dIdle = i - Double(prev.cpu_ticks.2)
            cpuPrev = info
            if dTot > 0 {
                return ((dTot - dIdle)/dTot*100,
                        (u - Double(prev.cpu_ticks.0))/dTot*100,
                        (s - Double(prev.cpu_ticks.1))/dTot*100,
                        (n - Double(prev.cpu_ticks.3))/dTot*100)
            }
            return (0,0,0,0)
        }
        cpuPrev = info
        return (0,0,0,0)
    }

    func memUsage() -> (usedGB: Double, totalGB: Double, wiredGB: Double, compressedGB: Double) {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var info = vm_statistics64()
        let ret = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, ptr, &count)
            }
        }
        guard ret == KERN_SUCCESS else { return (0, Double(memTotalBytes)/1e9, 0, 0) }
        let ps = Double(vm_kernel_page_size)
        let totalPages = Double(memTotalBytes) / ps
        // 已用 ≈ 总页数 − 空闲 − 投机(可回收)，与 Activity Monitor「内存已用」接近
        let usedPages = totalPages - Double(info.free_count) - Double(info.speculative_count)
        let wired = Double(info.wire_count) * ps
        let compressed = Double(info.compressions) * ps
        return (max(usedPages,0)*ps/1e9, Double(memTotalBytes)/1e9, wired/1e9, compressed/1e9)
    }

    func netSample() -> (upMBps: Double, downMBps: Double, iface: String) {
        guard let o = runCmd("/usr/sbin/netstat", ["-ib", "-I", netIface, "-n"]) else { return (0,0,netIface) }
        let lines = o.split(separator: "\n")
        guard lines.count >= 2 else { return (0,0,netIface) }
        let header = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        let dataLine = lines.first(where: { $0.contains("Link#") }) ?? lines[1]
        let data = dataLine.split(separator: " ", omittingEmptySubsequences: true)
        guard let iI = header.firstIndex(of: "Ibytes"), let iO = header.firstIndex(of: "Obytes"),
              data.count > iI, data.count > iO,
              let ib = UInt64(data[iI]), let ob = UInt64(data[iO]) else { return (0,0,netIface) }
        let now = Date().timeIntervalSince1970
        if netPrevT > 0 {
            let dt = now - netPrevT
            if dt > 0 {
                let down = Double(ib &- netPrevIn)/dt/1e6
                let up = Double(ob &- netPrevOut)/dt/1e6
                netPrevIn = ib; netPrevOut = ob; netPrevT = now
                return (max(up,0), max(down,0), netIface)
            }
        }
        netPrevIn = ib; netPrevOut = ob; netPrevT = now
        return (0,0,netIface)
    }

    func ssdThroughput() -> Double {
        // -d: 仅磁盘统计; -c 2 -w 1: 连续 2 次、间隔 1 秒; 末行即最近 1 秒区间样本
        guard let o = runCmd("/usr/sbin/iostat", ["-d", "-c", "2", "-w", "1", "disk0"]),
              let lastRow = o.split(separator: "\n").last(where: { $0.trimmingCharacters(in: .whitespaces).first?.isNumber == true })
        else { return 0 }
        // 列: KB/t  tps  MB/s —— MB/s 在 index 2（读取+写入总吞吐）
        let cols = lastRow.split(separator: " ", omittingEmptySubsequences: true)
        if cols.count >= 3, let mbps = Double(cols[2]) { return mbps }
        return 0
    }
}

class SysTile: NSView {
    let kind: MetricKind
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "—")
    var onSelect: (MetricKind) -> Void = { _ in }
    init(kind: MetricKind, onSelect: @escaping (MetricKind) -> Void) {
        self.kind = kind; self.onSelect = onSelect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.06, blue: 0.15, alpha: 0.75).cgColor
        layer?.cornerRadius = 10; layer?.borderWidth = 1
        layer?.borderColor = NSColor.accentPink.withAlphaComponent(0.25).cgColor
        titleLabel.stringValue = kind.rawValue
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .textHint; titleLabel.alignment = .center; titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
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
        let ta = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(ta)
    }
    override func mouseDown(with event: NSEvent) { onSelect(kind) }
    override func mouseEntered(with event: NSEvent) { anim(0.8); NSCursor.pointingHand.push() }
    override func mouseExited(with event: NSEvent) { anim(0.15); NSCursor.pop() }
    func anim(_ a: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15
            self.layer?.borderColor = NSColor.accentPink.withAlphaComponent(a).cgColor
        }
    }
    func update(_ value: String) { DispatchQueue.main.async { self.valueLabel.stringValue = value } }
    required init?(coder: NSCoder) { fatalError() }
}

class SysDetailPanel: NSPanel {
    let kind: MetricKind
    let valueLabel = NSTextField(labelWithString: "")
    let detailStack = NSStackView()
    var actionButtons: [NSButton] = []
    var onAuthorizeGPU: (() -> Void)?
    var onStopGPU: (() -> Void)?
    var onCleanJunk: (() -> Void)?
    var onManageProcesses: (() -> Void)?
    var onClose: (() -> Void)?

    init(kind: MetricKind) {
        self.kind = kind
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = "系统监测 · \(kind.rawValue)"
        self.appearance = NSAppearance(named: .darkAqua)
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.backgroundColor = NSColor(srgbRed: 0.10, green: 0.06, blue: 0.15, alpha: 0.97)
        self.isReleasedWhenClosed = false

        let root = NSView(); self.contentView = root

        valueLabel.font = NSFont.boldSystemFont(ofSize: 30)
        valueLabel.textColor = .accentPink
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(valueLabel)

        detailStack.orientation = .vertical
        detailStack.spacing = 8
        detailStack.alignment = .centerX
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(detailStack)

        func makeBtn(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            b.translatesAutoresizingMaskIntoConstraints = false
            return b
        }
        switch kind {
        case .gpu:
            actionButtons.append(makeBtn("授权 GPU 监测", #selector(gpuClicked)))
        case .ram:
            actionButtons.append(makeBtn("清理垃圾", #selector(cleanClicked)))
            actionButtons.append(makeBtn("进程管理", #selector(procClicked)))
        default: break
        }
        for b in actionButtons { root.addSubview(b) }

        let closeBtn = NSButton(title: "关闭", target: self, action: #selector(closeClicked))
        closeBtn.bezelStyle = .rounded
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(closeBtn)

        var cons: [NSLayoutConstraint] = [
            valueLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 54),
            valueLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            valueLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            detailStack.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 18),
            detailStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            detailStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            closeBtn.centerXAnchor.constraint(equalTo: root.centerXAnchor)
        ]
        var prev: NSView? = detailStack
        for b in actionButtons {
            cons.append(b.topAnchor.constraint(equalTo: prev!.bottomAnchor, constant: 10))
            cons.append(b.centerXAnchor.constraint(equalTo: root.centerXAnchor))
            prev = b
        }
        cons.append(closeBtn.topAnchor.constraint(equalTo: prev!.bottomAnchor, constant: 16))
        NSLayoutConstraint.activate(cons)
    }
    override func close() { onClose?(); super.close() }
    @objc func gpuClicked() {
        if actionButtons.first?.title.contains("授权") == true { onAuthorizeGPU?() } else { onStopGPU?() }
    }
    @objc func cleanClicked() { onCleanJunk?() }
    @objc func procClicked() { onManageProcesses?() }
    @objc func closeClicked() { onClose?() }
    func setValue(_ value: String, details: [String], gpuAuthorized: Bool) {
        valueLabel.stringValue = value
        detailStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for d in details {
            let t = NSTextField(labelWithString: d)
            t.font = NSFont.systemFont(ofSize: 12)
            t.textColor = .textBody
            t.alignment = .center
            t.lineBreakMode = .byWordWrapping
            t.preferredMaxLayoutWidth = 412
            detailStack.addArrangedSubview(t)
        }
        if kind == .gpu {
            actionButtons.first?.title = gpuAuthorized ? "停止 GPU 监测" : "授权 GPU 监测"
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    var window: NSWindow!; var statusItem: NSStatusItem!
    var wbCard: StatusCard!, cdpCard: StatusCard!, daemonCard: StatusCard!, bgCard: StatusCard!
    var startButton: NSButton!, injectButton: NSButton!, stopButton: NSButton!
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

    // 系统监测
    let sysMonitor = SystemMonitor()
    var sysTiles: [MetricKind: SysTile] = [:]
    var detailPanel: SysDetailPanel?
    var gpuAuthorized = false
    var lastCPU: (total: Double, user: Double, system: Double, nice: Double) = (0,0,0,0)
    var lastMem: (usedGB: Double, totalGB: Double, wiredGB: Double, compressedGB: Double) = (0,0,0,0)
    var lastNet: (upMBps: Double, downMBps: Double, iface: String) = (0,0,"en0")
    var lastSSD: Double = 0
    var lastGPU: Double? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupMenuBar(); createWindow(); startDaemonIfNeeded()
        // 用 NotificationCenter 处理 Dock 点击，不依赖 weak delegate
        NotificationCenter.default.addObserver(self, selector: #selector(handleReopen), name: NSApplication.didBecomeActiveNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshStatus(); self.loadConfig(); self.updateMenuStatus() }
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in self.refreshStatus(); self.updateMenuStatus() }
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.scheduleSysSample() }
        scheduleSysSample()
    }

    @objc func handleReopen() {
        guard let w = window, !w.isVisible else { return }
        w.makeKeyAndOrderFront(nil)
    }

    // 关键修复：Dock 图标点击（无论 app 是否已激活）都会触发此委托方法。
    // 原实现只监听 didBecomeActive 通知 —— 关闭窗口后 app 仍是前台应用，
    // 再点 Dock 不会触发该通知，导致窗口永远无法重开。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let w = window {
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
        return true
    }

    func createWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 900), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "WorkBuddy-Skin"; window.titlebarAppearsTransparent = true; window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        // 关键修复：关闭窗口时不释放窗口对象，否则点 "x" 后窗口被销毁，再次打开会崩溃/无反应
        window.isReleasedWhenClosed = false

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
        let titleLabel = NSTextField(labelWithString: "WorkBuddy-Skin 背景注入管理器 v1.1.0")
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

        // 停止 CDP 注入（危险操作，独立成行）
        let stopRow = hstack([
            { stopButton = $0; return $0 }(makeBtn("停止CDP注入", "xmark.circle.fill", #selector(stopInjection)))
        ], equalWidth: true)
        main.addArrangedSubview(stopRow)

        // ══ 状态监测 ══
        main.setCustomSpacing(20, after: qRow)
        main.addArrangedSubview(sectionHeader("状态监测"))
        wbCard = StatusCard(title: "WorkBuddy"); cdpCard = StatusCard(title: "CDP 端口")
        daemonCard = StatusCard(title: "守护进程"); bgCard = StatusCard(title: "背景状态")
        let statusRow = hstack([wbCard, cdpCard, daemonCard, bgCard], equalWidth: true)
        main.addArrangedSubview(statusRow)

        // ══ 系统监测 ══
        main.setCustomSpacing(20, after: statusRow)
        main.addArrangedSubview(sectionHeader("系统监测"))
        let sysRow = NSStackView(); sysRow.spacing = 8; sysRow.distribution = .fillEqually
        for k in [MetricKind.cpu, .gpu, .ram, .ssd, .net] {
            let tile = SysTile(kind: k) { [weak self] kind in self?.openDetail(kind) }
            sysTiles[k] = tile
            sysRow.addArrangedSubview(tile)
        }
        main.addArrangedSubview(sysRow)
        main.setCustomSpacing(16, after: sysRow)

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
        let o = m.addItem(withTitle: "打开应用窗口", action: #selector(showWindow), keyEquivalent: "o"); o.target = AppDelegate.shared
        m.addItem(NSMenuItem.separator())
        let i = m.addItem(withTitle: "CDP 注入启动", action: #selector(menuStartWorkBuddy), keyEquivalent: ""); i.target = AppDelegate.shared
        let t = m.addItem(withTitle: "启用背景", action: #selector(menuToggleBackground), keyEquivalent: ""); t.target = AppDelegate.shared; t.tag = 100
        m.addItem(NSMenuItem.separator())
        let sm = NSMenu()
        sm.addItem(withTitle: "守护进程: —", action: nil, keyEquivalent: "").tag = 201
        sm.addItem(withTitle: "CDP 端口: —", action: nil, keyEquivalent: "").tag = 202
        sm.addItem(withTitle: "背景状态: —", action: nil, keyEquivalent: "").tag = 203
        let si = m.addItem(withTitle: "状态", action: nil, keyEquivalent: ""); si.submenu = sm
        m.addItem(NSMenuItem.separator())
        let r = m.addItem(withTitle: "刷新状态", action: #selector(menuRefreshStatus), keyEquivalent: ""); r.target = AppDelegate.shared
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "退出 WorkBuddy-Skin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }
    @objc func showWindow() {
        guard let w = window else { return }
        w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func menuStartWorkBuddy() { startWorkBuddy() }
    // 修复：此菜单项是"启用/停用背景"，原来错绑成 autoTextToggled（切换文字自动配色）
    @objc func menuToggleBackground() { toggleBackground(); updateMenuStatus() }
    @objc func menuRefreshStatus() { refreshStatus(); updateMenuStatus() }
    func updateMenuStatus() {
        // 关键修复：先在主线程快照 currentConfig（Swift Dictionary 非线程安全，
        // 后台线程读 + 主线程写 = 数据竞争，菜单点击时必然闪退），
        // 后台线程只做端口探测，最后回主线程更新菜单 UI。
        guard Thread.isMainThread else { DispatchQueue.main.async { self.updateMenuStatus() }; return }
        let bgActive = (currentConfig["enabled"] as? Bool ?? false) && !(currentConfig["source"] as? String ?? "").isEmpty
        DispatchQueue.global().async {
            let daemonOk = self.checkPort(17890), cdpOk = self.checkPort(9222)
            DispatchQueue.main.async {
                guard let menu = self.statusItem?.menu else { return }
                if let i = menu.item(withTag: 201) { i.title = "守护进程: " + (daemonOk ? "✓" : "✗") }
                if let i = menu.item(withTag: 202) { i.title = "CDP 端口: " + (cdpOk ? "✓" : "✗") }
                if let i = menu.item(withTag: 203) { i.title = "背景状态: " + (bgActive ? "✓" : "✗") }
                if let i = menu.item(withTag: 100) { i.title = bgActive ? "停用背景" : "启用背景" }
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
    @objc func stopInjection() {
        let alert = NSAlert()
        alert.messageText = "WorkBuddy程序将退出"
        alert.informativeText = "停止 CDP 注入后，WorkBuddy 将关闭，背景注入守护进程也会一并退出。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "停止并退出")
        if alert.runModal() == .alertSecondButtonReturn {
            callStopInjection()
            // 兜底：直接让 WorkBuddy 退出（覆盖守护进程未连接的情况）
            DispatchQueue.global().async {
                let q = Process(); q.launchPath = "/usr/bin/osascript"; q.arguments = ["-e", "tell application \"WorkBuddy\" to quit"]
                q.standardOutput = FileHandle.nullDevice; q.standardError = FileHandle.nullDevice; q.launch(); q.waitUntilExit()
            }
            stopButton.title = "已停止"; stopButton.isEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshStatus(); self.updateMenuStatus() }
        }
    }
    func callStopInjection() {
        guard let u = URL(string: "\(daemonURL)/api/stop-injection") else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"
        URLSession.shared.dataTask(with: r).resume()
    }
    @objc func refreshStatus() {
        // 同样的线程安全修复：主线程快照配置，后台仅探测端口
        guard Thread.isMainThread else { DispatchQueue.main.async { self.refreshStatus() }; return }
        let bgActive = (currentConfig["enabled"] as? Bool ?? false) && !(currentConfig["source"] as? String ?? "").isEmpty
        DispatchQueue.global().async {
            let d = self.checkPort(17890), c = self.checkPort(9222)
            self.daemonCard.update(d ? "运行中" : "未运行", d); self.cdpCard.update(c ? "已开放" : "未开放", c); self.wbCard.update(c ? "运行中" : "未运行", c)
            self.bgCard.update(bgActive ? "已启用" : "未启用", bgActive)
        }
    }

    // ══ 系统监测 ══
    func scheduleSysSample() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.lastCPU = self.sysMonitor.cpuUsage()
            self.lastMem = self.sysMonitor.memUsage()
            self.lastNet = self.sysMonitor.netSample()
            self.lastSSD = self.sysMonitor.ssdThroughput()
            if self.gpuAuthorized { self.lastGPU = self.readGpuValue() } else { self.lastGPU = nil }
            let cpuT = self.lastCPU.total
            let memPct = self.lastMem.totalGB > 0 ? self.lastMem.usedGB/self.lastMem.totalGB*100 : 0
            let net = self.lastNet, ssd = self.lastSSD
            DispatchQueue.main.async {
                self.sysTiles[.cpu]?.update(String(format: "%.0f%%", cpuT))
                self.sysTiles[.ram]?.update(String(format: "%.0f%%", memPct))
                self.sysTiles[.net]?.update(String(format: "↓%.1f ↑%.1f", net.downMBps, net.upMBps))
                self.sysTiles[.ssd]?.update(String(format: "%.1f", ssd) + " MB/s")
                if self.gpuAuthorized {
                    if let g = self.lastGPU { self.sysTiles[.gpu]?.update(String(format: "%.0f%%", g)) }
                    else { self.sysTiles[.gpu]?.update("…") }
                } else { self.sysTiles[.gpu]?.update("需授权") }
                if let panel = self.detailPanel { self.updateDetailContent(panel.kind) }
            }
        }
    }
    func openDetail(_ kind: MetricKind) {
        if detailPanel != nil { closeDetail() }
        let panel = SysDetailPanel(kind: kind)
        panel.onAuthorizeGPU = { [weak self] in self?.authorizeGPU() }
        panel.onStopGPU = { [weak self] in self?.stopGPU() }
        panel.onCleanJunk = { [weak self] in self?.cleanJunk() }
        panel.onManageProcesses = { [weak self] in self?.openProcessManager() }
        panel.onClose = { [weak self] in self?.closeDetail() }
        detailPanel = panel
        if let w = window {
            let cx = w.frame.midX, cy = w.frame.midY
            panel.setFrame(NSRect(x: cx - 230, y: cy - 180, width: 460, height: 360), display: true)
            w.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        updateDetailContent(kind)
    }
    func closeDetail() {
        guard let p = detailPanel else { return }
        detailPanel = nil
        window?.removeChildWindow(p)
        p.orderOut(nil)
    }
    func updateDetailContent(_ kind: MetricKind) {
        guard let panel = detailPanel, panel.kind == kind else { return }
        let (value, details) = detailData(for: kind)
        panel.setValue(value, details: details, gpuAuthorized: gpuAuthorized)
    }
    func detailData(for kind: MetricKind) -> (String, [String]) {
        switch kind {
        case .cpu:
            let c = lastCPU
            return (String(format: "%.1f%%", c.total),
                ["总占用率: \(String(format:"%.1f%%", c.total))",
                 "用户态: \(String(format:"%.1f%%", c.user))",
                 "系统态: \(String(format:"%.1f%%", c.system))",
                 "低优先级(nice): \(String(format:"%.1f%%", c.nice))",
                 "逻辑核心: \(sysMonitor.coreCount)   物理核心: \(sysMonitor.physicalCores)",
                 "处理器: \(sysMonitor.cpuModel)"])
        case .ram:
            let m = lastMem
            let free = max(m.totalGB - m.usedGB, 0)
            let pct = m.totalGB > 0 ? m.usedGB/m.totalGB*100 : 0
            return (String(format: "%.1f%%", pct),
                ["已使用: \(String(format:"%.2f", m.usedGB)) GB",
                 "总内存: \(String(format:"%.2f", m.totalGB)) GB",
                 "可用: \(String(format:"%.2f", free)) GB",
                 "线路内存(Wired): \(String(format:"%.2f", m.wiredGB)) GB",
                 "已压缩: \(String(format:"%.2f", m.compressedGB)) GB",
                 "点击下方按钮可清理垃圾或打开进程管理"])
        case .net:
            let n = lastNet
            return (String(format: "↓%.1f ↑%.1f MB/s", n.downMBps, n.upMBps),
                ["下行(接收): \(String(format:"%.2f", n.downMBps)) MB/s",
                 "上行(发送): \(String(format:"%.2f", n.upMBps)) MB/s",
                 "网络接口: \(n.iface)"])
        case .ssd:
            let s = lastSSD
            return (String(format: "%.1f MB/s", s),
                ["读取+写入吞吐: \(String(format:"%.2f", s)) MB/s",
                 "说明: macOS 未公开单独读/写速率，此处为磁盘总吞吐(iostat)",
                 "磁盘: disk0 (Apple SSD)"])
        case .gpu:
            if gpuAuthorized, let g = lastGPU {
                return (String(format: "%.0f%%", g),
                    ["GPU 占用率: \(String(format:"%.0f%%", g))",
                     "数据来源: powermetrics (已授权管理员权限)",
                     "说明: Apple Silicon 未提供公开 GPU 占用率 API，此为估算值"])
            }
            if gpuAuthorized {
                return ("采集中…",
                    ["授权已生效，正在采集 GPU 占用率…",
                     "首次采样需 1~2 秒，请稍候。"])
            }
            return ("需授权",
                ["macOS (Apple Silicon) 未公开 GPU 占用率公共 API。",
                 "点击「授权 GPU 监测」后，将以管理员权限运行",
                 "powermetrics 实时采集 GPU 占用率(估算值)。",
                 "授权仅需一次，数据将持续刷新。"])
        }
    }
    func authorizeGPU() {
        let script = "do shell script \"nohup powermetrics -s gpu -i 1000 -n 0 > /tmp/wb_gpu.log 2>&1 &\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err == nil {
            gpuAuthorized = true
            sysTiles[.gpu]?.update("…")
            if let panel = detailPanel, panel.kind == .gpu { updateDetailContent(.gpu) }
        } else {
            let a = NSAlert(); a.messageText = "GPU 授权失败"; a.informativeText = "无法以管理员权限启动 powermetrics。"; a.runModal()
        }
    }
    func stopGPU() {
        _ = runCmd("/usr/bin/pkill", ["-f", "powermetrics -s gpu"])
        gpuAuthorized = false
        try? FileManager.default.removeItem(atPath: "/tmp/wb_gpu.log")
        sysTiles[.gpu]?.update("需授权")
        if let panel = detailPanel, panel.kind == .gpu { updateDetailContent(.gpu) }
    }
    func cleanJunk() {
        let a = NSAlert()
        a.messageText = "清理垃圾"
        a.informativeText = "将清空废纸篓并刷新系统 DNS 缓存。是否继续？"
        a.alertStyle = .warning
        a.addButton(withTitle: "清理")
        a.addButton(withTitle: "取消")
        if a.runModal() == .alertFirstButtonReturn {
            _ = runCmd("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty the trash"])
            _ = runCmd("/usr/bin/dscacheutil", ["-flushcache"])
            let done = NSAlert(); done.messageText = "已完成"; done.informativeText = "已清空废纸篓并刷新 DNS 缓存。"; done.runModal()
        }
    }
    func openProcessManager() {
        _ = runCmd("/usr/bin/open", ["-a", "Activity Monitor"])
    }
    func readGpuValue() -> Double? {
        guard let s = try? String(contentsOfFile: "/tmp/wb_gpu.log", encoding: .utf8), !s.isEmpty else { return nil }
        let blocks = s.components(separatedBy: "====")
        let block = blocks.last ?? s
        func parsePercent(_ pattern: String) -> Double? {
            guard let r = try? NSRegularExpression(pattern: pattern, options: []),
                  let m = r.firstMatch(in: block, options: [], range: NSRange(location: 0, length: block.utf16.count)) else { return nil }
            let ns = block as NSString
            let num = ns.substring(with: m.range(at: 1))
            return Double(num)
        }
        return parsePercent(#"GPU\s+(?:HW\s+)?Active[^%\n]*?(\d+(?:\.\d+)?)\s*%"#)
            ?? parsePercent(#"GPU[^%\n]*?(\d+(?:\.\d+)?)\s*%"#)
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
// 额外强引用：防止 Swift 编译器优化释放全局变量
_ = Unmanaged.passRetained(delegate)
app.setActivationPolicy(.regular)
app.run()
