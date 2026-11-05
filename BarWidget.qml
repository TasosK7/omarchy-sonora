import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Ui
import qs.Commons

// Bar entry for Sonora, styled after Sonora itself: the five-bar waveform from
// its logo (animated while playing), a small cover thumbnail, a two-tone
// title/artist label and a hairline progress bar. Left click toggles
// play/pause, middle click skips, the wheel moves between tracks, and right
// click opens a "Now Playing" card modelled on Sonora's now-playing view.
BarWidget {
  id: root
  moduleName: "io.github.tasosk7.sonora"

  readonly property var sonora: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool available: sonora ? sonora.available : false
  readonly property bool playing: sonora ? sonora.playing : false
  readonly property string title: sonora ? sonora.title : ""
  readonly property string artist: sonora ? sonora.artist : ""
  readonly property string artUrl: sonora ? sonora.artUrl : ""
  readonly property real progress: sonora && sonora.length > 0
    ? Math.max(0, Math.min(1, sonora.position / sonora.length)) : 0

  readonly property real maxLabelWidth: setting("maxLabelWidth", 180)
  readonly property bool hideWhenUnavailable: setting("hideWhenUnavailable", true) === true
  readonly property bool showArtist: setting("showArtist", true) === true
  readonly property bool showCover: setting("showCover", true) === true
  readonly property bool showProgress: setting("showProgress", true) === true

  // Sonora's UI typeface is Inter; use it in the card when it's installed.
  readonly property string textFont: Qt.fontFamilies().indexOf("Inter") >= 0
    ? "Inter" : (bar ? bar.fontFamily : "sans-serif")

  property bool popupOpen: false

  // open/close/opened let `omarchy-shell shell toggle io.github.tasosk7.sonora ''`
  // open the card on the focused monitor (handy for a keybinding).
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }

  visible: !hideWhenUnavailable || available
  implicitWidth: visible ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  // ---------------------------------------------------------------- pieces

  // The Sonora logo: five rounded bars, symmetric around the tallest. While
  // `active`, each bar bounces on its own rhythm; otherwise they settle back
  // into the logo silhouette.
  component Waveform: Item {
    id: wave
    property bool active: false
    property color color: "white"
    property real barWidth: 2
    property real gap: 2

    implicitWidth: barWidth * 5 + gap * 4
    implicitHeight: 14

    Row {
      anchors.centerIn: parent
      spacing: wave.gap

      Repeater {
        model: 5

        Rectangle {
          id: waveBar
          required property int index
          readonly property real base: [0.3, 0.64, 1.0, 0.64, 0.3][index]
          readonly property bool running: wave.active
          property real level: base

          anchors.verticalCenter: parent.verticalCenter
          width: wave.barWidth
          height: Math.max(wave.barWidth, wave.height * level)
          radius: width / 2
          color: wave.color

          onRunningChanged: if (!running) settle.restart()

          SequentialAnimation on level {
            running: waveBar.running
            loops: Animation.Infinite
            NumberAnimation {
              to: Math.min(1, waveBar.base + 0.5)
              duration: 240 + ((waveBar.index * 97) % 5) * 45
              easing.type: Easing.InOutSine
            }
            NumberAnimation {
              to: Math.max(0.2, waveBar.base - 0.3)
              duration: 280 + ((waveBar.index * 61) % 4) * 55
              easing.type: Easing.InOutSine
            }
          }

          NumberAnimation {
            id: settle
            target: waveBar
            property: "level"
            to: waveBar.base
            duration: 220
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }

  // Cover art clipped to a rounded rectangle.
  component RoundedArt: Item {
    id: art
    property string source: ""
    property real radius: 4
    readonly property bool ready: img.status === Image.Ready && source !== ""

    Rectangle {
      id: artMask
      anchors.fill: parent
      radius: art.radius
      visible: false
      layer.enabled: true
    }

    Image {
      id: img
      anchors.fill: parent
      source: art.source
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      mipmap: true
      visible: art.ready
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: artMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }
  }

  // Slim Sonora-style scrubber: a thin white line that thickens and grows a
  // knob on hover.
  component SlimSlider: Item {
    id: slider
    property real value: 0
    property real maximum: 1
    property bool interactive: true
    property bool dragging: false
    property real liveValue: value
    readonly property bool hot: sliderMouse.containsMouse || dragging
    readonly property real fraction: maximum > 0 ? Math.max(0, Math.min(1, liveValue / maximum)) : 0

    signal moved(real value)
    signal released(real value)

    onValueChanged: if (!dragging) liveValue = value

    implicitHeight: Style.space(14)

    Rectangle {
      id: slimTrack
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: slider.hot ? 5 : 3
      radius: height / 2
      color: Qt.rgba(1, 1, 1, 0.22)
      Behavior on height { NumberAnimation { duration: 120 } }

      Rectangle {
        height: parent.height
        radius: parent.radius
        width: parent.width * slider.fraction
        color: slider.hot ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
      }
    }

    Rectangle {
      width: 12
      height: 12
      radius: 6
      color: "#ffffff"
      anchors.verticalCenter: parent.verticalCenter
      x: slimTrack.width * slider.fraction - width / 2
      visible: slider.interactive
      opacity: slider.hot ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    MouseArea {
      id: sliderMouse
      anchors.fill: parent
      anchors.topMargin: -4
      anchors.bottomMargin: -4
      enabled: slider.interactive
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      function valueAt(x) {
        return Math.max(0, Math.min(1, x / Math.max(1, width))) * slider.maximum
      }
      onPressed: function(mouse) {
        slider.dragging = true
        slider.liveValue = valueAt(mouse.x)
        slider.moved(slider.liveValue)
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        slider.liveValue = valueAt(mouse.x)
        slider.moved(slider.liveValue)
      }
      onReleased: {
        slider.released(slider.liveValue)
        slider.dragging = false
      }
    }
  }

  // Glyph button for the transport row. `active` draws Sonora's small dot
  // under toggles (shuffle / repeat) that are switched on.
  component GlyphButton: Item {
    id: btn
    property string glyph: ""
    property real size: Style.font.iconLarge
    property bool active: false
    property bool showDot: false
    property bool available: true
    signal clicked()

    implicitWidth: Math.max(size + Style.space(10), Style.space(30))
    implicitHeight: implicitWidth
    opacity: available ? 1 : 0.3

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: btn.glyph
      font.family: root.bar ? root.bar.fontFamily : ""
      font.pixelSize: btn.size
      color: btn.active || btnMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.66)
      scale: btnMouse.pressed ? 0.9 : (btnMouse.containsMouse ? 1.08 : 1)
      Behavior on scale { NumberAnimation { duration: 90 } }
    }

    Rectangle {
      visible: btn.showDot && btn.active
      width: 4
      height: 4
      radius: 2
      color: "#ffffff"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 1
    }

    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.available
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  // ---------------------------------------------------------------- bar

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(7)

    RoundedArt {
      id: thumb
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(root.barSize * 0.6)
      height: width
      radius: Math.max(2, Math.round(width * 0.18))
      source: root.artUrl
      visible: root.showCover && root.available && root.artUrl !== "" && !root.vertical
    }

    Waveform {
      id: barWave
      anchors.verticalCenter: parent.verticalCenter
      height: Math.round(Style.font.body * 0.95)
      barWidth: Math.max(2, Math.round(Style.font.body / 7))
      gap: Math.max(1, Math.round(barWidth * 0.8))
      active: root.playing && !root.popupOpen
      color: root.playing ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.6)
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelRow.implicitWidth)
      height: labelRow.implicitHeight
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.title !== ""

      Row {
        id: labelRow
        spacing: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        x: 0

        Text {
          textFormat: Text.PlainText
          text: root.title
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: root.artist
          visible: root.showArtist && root.artist !== ""
          color: Qt.darker(root.bar.barForeground, 1.45)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        readonly property bool needsScroll: implicitWidth > scrollClip.width
        readonly property bool canScroll: needsScroll && !root.popupOpen && !root.vertical

        // Drive the marquee explicitly so it reliably restarts on track change.
        function syncScroll() {
          scrollAnim.stop()
          labelRow.x = 0
          if (canScroll) scrollAnim.start()
        }
        onCanScrollChanged: syncScroll()
        onImplicitWidthChanged: syncScroll()
        Component.onCompleted: syncScroll()

        SequentialAnimation {
          id: scrollAnim
          loops: Animation.Infinite
          PauseAnimation { duration: 1800 }
          NumberAnimation {
            target: labelRow
            property: "x"
            from: 0
            to: scrollClip.width - labelRow.implicitWidth
            duration: Math.max(2000, (labelRow.implicitWidth - scrollClip.width) * 28)
            easing.type: Easing.InOutSine
          }
          PauseAnimation { duration: 1800 }
          NumberAnimation {
            target: labelRow
            property: "x"
            to: 0
            duration: Math.max(2000, (labelRow.implicitWidth - scrollClip.width) * 28)
            easing.type: Easing.InOutSine
          }
        }
      }

      // Fade the clipped edge instead of hard-cutting the text.
      Rectangle {
        anchors.right: parent.right
        width: Style.space(14)
        height: parent.height
        visible: labelRow.needsScroll && labelRow.x > scrollClip.width - labelRow.implicitWidth + 1
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 1; color: root.bar.transparent ? "transparent" : root.bar.background }
        }
      }
    }
  }

  // Hairline playback progress along the bottom of the widget.
  Rectangle {
    visible: root.showProgress && root.available && !root.vertical && !root.popupOpen
      && root.sonora !== null && root.sonora.length > 0
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(3)
    x: row.x
    width: row.width
    height: 2
    radius: 1
    color: Qt.rgba(root.bar.barForeground.r, root.bar.barForeground.g, root.bar.barForeground.b, 0.18)

    Rectangle {
      height: parent.height
      radius: parent.radius
      width: parent.width * root.progress
      color: root.bar.barForeground
      Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.popupOpen = !root.popupOpen
        return
      }
      if (!root.sonora) return
      if (!root.available) {
        if (mouse.button === Qt.LeftButton) root.sonora.focusApp()
        return
      }
      if (mouse.button === Qt.MiddleButton) root.sonora.runAction("next", false)
      else root.sonora.runAction("playPause", false)
    }
    onWheel: function(wheel) {
      if (!root.sonora || !root.available) return
      if (wheel.angleDelta.y > 0) root.sonora.runAction("previous", false)
      else if (wheel.angleDelta.y < 0) root.sonora.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root,
      root.sonora ? root.sonora.summary() : "Sonora")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // ---------------------------------------------------------------- card

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    padding: 0
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(card.implicitHeight)

    Item {
      id: card
      anchors.fill: parent
      implicitHeight: content.implicitHeight + inset * 2
      readonly property real inset: Style.space(18)

      // Ambient backdrop: the cover art blurred and darkened, the way Sonora
      // tints its now-playing view with the current album.
      Rectangle {
        id: backdropMask
        anchors.fill: parent
        radius: Math.max(0, Style.cornerRadius - 1)
        visible: false
        layer.enabled: true
      }

      Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: backdropMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }

        Rectangle {
          anchors.fill: parent
          color: "#0e0e0e"
        }

        Image {
          id: ambient
          anchors.centerIn: parent
          width: parent.width * 1.6
          height: parent.height * 1.6
          source: root.artUrl
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 256
          sourceSize.height: 256
          visible: root.artUrl !== "" && status === Image.Ready
          opacity: 0.55
          layer.enabled: true
          layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 0.15
          }
          Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.5) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.78) }
          }
        }
      }

      Column {
        id: content
        anchors.fill: parent
        anchors.margins: card.inset
        spacing: Style.space(14)

        // Header: Sonora logo + "Now playing" + open-in-app.
        Item {
          width: parent.width
          height: Style.space(22)

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(22)
              height: width
              radius: width / 2
              color: "#ffffff"

              Waveform {
                anchors.centerIn: parent
                width: implicitWidth
                height: parent.height * 0.6
                barWidth: Math.max(1.5, parent.width / 14)
                gap: Math.max(1, parent.width / 14)
                color: "#000000"
                active: root.playing && root.popupOpen
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.available ? (root.playing ? "NOW PLAYING" : "PAUSED") : "SONORA"
              color: Qt.rgba(1, 1, 1, 0.7)
              font.family: root.textFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.5
            }
          }

          GlyphButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Style.space(26)
            glyph: "󰏌"
            size: Style.font.body
            onClicked: {
              if (root.sonora) root.sonora.focusApp()
              root.close()
            }
          }
        }

        // Cover art, large and centered, with a soft drop shadow.
        Item {
          id: artFrame
          width: parent.width
          height: width
          readonly property real artRadius: Style.space(10)

          Rectangle {
            id: artShadowSource
            anchors.fill: parent
            radius: artFrame.artRadius
            color: "#000000"
            visible: false
          }

          MultiEffect {
            anchors.fill: artShadowSource
            source: artShadowSource
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.6)
            shadowBlur: 1.0
            shadowVerticalOffset: Style.space(6)
            opacity: bigArt.ready ? 1 : 0
          }

          Rectangle {
            anchors.fill: parent
            radius: artFrame.artRadius
            color: Qt.rgba(1, 1, 1, 0.06)
            visible: !bigArt.ready

            Waveform {
              anchors.centerIn: parent
              width: implicitWidth
              height: parent.height * 0.32
              barWidth: Math.max(4, parent.width / 26)
              gap: barWidth
              color: Qt.rgba(1, 1, 1, 0.35)
              active: root.playing && root.popupOpen
            }
          }

          RoundedArt {
            id: bigArt
            anchors.fill: parent
            radius: artFrame.artRadius
            source: root.artUrl
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.sonora) root.sonora.focusApp()
              root.close()
            }
          }
        }

        // Title / artist, centered like Sonora's now-playing view.
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: !root.available ? "Sonora is not running" : (root.title || "Nothing playing")
            color: "#ffffff"
            font.family: root.textFont
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.available ? root.artist : "Click the art to launch it"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: root.textFont
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            visible: text !== ""
          }
        }

        // Scrubber with elapsed / total times.
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.sonora !== null && root.sonora.length > 0

          SlimSlider {
            id: seekSlider
            width: parent.width
            maximum: root.sonora ? Math.max(1, root.sonora.length) : 1
            value: root.sonora ? root.sonora.position : 0
            interactive: root.sonora ? root.sonora.canSeek : false
            onReleased: function(v) { if (root.sonora) root.sonora.seekTo(v) }
          }

          Item {
            width: parent.width
            height: elapsed.implicitHeight

            Text {
              id: elapsed
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: root.sonora ? root.sonora.fmtTime(seekSlider.dragging ? seekSlider.liveValue : root.sonora.position) : ""
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.sonora ? "-" + root.sonora.fmtTime(root.sonora.length - (seekSlider.dragging ? seekSlider.liveValue : root.sonora.position)) : ""
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Transport: shuffle · previous · (play) · next · repeat
        Item {
          width: parent.width
          height: playButton.height

          GlyphButton {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.sonora && root.sonora.shuffle ? "󰒝" : "󰒞"
            size: Style.font.body + 2
            showDot: true
            active: root.sonora ? root.sonora.shuffle : false
            available: root.sonora ? root.sonora.shuffleSupported : false
            onClicked: root.sonora.toggleShuffle()
          }

          Row {
            anchors.centerIn: parent
            spacing: Style.space(14)

            GlyphButton {
              anchors.verticalCenter: parent.verticalCenter
              glyph: "󰒮"
              available: root.sonora ? root.sonora.canPrevious : false
              onClicked: root.sonora.runAction("previous", false)
            }

            // The white disc echoes Sonora's logo.
            Rectangle {
              id: playButton
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(48)
              height: width
              radius: width / 2
              color: "#ffffff"
              opacity: root.available ? 1 : 0.35
              scale: playMouse.pressed ? 0.92 : (playMouse.containsMouse ? 1.06 : 1)
              Behavior on scale { NumberAnimation { duration: 100 } }

              Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.playing ? 0 : 1
                textFormat: Text.PlainText
                text: root.playing ? "󰏤" : "󰐊"
                color: "#000000"
                font.family: root.bar ? root.bar.fontFamily : ""
                font.pixelSize: Style.font.iconLarge + 4
              }

              MouseArea {
                id: playMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.available
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sonora.runAction("playPause", false)
              }
            }

            GlyphButton {
              anchors.verticalCenter: parent.verticalCenter
              glyph: "󰒭"
              available: root.sonora ? root.sonora.canNext : false
              onClicked: root.sonora.runAction("next", false)
            }
          }

          GlyphButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            readonly property string mode: root.sonora ? root.sonora.loopMode : "none"
            glyph: mode === "track" ? "󰑘" : "󰑖"
            size: Style.font.body + 2
            showDot: true
            active: mode !== "none"
            available: root.sonora ? root.sonora.loopSupported : false
            onClicked: root.sonora.cycleLoop()
          }
        }

        // Sonora's own player volume (independent of system volume).
        Row {
          width: parent.width
          spacing: Style.space(10)
          visible: root.sonora ? root.sonora.volumeSupported : false

          Text {
            id: volIcon
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: !root.sonora || root.sonora.volume <= 0 ? "󰝟" : (root.sonora.volume < 0.5 ? "󰖀" : "󰕾")
            color: Qt.rgba(1, 1, 1, 0.66)
            font.family: root.bar ? root.bar.fontFamily : ""
            font.pixelSize: Style.font.body
            width: Style.space(16)
            horizontalAlignment: Text.AlignHCenter
          }

          SlimSlider {
            id: volSlider
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - volIcon.width - volText.width - parent.spacing * 2
            maximum: 1
            value: root.sonora ? root.sonora.volume : 0
            onMoved: function(v) { if (root.sonora) root.sonora.setVolume(v) }
          }

          Text {
            id: volText
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Math.round((volSlider.dragging ? volSlider.liveValue : (root.sonora ? root.sonora.volume : 0)) * 100) + "%"
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: root.textFont
            font.pixelSize: Style.font.caption
            width: Style.space(32)
            horizontalAlignment: Text.AlignRight
          }
        }
      }
    }
  }
}
