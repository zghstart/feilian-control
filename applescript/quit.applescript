on run
	set theChoice to display dialog "飞连要退出了。是否同时停止后台服务？" & return & return & "仅退出界面：VPN 断开，但 EDR / DLP / 杀毒等后台进程继续运行。" & return & "连后台一起停用：所有飞连进程停止，直到你运行“恢复飞连”。" buttons {"取消", "仅退出界面", "连后台一起停用"} default button "仅退出界面" cancel button "取消" with title "退出飞连" with icon caution

	set theButton to button returned of theChoice

	if theButton is "仅退出界面" then
		try
			do shell script "pkill -TERM -x CorpLink 2>/dev/null || true"
			display notification "飞连界面已退出，后台服务仍在运行" with title "飞连"
		end try
	else if theButton is "连后台一起停用" then
		try
			do shell script "/usr/local/bin/feilianctl stop"
			display notification "飞连界面和全部后台服务已停止" with title "飞连"
			display dialog "飞连界面和全部后台服务已停止。" buttons {"好"} default button "好" with title "飞连已停用"
		on error errMsg
			display dialog "停用失败：" & errMsg buttons {"好"} default button "好" with icon stop
		end try
	end if
end run
