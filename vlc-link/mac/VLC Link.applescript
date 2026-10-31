-- VLC Link: opens the page's vlc://host:port/... links (the [vlc] next to a video, "open in
-- VLC" in the player) in VLC, as http://host:port/... (the page leaves http out: Chrome
-- rewrites vlc://http://... as vlc://http//...).
-- Only links to the page itself: the addresses (host:port) given to install.sh, which puts them
-- in the list below, and only under a folder of it (/<folder>/...), so no other page can make
-- VLC open what it likes. As it is here, with an empty list, it opens nothing.
on open location theURL
	-- What arrived and what was done with it, in ~/Library/Logs/VLC-Link.log (the link's
	-- signature left out).
	set shown to theURL
	if shown contains "&k=" then set shown to text 1 thru ((offset of "&k=" in shown) + 2) of shown & "…"
	do shell script "printf '%s %s\\n' \"$(date '+%F %T')\" " & quoted form of shown & " >> ~/Library/Logs/VLC-Link.log"
	set allowed to {} -- (install.sh fills it in: {"vlc://host:port/", ...})
	set matched to ""
	repeat with p in allowed
		if theURL starts with (p as text) then set matched to (p as text)
	end repeat
	if matched is "" then
		do shell script "echo '  refused: not a link to the page' >> ~/Library/Logs/VLC-Link.log"
		return
	end if
	-- Under a folder of the page: /<folder>/<something>, the folder's name not empty and not
	-- holding the start of the query.
	set pathPart to text (length of matched) thru -1 of theURL -- ("/" and what follows)
	set slash to 0
	if (length of pathPart) > 2 then set slash to offset of "/" in (text 2 thru -1 of pathPart)
	if slash < 2 or slash is (length of pathPart) - 1 or (text 2 thru slash of pathPart) contains "?" then
		do shell script "echo '  refused: not under a folder of the page' >> ~/Library/Logs/VLC-Link.log"
		return
	end if
	set target to "http://" & (text 7 thru -1 of theURL)
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
	display dialog "VLC Link opens the page's [vlc] links in VLC. Nothing to do here: click [vlc] on the page." buttons {"OK"} default button 1
end run
