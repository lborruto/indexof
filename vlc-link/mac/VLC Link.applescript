-- VLC Link: opens vlc://files.lan:8099/... links (the files page's [vlc]) in VLC, as
-- http://files.lan:8099/... (the page leaves http out: Chrome rewrites vlc://http://... as
-- vlc://http//...).
-- Only links to the files page (files.lan, its Tailscale name or 192.168.1.10, port 8099,
-- under /media/ or /share/), so no other page can make VLC open what it likes.
on open location theURL
	-- What arrived and what was done with it, in ~/Library/Logs/VLC-Link.log (the link's
	-- signature left out).
	set shown to theURL
	if shown contains "&k=" then set shown to text 1 thru ((offset of "&k=" in shown) + 2) of shown & "…"
	do shell script "printf '%s %s\\n' \"$(date '+%F %T')\" " & quoted form of shown & " >> ~/Library/Logs/VLC-Link.log"
	set allowed to {"vlc://files.lan:8099/", "vlc://files.example-tailnet.ts.net:8099/", "vlc://192.168.1.10:8099/"}
	set target to ""
	repeat with p in allowed
		if theURL starts with (p as text) then set target to "http://" & (text 7 thru -1 of theURL)
	end repeat
	if target is "" then
		do shell script "echo '  refused: not a link to the files page' >> ~/Library/Logs/VLC-Link.log"
		return
	end if
	set pathPart to text ((offset of ":8099/" in target) + 5) thru -1 of target
	if not (pathPart starts with "/media/" or pathPart starts with "/share/") then
		do shell script "echo '  refused: not under /media/ or /share/' >> ~/Library/Logs/VLC-Link.log"
		return
	end if
	-- A link from the page is percent-encoded: nothing a shell or VLC could read otherwise.
	repeat with c in {" ", "\"", "'", "`", "\\", "$", ";", "|", "&&", "<", ">"}
		if target contains (c as text) then
			do shell script "echo '  refused: holds a character it should not' >> ~/Library/Logs/VLC-Link.log"
			return
		end if
	end repeat
	do shell script "open -a VLC " & quoted form of target
	do shell script "echo '  opened in VLC' >> ~/Library/Logs/VLC-Link.log"
end open location

on run
	display dialog "VLC Link opens the files page's [vlc] links in VLC. Nothing to do here: click [vlc] on the page." buttons {"OK"} default button 1
end run
