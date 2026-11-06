on run
	try
		set s to do shell script "/usr/local/bin/feilianctl status"
		display dialog s buttons {"好"} default button "好" with title "飞连状态"
	on error errMsg
		display dialog "读取状态失败：" & errMsg buttons {"好"} default button "好" with icon stop
	end try
end run
