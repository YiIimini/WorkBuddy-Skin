-- WorkBuddy-Skin 一体化管理器
-- 直接打开管理界面，集成状态监控、设置、启动等所有功能

on run
	-- 检查守护进程是否运行
	set daemonRunning to checkPort(17890)

	if not daemonRunning then
		display dialog "守护进程未运行，正在启动..." buttons {"确定"} default button 1 with icon note giving up after 2
		startDaemonOnly()
		delay 3
	end if

	-- 打开管理器界面
	open location "http://localhost:17890"

	display notification "WorkBuddy-Skin 管理器已打开" with title "WorkBuddy-Skin" sound name "Glass"
end run

on startDaemonOnly()
	do shell script "/Users/x/.workbuddy/binaries/node/versions/22.22.2/bin/node ~/WorkBuddy-Skin/daemon.js > ~/WorkBuddy-Skin/daemon.log 2>&1 &"
	delay 1
	do shell script "pgrep -f 'node.*daemon.js' > ~/WorkBuddy-Skin/daemon.pid"
end startDaemonOnly

on checkPort(port)
	try
		do shell script "nc -z localhost " & port & " 2>/dev/null"
		return true
	on error
		return false
	end try
end checkPort
