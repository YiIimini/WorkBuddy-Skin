-- WorkBuddy-Skin 一体化管理器
-- 直接启动原生桌面应用窗口，不自动打开浏览器

on run
	-- 检查守护进程是否运行
	set daemonRunning to checkPort(17890)

	if not daemonRunning then
		startDaemonOnly()
		delay 3
	end if
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
