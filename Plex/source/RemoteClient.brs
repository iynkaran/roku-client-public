'*
'* An implementation of the remote client/player interface that allows the Roku
'* to be controlled by other Plex clients, like the remote built into the
'* iOS/Android apps.
'*

Function ProcessPlayMediaRequest() As Boolean
    ' Note that we're evaluated in the context of a Reply object.

    if RegRead("remotecontrol", "preferences", "1") <> "1" then
        m.default(404, "Remote control is disabled for this device")
        return true
    end if

    Debug("Processing PlayMedia request")
    for each name in m.request.fields
        Debug("  " + name + ": " + UrlUnescape(m.request.fields[name]))
    next

    ' Fetch the container for the path and then look for a matching key. This
    ' allows us to set the context correctly so we can do things like play an
    ' entire album or slideshow.

    url = RewriteNodeKey(UrlUnescape(firstOf(m.request.fields["X-Plex-Arg-Path"], "")))
    key = RewriteNodeKey(UrlUnescape(firstOf(m.request.fields["X-Plex-Arg-Key"], "")))

    server = GetServerForUrl(url)
    if server = invalid then
        Debug("Not sure which server to use for " + tostr(url) + ", falling back to primary")
        server = GetPrimaryServer()
    end if

    if server = invalid then
        m.default(404, "No server available for specified URL")
        return true
    end if

    container = createPlexContainerForUrl(server, "", url)
    children = container.GetMetadata()
    matchIndex = invalid
    for i = 0 to children.Count() - 1
        item = children[i]
        if key = item.key then
            matchIndex = i
            exit for
        end if
    end for

    ' Sadly, this doesn't work when playing something from the queue on iOS. So
    ' if we didn't find a match, just request the key directly.
    if matchIndex = invalid then
        container = createPlexContainerForUrl(server, url, key)
        children = container.GetMetadata()
        if children.Count() > 0 then matchIndex = 0
    end if

    if matchIndex <> invalid then
        if m.request.fields.DoesExist("X-Plex-Arg-ViewOffset") then
            seek = m.request.fields["X-Plex-Arg-ViewOffset"].toint()
        else
            seek = 0
        end if

        ' If we currently have a video playing, things are tricky. We can't
        ' play anything on top of video or Bad Things happen. But we also
        ' can't quickly close the screen and throw up a new video player
        ' because the new video screen will see the isScreenClosed event
        ' meant for the old video player. So we have to register a callback,
        ' which is always awkward.

        if GetViewController().IsVideoPlaying() then
            callback = CreateObject("roAssociativeArray")
            callback.context = children
            callback.contextIndex = matchIndex
            callback.seekValue = seek
            callback.OnAfterClose = createPlayerAfterClose
            GetViewController().CloseScreenWithCallback(callback)
        else
            GetViewController().CreatePlayerForItem(children, matchIndex, seek)

            ' If the screensaver is on, which we can't reliably know, then the
            ' video won't start until the user wakes the Roku up. We can do that
            ' for them by sending a harmless keystroke. Down is harmless, as long
            ' as they started a video or slideshow.
            if GetViewController().IsVideoPlaying() OR children[matchIndex].ContentType = "photo" then
                req = CreateURLTransferObject("http://127.0.0.1:8060/keypress/Down")
                req.AsyncPostFromString("")
            end if
        end if

        m.http_code = 200
    else
        Debug("Unable to find matching item for key")
        m.http_code = 404
    end if

    ' Always return an empty body
    body = ""
    m.buf.fromasciistring(body)
    m.length = m.buf.count()
    m.genHdr(true)
    m.source = m.GENERATED

    return true
End Function

Function ProcessStopMediaRequest() As Boolean
    ' Note that we're evaluated in the context of a Reply object.

    if RegRead("remotecontrol", "preferences", "1") <> "1" then
        m.default(404, "Remote control is disabled for this device")
        return true
    end if

    ' If we're playing a video, close it. Otherwise assume this is destined for
    ' the audio player, which will respond appropriately whatever state it's in.
    vc = GetViewController()
    if vc.IsVideoPlaying() then
        vc.CloseScreenWithCallback(invalid)
    else
        vc.AudioPlayer.Stop()
    end if

    ' Always return an empty body
    body = ""
    m.buf.fromasciistring(body)
    m.length = m.buf.count()
    m.http_code = 200
    m.genHdr(true)
    m.source = m.GENERATED

    return true
End Function

Sub createPlayerAfterClose()
    GetViewController().CreatePlayerForItem(m.context, m.contextIndex, m.seekValue)
End Sub
