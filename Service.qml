import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Headless service that tracks the Sonora MPRIS player
// (org.mpris.MediaPlayer2.sonora) and exposes its state and controls to the
// bar widget (one per monitor) and to IPC / keybindings.
Item {
  id: root

  property var shell: null

  // ------------------------------------------------------------ player

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: findPlayer(players)

  function isSonora(p) {
    if (!p) return false
    var dbus = String(p.dbusName || "").toLowerCase()
    var identity = String(p.identity || "").toLowerCase()
    var entry = String(p.desktopEntry || "").toLowerCase()
    return dbus.indexOf("org.mpris.mediaplayer2.sonora") === 0
      || identity === "sonora"
      || entry === "sonora"
  }

  function findPlayer(list) {
    for (var i = 0; i < list.length; i++) {
      if (isSonora(list[i])) return list[i]
    }
    return null
  }

  readonly property bool available: player !== null
  readonly property bool playing: available && !!player.isPlaying
  readonly property string title: available ? (player.trackTitle || "") : ""
  readonly property string artist: available ? (player.trackArtist || "") : ""
  readonly property string album: available ? (player.trackAlbum || "") : ""
  readonly property string artUrl: available ? (player.trackArtUrl || "") : ""
  readonly property bool hasTrack: title !== "" || artist !== ""

  readonly property real length: available && player.lengthSupported ? player.length : 0
  readonly property real position: available && player.positionSupported ? player.position : 0
  readonly property bool canSeek: available && !!player.canSeek && length > 0
  readonly property bool canNext: available && !!player.canGoNext
  readonly property bool canPrevious: available && !!player.canGoPrevious
  readonly property bool volumeSupported: available && !!player.volumeSupported
  readonly property real volume: volumeSupported ? player.volume : 0
  readonly property bool shuffleSupported: available && !!player.shuffleSupported
  readonly property bool loopSupported: available && !!player.loopSupported
  readonly property bool shuffle: shuffleSupported && _shuffle
  // "none" | "playlist" | "track"
  readonly property string loopMode: loopSupported ? _loop : "none"

  // ------------------------------------------------------------ shuffle / repeat
  // Sonora doesn't emit PropertiesChanged for Shuffle or LoopStatus, so the
  // values cached by Quickshell's MPRIS client go stale. Read and write them
  // directly over D-Bus instead, polling while Sonora is running.

  readonly property string busName: available && player.dbusName
    ? String(player.dbusName) : "org.mpris.MediaPlayer2.sonora"
  readonly property var _busctl: ["busctl", "--user"]
  readonly property string _objPath: "/org/mpris/MediaPlayer2"
  readonly property string _iface: "org.mpris.MediaPlayer2.Player"

  property bool _shuffle: false
  property string _loop: "none"

  function refreshOptions() {
    if (!available || optionsProc.running) return
    optionsProc.running = true
  }

  Process {
    id: optionsProc
    command: root._busctl.concat(["get-property", root.busName, root._objPath, root._iface,
      "Shuffle", "LoopStatus"])
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        if (lines.length < 2) return
        root._shuffle = lines[0].trim() === "b true"
        var loop = lines[1].trim().toLowerCase()
        root._loop = loop.indexOf("track") >= 0 ? "track"
          : (loop.indexOf("playlist") >= 0 ? "playlist" : "none")
      }
    }
  }

  Timer {
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.available
    onTriggered: root.refreshOptions()
  }

  Timer {
    id: optionsSettle
    interval: 250
    onTriggered: root.refreshOptions()
  }

  function _setOption(name, type, value) {
    Quickshell.execDetached(root._busctl.concat(["set-property", root.busName, root._objPath,
      root._iface, name, type, value]))
    optionsSettle.restart()
  }

  // MPRIS doesn't push position updates while playing; nudge the binding once
  // a second so progress displays keep moving.
  Timer {
    interval: 1000
    repeat: true
    running: root.playing && root.player.positionSupported
    onTriggered: root.player.positionChanged()
  }

  // ------------------------------------------------------------ actions

  function summary() {
    if (!hasTrack) return available ? "Sonora" : "Sonora is not running"
    return artist ? title + " - " + artist : title
  }

  function showOsd(label, icon) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: icon || "media",
      message: hasTrack ? summary() : label
    }))
  }

  // Track metadata lands a moment after next/previous; wait for it so the OSD
  // shows the new song rather than the old one.
  property var _pendingOsd: null

  Timer {
    id: osdTimer
    interval: 120
    repeat: false
    onTriggered: {
      var p = root._pendingOsd
      if (!p) return
      var sig = root.title + "\u001f" + root.artist
      if (sig !== p.before || p.attempts >= 10) {
        root._pendingOsd = null
        root.showOsd(p.label, p.icon)
      } else {
        p.attempts += 1
        osdTimer.restart()
      }
    }
  }

  function feedback(label, icon, waitForTrack) {
    if (waitForTrack) {
      _pendingOsd = { label: label, icon: icon, before: title + "\u001f" + artist, attempts: 0 }
      osdTimer.restart()
    } else {
      Qt.callLater(function() { root.showOsd(label, icon) })
    }
  }

  function runAction(action, showFeedback) {
    var p = player
    if (!p) return false
    var handled = false
    var label = ""
    var icon = "media"
    var waitForTrack = false

    if (action === "playPause") {
      label = p.isPlaying ? "Pause" : "Play"
      icon = p.isPlaying ? "media-pause" : "media-play"
      if (p.canTogglePlaying) { p.togglePlaying(); handled = true }
      else if (p.isPlaying && p.canPause) { p.pause(); handled = true }
      else if (!p.isPlaying && p.canPlay) { p.play(); handled = true }
    } else if (action === "play") {
      label = "Play"; icon = "media-play"
      if (p.canPlay) { p.play(); handled = true }
    } else if (action === "pause") {
      label = "Pause"; icon = "media-pause"
      if (p.canPause) { p.pause(); handled = true }
    } else if (action === "stop") {
      label = "Stop"; icon = "media-pause"
      p.stop(); handled = true
    } else if (action === "next") {
      label = "Next"; icon = "media-next"; waitForTrack = true
      if (p.canGoNext) { p.next(); handled = true }
    } else if (action === "previous") {
      label = "Previous"; icon = "media-previous"; waitForTrack = true
      if (p.canGoPrevious) { p.previous(); handled = true }
    }

    if (handled && showFeedback !== false) feedback(label, icon, waitForTrack)
    return handled
  }

  // Absolute seek, in seconds, implemented as a relative Seek from the current
  // position (avoids needing the trackid that SetPosition requires).
  function seekTo(seconds) {
    if (!canSeek) return false
    var target = Math.max(0, Math.min(length, Number(seconds)))
    if (!isFinite(target)) return false
    player.seek(target - player.position)
    Qt.callLater(function() { if (root.player) root.player.positionChanged() })
    return true
  }

  function seekBy(deltaSeconds) {
    if (!canSeek) return false
    return seekTo(player.position + Number(deltaSeconds))
  }

  function setVolume(v) {
    if (!volumeSupported) return false
    var next = Math.max(0, Math.min(1, Number(v)))
    if (!isFinite(next)) return false
    player.volume = next
    return true
  }

  function toggleShuffle() {
    if (!shuffleSupported) return false
    _shuffle = !_shuffle  // optimistic; confirmed by the follow-up read
    _setOption("Shuffle", "b", _shuffle ? "true" : "false")
    return true
  }

  // Cycles none -> playlist -> track -> none, like Sonora's repeat button.
  function cycleLoop() {
    if (!loopSupported) return false
    _loop = _loop === "none" ? "playlist" : (_loop === "playlist" ? "track" : "none")
    _setOption("LoopStatus", "s", _loop === "track" ? "Track" : (_loop === "playlist" ? "Playlist" : "None"))
    return true
  }

  // Bring Sonora to the front, or start it if it isn't running.
  function focusApp() {
    Quickshell.execDetached(["omarchy-launch-or-focus", "sonora", "uwsm-app -- sonora"])
  }

  function fmtTime(seconds) {
    var s = Math.max(0, Math.floor(Number(seconds) || 0))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    var mm = h > 0 && m < 10 ? "0" + m : String(m)
    var ss = sec < 10 ? "0" + sec : String(sec)
    return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
  }

  function statusJson() {
    return JSON.stringify({
      running: available,
      playing: playing,
      title: title,
      artist: artist,
      album: album,
      artUrl: artUrl,
      position: position,
      length: length,
      volume: volume,
      shuffle: shuffle,
      loop: loopMode
    })
  }

  // ------------------------------------------------------------ IPC
  // omarchy-shell sonora <method> [arg]

  IpcHandler {
    target: "sonora"

    function status(): string { return root.statusJson() }
    function playPause(): string { return root.runAction("playPause", true) ? "ok" : "unavailable" }
    function play(): string { return root.runAction("play", true) ? "ok" : "unavailable" }
    function pause(): string { return root.runAction("pause", true) ? "ok" : "unavailable" }
    function stop(): string { return root.runAction("stop", true) ? "ok" : "unavailable" }
    function next(): string { return root.runAction("next", true) ? "ok" : "unavailable" }
    function previous(): string { return root.runAction("previous", true) ? "ok" : "unavailable" }
    function seek(seconds: string): string { return root.seekBy(Number(seconds)) ? "ok" : "unavailable" }
    function volume(percent: string): string { return root.setVolume(Number(percent) / 100) ? "ok" : "unavailable" }
    function shuffle(): string { return root.toggleShuffle() ? "ok" : "unavailable" }
    function repeat(): string { return root.cycleLoop() ? root.loopMode : "unavailable" }
    function focus(): string { root.focusApp(); return "ok" }
    function ping(): string { return "ok" }
  }
}
