-- WorkBuddy+ 控制器
-- 简单的控制面板，提供快捷操作

on run
	set trayPort to 17891
	set daemonPort to 17890

	-- 检查托盘守护进程
	set trayRunning to checkPort(trayPort)

	if not trayRunning then
		display dialog "托盘守护进程未运行" & return & return & "是否启动？" buttons {"取消", "启动"} default button 2 with icon caution
		if button returned of result is "启动" then
			startTrayDaemon()
			delay 2
		else
			return
		end if
	end if

	-- 显示主菜单
	showMainMenu()
end run

on showMainMenu()
	set trayPort to 17891
	set statusUrl to "http://localhost:" & trayPort & "/api/status"

	try
		set statusJson to do shell script "curl -s " & quoted form of statusUrl
		set wbRunning to my parseJson(statusJson, "workbuddy")
		set daemonRunning to my parseJson(statusJson, "daemon")

		set wbStatus to "✗ 未运行"
		if wbRunning then set wbStatus to "✓ 运行中"

		set daemonStatus to "✗ 未运行"
		if daemonRunning then set daemonStatus to "✓ 运行中"

		set statusText to "WorkBuddy: " & wbStatus & return & "守护进程: " & daemonStatus

		set menuItems to {"启动 WorkBuddy+", "设置背景...", "打开 Web 设置面板", "查看状态", "退出"}
		set choice to choose from list menuItems with prompt statusText & return & return & "选择操作:" with title "WorkBuddy+ 控制器"

		if choice is false then return

		set selectedItem to item 1 of choice

		if selectedItem is "启动 WorkBuddy+" then
			startWorkBuddyPlus()
		else if selectedItem is "设置背景..." then
			setBackground()
		else if selectedItem is "打开 Web 设置面板" then
			open location "http://localhost:17890"
		else if selectedItem is "查看状态" then
			showMainMenu()
		else if selectedItem is "退出" then
			return
		end if

	on error errMsg
		display alert "错误" message errMsg buttons {"确定"} default button 1 as critical
	end try
end showMainMenu

on startTrayDaemon()
	do shell script "nohup /Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node /Users/x/Documents/WorkBuddy/bg-injector/tray-daemon.js > /dev/null 2>&1 &"
	display notification "托盘守护进程已启动" with title "WorkBuddy+"
end startTrayDaemon

on startWorkBuddyPlus()
	try
		do shell script "curl -s -X POST http://localhost:17891/api/start"
		display notification "WorkBuddy+ 正在启动..." with title "WorkBuddy+"
		delay 3
		showMainMenu()
	on error errMsg
		display alert "启动失败" message errMsg buttons {"确定"} default button 1 as critical
	end try
end startWorkBuddyPlus

on setBackground()
	try
		set selectedFile to choose file with prompt "选择背景图片或视频:" of type {"public.image", "public.movie"}
		set filePath to POSIX path of selectedFile

		set jsonBody to "{\"filePath\":\"" & filePath & "\"}"
		do shell script "curl -s -X POST -H 'Content-Type: application/json' -d " & quoted form of jsonBody & " http://localhost:17891/api/set-background"

		display notification "背景已设置" with title "WorkBuddy+" sound name "Glass"
	on error errMsg number errNum
		if errNum is not -128 then
			display alert "设置失败" message errMsg buttons {"确定"} default button 1 as critical
		end if
	end try
end setBackground

on checkPort(port)
	try
		do shell script "nc -z localhost " & port & " 2>/dev/null"
		return true
	on error
		return false
	end try
end checkPort

on parseJson(jsonStr, key)
	-- 简单的 JSON 解析（仅用于布尔值）
	set searchStr to "\"" & key & "\":true"
	if jsonStr contains searchStr then
		return true
	else
		return false
	end if
end parseJson
