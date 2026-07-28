-- WorkBuddy+ 控制器
-- 三步流程：1. 打开 Web 管理选择背景  2. 启动源程序并注入  3. 退出

on run
	showMainMenu()
end run

on showMainMenu()
	set menuItems to {"1. 打开 Web 管理（选择背景）", "2. 启动源程序并注入", "3. 退出"}
	set choice to choose from list menuItems with prompt "WorkBuddy+ 背景注入

请选择操作步骤：" with title "WorkBuddy+ 控制器" default items {"1. 打开 Web 管理（选择背景）"}

	if choice is false then return

	set selectedItem to item 1 of choice

	if selectedItem starts with "1." then
		openWebManager()
	else if selectedItem starts with "2." then
		startWorkBuddyPlus()
	else if selectedItem starts with "3." then
		return
	end if
end showMainMenu

on openWebManager()
	-- 检查守护进程是否运行
	set daemonRunning to checkPort(17890)

	if not daemonRunning then
		display dialog "守护进程未运行，正在启动..." buttons {"确定"} default button 1 with icon note giving up after 2
		startDaemonOnly()
		delay 3
	end if

	-- 打开 Web 管理面板
	open location "http://localhost:17890"

	display notification "Web 管理面板已打开，请选择背景文件" with title "WorkBuddy+" sound name "Glass"

	-- 返回主菜单
	delay 1
	showMainMenu()
end openWebManager

on startWorkBuddyPlus()
	-- 检查 WorkBuddy 是否已运行（CDP 模式）
	set wbRunning to checkWorkBuddyCDP()

	set statusText to ""
	if wbRunning then
		set statusText to "WorkBuddy 已在运行（CDP 模式）"
	else
		set statusText to "WorkBuddy 未运行"
	end if

	display dialog statusText & return & return & "是否启动/重启 WorkBuddy+ 以应用背景？" buttons {"取消", "启动"} default button 2 with icon note
	if button returned of result is "取消" then
		showMainMenu()
		return
	end if

	-- 退出当前 WorkBuddy
	quitWorkBuddy()
	delay 2

	-- 启动 WorkBuddy + 守护进程
	do shell script "bash /Users/x/Documents/WorkBuddy/bg-injector/launcher.sh > /dev/null 2>&1 &"

	display notification "WorkBuddy+ 正在启动..." with title "WorkBuddy+" sound name "Glass"

	delay 5

	-- 检查启动状态
	set daemonRunning to checkPort(17890)
	set cdpRunning to checkPort(9222)

	set resultText to "守护进程: "
	if daemonRunning then
		set resultText to resultText & "✓ 运行中"
	else
		set resultText to resultText & "✗ 未运行"
	end if

	set resultText to resultText & return & "CDP 端口: "
	if cdpRunning then
		set resultText to resultText & "✓ 已开放"
	else
		set resultText to resultText & "✗ 未开放"
	end if

	if daemonRunning and cdpRunning then
		display notification "WorkBuddy+ 启动成功！背景已注入" with title "WorkBuddy+" sound name "Glass"
		display dialog "WorkBuddy+ 启动成功！" & return & return & resultText buttons {"完成"} default button 1 with icon note
	else
		display dialog "启动可能未完成" & return & return & resultText buttons {"确定"} default button 1 with icon caution
	end if
end startWorkBuddyPlus

on quitWorkBuddy()
	try
		tell application "WorkBuddy" to quit
		delay 1
	end try

	-- 强制退出（如果还在运行）
	do shell script "pkill -f 'WorkBuddy.app/Contents/MacOS' 2>/dev/null || true"
end quitWorkBuddy

on startDaemonOnly()
	do shell script "/Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node /Users/x/Documents/WorkBuddy/bg-injector/daemon.js > /Users/x/Documents/WorkBuddy/bg-injector/daemon.log 2>&1 &"
	delay 1
	do shell script "pgrep -f 'node.*daemon.js' > /Users/x/Documents/WorkBuddy/bg-injector/daemon.pid"
end startDaemonOnly

on checkPort(port)
	try
		do shell script "nc -z localhost " & port & " 2>/dev/null"
		return true
	on error
		return false
	end try
end checkPort

on checkWorkBuddyCDP()
	try
		do shell script "pgrep -f 'remote-debugging-port=9222' > /dev/null 2>&1"
		return true
	on error
		return false
	end try
end checkWorkBuddyCDP
