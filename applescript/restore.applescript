on run
	set theChoice to display dialog "恢复飞连后台服务并打开客户端？" buttons {"取消", "恢复"} default button "取消" with title "恢复飞连" with icon note
	if button returned of theChoice is "恢复" then
		try
			do shell script "/usr/local/bin/feilianctl start"
			display notification "飞连后台服务已恢复" with title "飞连"
			display dialog "飞连后台服务已恢复，客户端正在打开。" buttons {"好"} default button "好" with title "飞连已恢复"
		on error errMsg
			display dialog "恢复失败：" & errMsg buttons {"好"} default button "好" with icon stop
		end try
	end if
end run
