import Cocoa

// WorkBuddy-Skin 管理器 - 原生 macOS 应用
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusLabel: NSTextField!
    var startButton: NSButton!
    var selectFileButton: NSButton!
    var clearButton: NSButton!
    var enabledCheckbox: NSButton!
    var opacitySlider: NSSlider!
    var overlaySlider: NSSlider!
    var blurPopup: NSPopUpButton!
    var scalePopup: NSPopUpButton!
    var positionPopup: NSPopUpButton!
    var fileLabel: NSTextField!

    let daemonURL = "http://localhost:17890"
    var currentConfig: [String: Any] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow()
        startDaemonIfNeeded()
        refreshStatus()
        loadConfig()

        // 每 5 秒刷新状态
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.refreshStatus()
        }
    }

    func createWindow() {
        let windowRect = NSRect(x: 100, y: 100, width: 700, height: 800)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WorkBuddy-Skin 管理器"
        window.center()

        let contentView = NSView(frame: windowRect)
        window.contentView = contentView

        var yPos: CGFloat = 750

        // 标题
        let titleLabel = createLabel("🎨 WorkBuddy-Skin", fontSize: 28, bold: true, frame: NSRect(x: 20, y: yPos, width: 660, height: 40))
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)
        yPos -= 50

        // 副标题
        let subtitleLabel = createLabel("背景注入管理器 v2.0.1", fontSize: 14, bold: false, frame: NSRect(x: 20, y: yPos, width: 660, height: 20))
        subtitleLabel.alignment = .center
        subtitleLabel.textColor = .secondaryLabelColor
        contentView.addSubview(subtitleLabel)
        yPos -= 40

        // 状态卡片区域
        let statusCardWidth: CGFloat = 160
        let statusCardHeight: CGFloat = 80
        let statusCardSpacing: CGFloat = 10
        var xPos: CGFloat = 20

        // WorkBuddy 状态
        createStatusCard(title: "🖥️ WorkBuddy", x: xPos, y: yPos, width: statusCardWidth, height: statusCardHeight, view: contentView)
        xPos += statusCardWidth + statusCardSpacing

        // CDP 状态
        createStatusCard(title: "🔌 CDP 端口", x: xPos, y: yPos, width: statusCardWidth, height: statusCardHeight, view: contentView)
        xPos += statusCardWidth + statusCardSpacing

        // 守护进程状态
        createStatusCard(title: "⚙️ 守护进程", x: xPos, y: yPos, width: statusCardWidth, height: statusCardHeight, view: contentView)
        xPos += statusCardWidth + statusCardSpacing

        // 背景状态
        createStatusCard(title: "🎬 背景状态", x: xPos, y: yPos, width: statusCardWidth, height: statusCardHeight, view: contentView)

        yPos -= 100

        // 快速操作
        let actionsLabel = createLabel("⚡ 快速操作", fontSize: 16, bold: true, frame: NSRect(x: 20, y: yPos, width: 660, height: 25))
        contentView.addSubview(actionsLabel)
        yPos -= 35

        // 启动按钮
        startButton = NSButton(frame: NSRect(x: 20, y: yPos, width: 320, height: 40))
        startButton.title = "🚀 启动 WorkBuddy-Skin"
        startButton.bezelStyle = .rounded
        startButton.target = self
        startButton.action = #selector(startWorkBuddySkin)
        contentView.addSubview(startButton)

        // 刷新按钮
        let refreshButton = NSButton(frame: NSRect(x: 360, y: yPos, width: 320, height: 40))
        refreshButton.title = "🔄 刷新状态"
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshStatus)
        contentView.addSubview(refreshButton)

        yPos -= 60

        // 背景设置
        let settingsLabel = createLabel("🎬 背景设置", fontSize: 16, bold: true, frame: NSRect(x: 20, y: yPos, width: 660, height: 25))
        contentView.addSubview(settingsLabel)
        yPos -= 35

        // 文件信息
        fileLabel = createLabel("未选择文件", fontSize: 13, bold: false, frame: NSRect(x: 20, y: yPos, width: 660, height: 20))
        fileLabel.textColor = .secondaryLabelColor
        contentView.addSubview(fileLabel)
        yPos -= 30

        // 选择文件按钮
        selectFileButton = NSButton(frame: NSRect(x: 20, y: yPos, width: 320, height: 35))
        selectFileButton.title = "📁 选择文件"
        selectFileButton.bezelStyle = .rounded
        selectFileButton.target = self
        selectFileButton.action = #selector(selectFile)
        contentView.addSubview(selectFileButton)

        // 清除背景按钮
        clearButton = NSButton(frame: NSRect(x: 360, y: yPos, width: 320, height: 35))
        clearButton.title = "🗑️ 清除背景"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearBackground)
        contentView.addSubview(clearButton)

        yPos -= 50

        // 启用背景
        enabledCheckbox = NSButton(checkboxWithTitle: "启用背景", target: self, action: #selector(updateConfig))
        enabledCheckbox.frame = NSRect(x: 20, y: yPos, width: 660, height: 25)
        contentView.addSubview(enabledCheckbox)
        yPos -= 40

        // 不透明度
        let opacityLabel = createLabel("不透明度: 100%", fontSize: 13, bold: false, frame: NSRect(x: 20, y: yPos, width: 150, height: 20))
        contentView.addSubview(opacityLabel)

        opacitySlider = NSSlider(frame: NSRect(x: 180, y: yPos, width: 480, height: 20))
        opacitySlider.minValue = 10
        opacitySlider.maxValue = 100
        opacitySlider.doubleValue = 100
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        contentView.addSubview(opacitySlider)
        yPos -= 35

        // 暗色遮罩
        let overlayLabel = createLabel("暗色遮罩: 50%", fontSize: 13, bold: false, frame: NSRect(x: 20, y: yPos, width: 150, height: 20))
        contentView.addSubview(overlayLabel)

        overlaySlider = NSSlider(frame: NSRect(x: 180, y: yPos, width: 480, height: 20))
        overlaySlider.minValue = 0
        overlaySlider.maxValue = 80
        overlaySlider.doubleValue = 50
        overlaySlider.target = self
        overlaySlider.action = #selector(overlayChanged)
        contentView.addSubview(overlaySlider)
        yPos -= 40

        // 模糊
        let blurLabel = createLabel("模糊:", fontSize: 13, bold: false, frame: NSRect(x: 20, y: yPos, width: 150, height: 20))
        contentView.addSubview(blurLabel)

        blurPopup = NSPopUpButton(frame: NSRect(x: 180, y: yPos, width: 200, height: 25))
        blurPopup.addItems(withTitles: ["无", "轻微", "中等", "强烈"])
        blurPopup.target = self
        blurPopup.action = #selector(updateConfig)
        contentView.addSubview(blurPopup)
        yPos -= 35

        // 填充方式
        let scaleLabel = createLabel("填充方式:", fontSize: 13, bold: false, frame: NSRect(x: 20, y: yPos, width: 150, height: 20))
        contentView.addSubview(scaleLabel)

        scalePopup = NSPopUpButton(frame: NSRect(x: 180, y: yPos, width: 200, height: 25))
        scalePopup.addItems(withTitles: ["覆盖", "包含", "填充"])
        scalePopup.target = self
        scalePopup.action = #selector(updateConfig)
        contentView.addSubview(scalePopup)
        yPos -= 35

        // 位置
        let positionLabel = createLabel("位置:", fontSize: 13, bold: false, frame: NSRect(x: 20, y: yPos, width: 150, height: 20))
        contentView.addSubview(positionLabel)

        positionPopup = NSPopUpButton(frame: NSRect(x: 180, y: yPos, width: 200, height: 25))
        positionPopup.addItems(withTitles: ["居中", "顶部", "底部", "左侧", "右侧"])
        positionPopup.target = self
        positionPopup.action = #selector(updateConfig)
        contentView.addSubview(positionPopup)

        window.makeKeyAndOrderFront(nil)
    }

    func createLabel(_ text: String, fontSize: CGFloat, bold: Bool, frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        return label
    }

    func createStatusCard(title: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, view: NSView) {
        let card = NSView(frame: NSRect(x: x, y: y, width: width, height: height))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.8).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.systemPink.withAlphaComponent(0.3).cgColor

        let titleLabel = createLabel(title, fontSize: 11, bold: false, frame: NSRect(x: 10, y: height - 25, width: width - 20, height: 15))
        titleLabel.textColor = .secondaryLabelColor
        card.addSubview(titleLabel)

        let valueLabel = createLabel("检查中...", fontSize: 16, bold: true, frame: NSRect(x: 10, y: 10, width: width - 20, height: 30))
        valueLabel.alignment = .center
        card.addSubview(valueLabel)

        view.addSubview(card)

        // 保存引用
        if title.contains("WorkBuddy") && !title.contains("背景") {
            statusLabel = valueLabel
        }
    }

    @objc func startWorkBuddySkin() {
        startButton.isEnabled = false
        startButton.title = "启动中..."

        DispatchQueue.global().async {
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["\(NSHomeDirectory())/WorkBuddy-Skin/launcher.sh"]
            task.launch()
            task.waitUntilExit()

            DispatchQueue.main.async {
                self.startButton.isEnabled = true
                self.startButton.title = "🚀 启动 WorkBuddy-Skin"
                self.refreshStatus()
            }
        }
    }

    @objc func refreshStatus() {
        // 检查守护进程
        let daemonRunning = checkPort(17890)
        updateStatusCard(title: "⚙️ 守护进程", value: daemonRunning ? "运行中" : "未运行", ok: daemonRunning)

        // 检查 CDP
        let cdpRunning = checkPort(9222)
        updateStatusCard(title: "🔌 CDP 端口", value: cdpRunning ? "已开放" : "未开放", ok: cdpRunning)

        // WorkBuddy
        updateStatusCard(title: "🖥️ WorkBuddy", value: cdpRunning ? "运行中" : "未运行", ok: cdpRunning)

        // 背景状态
        if let enabled = currentConfig["enabled"] as? Bool, let source = currentConfig["source"] as? String {
            let bgActive = enabled && !source.isEmpty
            updateStatusCard(title: "🎬 背景状态", value: bgActive ? "已启用" : "未启用", ok: bgActive)
        }
    }

    func updateStatusCard(title: String, value: String, ok: Bool) {
        // 简化实现，实际应该保存每个卡片的引用
        DispatchQueue.main.async {
            self.statusLabel.stringValue = value
            self.statusLabel.textColor = ok ? .systemGreen : .systemRed
        }
    }

    func checkPort(_ port: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/nc"
        task.arguments = ["-z", "localhost", String(port)]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus == 0
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
            }
            Thread.sleep(forTimeInterval: 3)
        }
    }

    @objc func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.currentConfig["source"] = url.path
                self.currentConfig["type"] = url.pathExtension.lowercased().contains("mp4") || url.pathExtension.lowercased().contains("mov") ? "video" : "image"
                self.currentConfig["enabled"] = true
                self.enabledCheckbox.state = .on
                self.fileLabel.stringValue = url.lastPathComponent
                self.updateConfig()
            }
        }
    }

    @objc func clearBackground() {
        currentConfig["enabled"] = false
        currentConfig["source"] = ""
        enabledCheckbox.state = .off
        fileLabel.stringValue = "未选择文件"
        updateConfig()
    }

    @objc func opacityChanged() {
        let value = Int(opacitySlider.doubleValue)
        // 更新标签
        updateConfig()
    }

    @objc func overlayChanged() {
        let value = Int(overlaySlider.doubleValue)
        // 更新标签
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

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            DispatchQueue.main.async {
                self.currentConfig = json
                self.enabledCheckbox.state = (json["enabled"] as? Bool ?? false) ? .on : .off
                self.opacitySlider.doubleValue = (json["opacity"] as? Double ?? 1.0) * 100
                self.overlaySlider.doubleValue = (json["overlay"] as? Double ?? 0.5) * 100

                if let source = json["source"] as? String, !source.isEmpty {
                    self.fileLabel.stringValue = (source as NSString).lastPathComponent
                }
            }
        }
        task.resume()
    }

    func saveConfig() {
        guard let url = URL(string: "\(daemonURL)/api/config") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: currentConfig)

        URLSession.shared.dataTask(with: request).resume()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// 主入口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
