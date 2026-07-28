on open droppedFiles
	try
		set filePath to POSIX path of (item 1 of droppedFiles as alias)
		set scriptPath to "/Users/x/Documents/WorkBuddy/WorkBuddy+/set-background.sh"
		set logFile to "/tmp/workbuddy-bg-set.log"

		-- 记录日志
		do shell script "echo '=== " & (current date) & " ===' >> " & quoted form of logFile
		do shell script "echo 'File: " & quoted form of filePath & "' >> " & quoted form of logFile

		-- 执行设置脚本
		set shellCommand to "bash " & quoted form of scriptPath & " " & quoted form of filePath & " >> " & quoted form of logFile & " 2>&1"
		do shell script shellCommand

		do shell script "echo 'Success' >> " & quoted form of logFile
		display notification "背景已设置" with title "WorkBuddy+" sound name "Glass"
	on error errMsg number errNum
		do shell script "echo 'Error: " & quoted form of errMsg & "' >> /tmp/workbuddy-bg-set.log"
		display alert "设置失败" message errMsg & return & return & "查看日志: /tmp/workbuddy-bg-set.log" buttons {"确定"} default button 1 as critical
	end try
end open

on run
	try
		set selectedFile to choose file with prompt "选择背景图片或视频:" of type {"public.image", "public.movie"}
		set filePath to POSIX path of selectedFile
		set scriptPath to "/Users/x/Documents/WorkBuddy/WorkBuddy+/set-background.sh"
		set logFile to "/tmp/workbuddy-bg-set.log"

		-- 记录日志
		do shell script "echo '=== " & (current date) & " ===' >> " & quoted form of logFile
		do shell script "echo 'File: " & quoted form of filePath & "' >> " & quoted form of logFile

		-- 执行设置脚本
		set shellCommand to "bash " & quoted form of scriptPath & " " & quoted form of filePath & " >> " & quoted form of logFile & " 2>&1"
		do shell script shellCommand

		do shell script "echo 'Success' >> " & quoted form of logFile
		display notification "背景已设置" with title "WorkBuddy+" sound name "Glass"
	on error errMsg number errNum
		if errNum is not -128 then -- 不是用户取消
			do shell script "echo 'Error: " & quoted form of errMsg & "' >> /tmp/workbuddy-bg-set.log"
			display alert "设置失败" message errMsg & return & return & "查看日志: /tmp/workbuddy-bg-set.log" buttons {"确定"} default button 1 as critical
		end if
	end try
end run
