/*
 * Copyright (c) 2026 Ronin-CK
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "components"

Scope {
    id: root

    Compositor {
        id: compositorObj
    }

    function envValue(keys, fallback) {
        for (let i = 0; i < keys.length; i++) {
            const value = Quickshell.env(keys[i]);
            if (value)
                return value;

        }
        return fallback;
    }

    property string activeScreenName: compositorObj.focusedScreen !== "" ? compositorObj.focusedScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    property string mode: ["region", "window"].indexOf(envValue(["QSS_MODE", "HQF_MODE"], "")) !== -1 ? envValue(["QSS_MODE", "HQF_MODE"], "") : "region"
    property var modes: ["edit", "region", "window", "temp"]
    property bool tempActive: envValue(["QSS_ACTION", "HQF_ACTION"], "") === "temp"
    property bool editActive: envValue(["QSS_ACTION", "HQF_ACTION"], "") === "edit"
    property bool shareActive: envValue(["QSS_ACTION", "HQF_ACTION"], "") === "share"
    property int connectivityStatus: 0
    property string lastSavedPath: ""
    property string lastTimestamp: ""
    readonly property real targetMenuWidth: (modes.length - (editActive ? 1 : 0) - (tempActive ? 1 : 0)) * 100 + 8
    property var theme: themeObj
    property bool capturing: false
    property bool overlaysVisible: true

    function parseTOML(text) {
        let result = {
        };
        let section = "";
        const lines = text.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (!line || line.startsWith("#"))
                continue;

            const secMatch = line.match(/^\[(\w+)\]$/);
            if (secMatch) {
                section = secMatch[1];
                continue;
            }
            const quotedMatch = line.match(/^(\w+)\s*=\s*"([^"]*)"/);
            if (quotedMatch) {
                const rawKey = quotedMatch[1];
                const key = section ? section + rawKey.charAt(0).toUpperCase() + rawKey.slice(1) : rawKey;
                result[key] = quotedMatch[2];
                continue;
            }
            const unquotedMatch = line.match(/^(\w+)\s*=\s*([^\s#]+)/);
            if (unquotedMatch) {
                const rawKey = unquotedMatch[1];
                const key = section ? section + rawKey.charAt(0).toUpperCase() + rawKey.slice(1) : rawKey;
                let val = unquotedMatch[2];
                if (val === "true") {
                    val = true;
                } else if (val === "false") {
                    val = false;
                } else {
                    const num = parseFloat(val);
                    if (!isNaN(num))
                        val = num;

                }
                result[key] = val;
                continue;
            }
        }
        return result;
    }

    function shellEscape(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }

    // Region coordinates are relative to the selected output; grim expects
    // layout coordinates, which Quickshell exposes on each screen.
    function grimGeometry(x, y, width, height, screenName) {
        let target = null;
        for (const s of Quickshell.screens) {
            if (s.name === screenName) { target = s; break; }
        }
        if (!target) target = Quickshell.screens.length > 0 ? Quickshell.screens[0] : { x: 0, y: 0 };
        return `${Math.round(x + target.x)},${Math.round(y + target.y)} ${Math.round(width)}x${Math.round(height)}`;
    }

    // Notifications are optional: prefer Noctalia, fall back to libnotify.
    function notificationCommand(summary, body, iconPath) {
        const backend = theme.notifications;
        if (backend === "none")
            return "true";

        const noctalia = `noctalia msg notification-show ${shellEscape(summary)} ${shellEscape(body)}`;
        const iconArg = iconPath ? ` -i ${shellEscape(iconPath)}` : "";
        const libnotify = `notify-send -a quickScreenShot${iconArg} ${shellEscape(summary)} ${shellEscape(body)}`;

        // Keep the command a plain `if` so it can be chained with `&&`
        // without running when the capture step failed.
        if (backend === "noctalia")
            return `if command -v noctalia >/dev/null 2>&1; then ${noctalia}; fi`;

        if (backend === "libnotify")
            return `if command -v notify-send >/dev/null 2>&1; then ${libnotify}; fi`;

        return `if command -v noctalia >/dev/null 2>&1; then ${noctalia}; `
            + `elif command -v notify-send >/dev/null 2>&1; then ${libnotify}; fi`;
    }

    // Annotation is optional: Noctalia first, then Satty, then Gradia.
    function annotationCommand(rawPath, outputPath, picturesDir) {
        const tool = theme.annotationTool;
        const eRaw = shellEscape(rawPath);
        const eOut = shellEscape(outputPath);
        const eDir = shellEscape(picturesDir);

        const noctalia = `noctalia msg annotate ${eRaw} --directory ${eDir} --copy-to-clipboard`;
        const satty = `satty --filename ${eRaw} --output-filename ${eOut} --early-exit --init-tool brush --copy-command "wl-copy --type image/png"; if [ -f ${eOut} ]; then wl-copy --type image/png < ${eOut}; fi`;
        const gradia = `setsid -f sh -c 'gradia "$0" || flatpak run be.alexandervanhee.gradia "$0"' ${eRaw} >/dev/null 2>&1`;
        const plain = `mv -f ${eRaw} ${eOut} && wl-copy --type image/png < ${eOut}`;

        if (tool === "noctalia")
            return noctalia;

        if (tool === "satty")
            return satty;

        if (tool === "gradia")
            return gradia;

        if (tool === "none")
            return plain;

        return `if command -v noctalia >/dev/null 2>&1; then ${noctalia}; `
            + `elif command -v satty >/dev/null 2>&1; then ${satty}; `
            + `elif command -v gradia >/dev/null 2>&1; then ${gradia}; `
            + `else ${plain}; fi`;
    }

    function runPostSaveHook() {
        const hook = theme.postSaveHook;
        if (!hook || !root.lastSavedPath)
            return ;

        const filePath = root.lastSavedPath;
        const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
        const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
        let cmd = hook;
        cmd = cmd.replace(/%f/g, shellEscape(filePath));
        cmd = cmd.replace(/%n/g, shellEscape(fileName));
        cmd = cmd.replace(/%d/g, shellEscape(dirPath));
        cmd = cmd.replace(/%t/g, shellEscape(root.lastTimestamp));
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    function saveScreenshot(x, y, width, height, screenName) {
        const geom = grimGeometry(x, y, width, height, screenName);
        const picturesBase = Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures");
        const picturesDir = picturesBase + "/Screenshots";
        const timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_hh-mm-ss");
        const outputPath = `${picturesDir}/screenshot-${timestamp}.png`;
        root.lastTimestamp = timestamp;
        root.lastSavedPath = root.tempActive ? "" : outputPath;
        const ePicturesDir = shellEscape(picturesDir);
        const eOutputPath = shellEscape(outputPath);
        const eGeom = shellEscape(geom);

        const grimRegion = `timeout 5 grim -l 1 -g ${eGeom}`;

        const shareCmd = "kdeconnect-cli -l | grep 'reachable' | grep -oP '[a-f0-9-]{8,}'"
            + " | head -1 | xargs -I{} sh -c"
            + " 'kdeconnect-cli -d {} --share \"$1\" && sleep 0.2"
            + " && kdeconnect-cli -d {} --send-clipboard' --";
        const maybeShare = (escapedPath) => root.shareActive ? ` && ${shareCmd} ${escapedPath}` : "";
        const shareTag = root.shareActive ? " & phone" : "";
        const mkdirCmd = `mkdir -p ${ePicturesDir}`;

        const defaultSaveCommand =
            `${mkdirCmd} && ${grimRegion} ${eOutputPath} `
            + `&& wl-copy --type image/png < ${eOutputPath}`
            + `${maybeShare(eOutputPath)} `
            + `&& ${notificationCommand("Screenshot Saved", `Saved to ${picturesDir}`, outputPath)}`;
        const eTempSnip = shellEscape(Quickshell.cachePath(`snip-${timestamp}.png`));
        const tempShareCommand =
            `${grimRegion} ${eTempSnip} `
            + `&& wl-copy --type image/png < ${eTempSnip}`
            + `${maybeShare(eTempSnip)} `
            + `&& ${notificationCommand("Screenshot Copied", `Copied to clipboard${shareTag}`)}; `
            + `rm -f ${eTempSnip}`;
        const tempPlainCommand =
            `${grimRegion} - | wl-copy --type image/png `
            + `&& ${notificationCommand("Screenshot Copied", "Copied to clipboard")}`;
        const defaultTempCommand = root.shareActive ? tempShareCommand : tempPlainCommand;

        const rawPath = Quickshell.cachePath(`edit-${timestamp}.png`);
        const eRawPath = shellEscape(rawPath);
        const editCommand =
            `${mkdirCmd} && ${grimRegion} ${eRawPath} `
            + `&& ${annotationCommand(rawPath, outputPath, picturesDir)}`;

        let cmd;
        if (root.editActive)
            cmd = editCommand;
        else if (root.tempActive)
            cmd = defaultTempCommand;
        else
            cmd = defaultSaveCommand;

        root._pendingCmd = cmd;
        root.capturing = true;
        captureDelayTimer.start();
        
        if (root.editActive)
            hideOverlaysTimer.start();
    }

    property string _pendingCmd: ""

    Timer {
        id: captureDelayTimer
        interval: 100
        repeat: false
        onTriggered: {
            screenshotProcess.command = ["sh", "-c", root._pendingCmd];
            screenshotProcess.running = true;
        }
    }

    Timer {
        id: hideOverlaysTimer
        interval: 300
        repeat: false
        onTriggered: root.overlaysVisible = false
    }

    Component.onCompleted: {
        connectivityProcess.running = true;
        readyWatchdog.start();
    }

    Timer {
        id: readyWatchdog
        interval: 4000
        repeat: false
        onTriggered: {
            for (const w of overlayVariants.instances) {
                if (w && w.isReady) return;
            }
            console.error("quickScreenShot: screencopy never produced a frame; exiting.");
            Qt.quit();
        }
    }

    Theme {
        id: themeObj
    }

    FileView {
        id: themeFile

        property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
        property string userPath1: configHome + "/quickScreenShot/theme.toml"
        property string userPath2: configHome + "/quickshell/quickScreenShot/theme.toml"
        property string defaultPath: Quickshell.shellDir.toString().replace(/^file:\/\//, "") + "/theme.toml"

        path: defaultPath
        Component.onCompleted: {
            themePathCheck.command = ["sh", "-c", `if [ -f "${userPath1}" ]; then echo "${userPath1}";
                 elif [ -f "${userPath2}" ]; then echo "${userPath2}";
                 else echo "${defaultPath}"; fi`];
            themePathCheck.running = true;
        }
        onTextChanged: {
            try {
                let rawText = (typeof text === 'function') ? text() : text;
                themeObj.source = root.parseTOML(rawText);
            } catch (e) {
                console.warn("Failed to parse theme.toml:", e);
            }
        }
    }

    Process {
        id: themePathCheck

        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                themeFile.path = this.text.trim();
                console.log("Theme loaded from:", themeFile.path);
            }
        }

    }

    Process {
        id: screenshotProcess

        running: false
        onExited: (code) => {
            if (code !== 0)
                console.error("Screenshot pipeline failed with exit code:", code);
            else
                root.runPostSaveHook();
            Qt.quit();
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim())
                    console.log(this.text);

            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim())
                    console.warn(this.text);

            }
        }

    }

    Process {
        id: connectivityProcess

        command: ["sh", "-c", "timeout 5 kdeconnect-cli -l | grep 'reachable'"]
        onExited: (code) => {
            root.connectivityStatus = (code === 0 ? 1 : 2);
        }
    }

    Variants {
        id: overlayVariants
        model: Quickshell.screens

        FreezeScreen {
            id: overlay

            required property var modelData
            property bool isFocused: modelData.name === root.activeScreenName
            property var themeRef: root.theme
            property var monitorInfo: ({
                name: modelData.name,
                x: modelData.x,
                y: modelData.y,
                width: modelData.width,
                height: modelData.height
            })
            property var windowList: compositorObj.windows.filter(w => w.output === modelData.name)

            function applyCursor() {
                const pos = compositorObj.cursor;
                if (!pos || pos.x < 0)
                    return ;

                const localX = pos.x - modelData.x;
                const localY = pos.y - modelData.y;
                regionSelector.mouseX = localX;
                regionSelector.mouseY = localY;
                windowSelector.mouseX = localX;
                windowSelector.mouseY = localY;
            }

            targetScreen: modelData
            visible: root.overlaysVisible
            Component.onCompleted: applyCursor()

            Connections {
                target: compositorObj

                function onCursorChanged() {
                    overlay.applyCursor();
                }
            }

            Shortcut {
                sequences: ["Escape", "q"]
                onActivated: Qt.quit()
            }

            Shortcut {
                sequence: "r"
                onActivated: root.mode = "region"
            }

            Shortcut {
                sequence: "w"
                onActivated: root.mode = "window"
            }

            Shortcut {
                sequence: "s"
                onActivated: {
                    let targetMon = overlay.modelData;
                    if (root.activeScreenName && root.activeScreenName !== targetMon.name) {
                        const screens = Quickshell.screens;
                        for (let i = 0; i < screens.length; i++) {
                            if (screens[i].name === root.activeScreenName) {
                                targetMon = screens[i];
                                break;
                            }
                        }
                    }
                    root.saveScreenshot(0, 0, targetMon.width, targetMon.height, targetMon.name);
                }
            }

            Shortcut {
                sequence: "e"
                onActivated: {
                    root.editActive = !root.editActive;
                    if (root.editActive)
                        root.tempActive = false;

                }
            }

            Shortcut {
                sequence: "t"
                onActivated: {
                    root.tempActive = !root.tempActive;
                    if (root.tempActive)
                        root.editActive = false;

                }
            }

            Shortcut {
                sequence: "k"
                onActivated: {
                    root.shareActive = !root.shareActive;
                    if (root.shareActive && !connectivityProcess.running && root.connectivityStatus !== 0)
                        connectivityProcess.running = true;

                }
            }

            RegionSelector {
                id: regionSelector

                visible: root.mode === "region" && overlay.isReady && !root.capturing
                anchors.fill: parent
                dimOpacity: overlay.themeRef.dimOpacity
                borderRadius: overlay.themeRef.borderRadius
                outlineThickness: overlay.themeRef.outlineThickness
                globalAnimations: overlay.themeRef.animations
                onRegionSelected: (x, y, width, height) => {
                    root.saveScreenshot(x, y, width, height, overlay.modelData.name);
                }
            }

            WindowSelector {
                id: windowSelector

                visible: root.mode === "window" && !root.capturing
                anchors.fill: parent
                monitor: overlay.monitorInfo
                windows: overlay.windowList
                dimOpacity: overlay.themeRef.dimOpacity
                borderRadius: overlay.themeRef.borderRadius
                outlineThickness: overlay.themeRef.outlineThickness
                animateSelection: overlay.themeRef.animations
                onRegionSelected: (x, y, width, height) => {
                    root.saveScreenshot(x, y, width, height, overlay.modelData.name);
                }
            }

            ControlBar {
                id: segmentedControl

                visible: overlay.isFocused && overlay.isReady && !root.capturing
                modes: root.modes
                mode: root.mode
                tempActive: root.tempActive
                editActive: root.editActive
                theme: overlay.themeRef
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: overlay.themeRef ? overlay.themeRef.bottomMargin : 60
                onModeSelected: (m) => {
                    return root.mode = m;
                }
                onTempToggled: {
                    root.tempActive = true;
                    root.editActive = false;
                }
                onEditToggled: {
                    root.editActive = true;
                    root.tempActive = false;
                }
            }

            QuickToggle {
                id: editToggleButton

                visible: overlay.isFocused && !root.capturing
                active: root.editActive
                icon: "" // "󰏫"
                imageSource: Qt.resolvedUrl("assets/icons/edit.svg")
                iconColor: overlay.themeRef.toggleEdit
                backgroundColor: overlay.themeRef.toggleBackground
                shadowColor: overlay.themeRef.toggleShadow
                borderColor: overlay.themeRef.barBorder
                borderWidth: 1
                targetX: (overlay.width - root.targetMenuWidth) / 2 - 15 - width
                targetY: segmentedControl.y + segmentedControl.height / 2
                sourceX: overlay.width / 2 - 204 + 32
                onClicked: root.editActive = false
            }

            QuickToggle {
                id: tempToggleButton

                visible: overlay.isFocused && !root.capturing
                active: root.tempActive
                icon: "" // "󰏫"
                imageSource: Qt.resolvedUrl("assets/icons/temp.svg")
                iconColor: overlay.themeRef.toggleTemp
                backgroundColor: overlay.themeRef.toggleBackground
                shadowColor: overlay.themeRef.toggleShadow
                borderColor: overlay.themeRef.barBorder
                borderWidth: 1
                targetX: (overlay.width + root.targetMenuWidth) / 2 + 15
                targetY: segmentedControl.y + segmentedControl.height / 2
                sourceX: overlay.width / 2 - 204 + 332
                onClicked: root.tempActive = false
            }

            QuickToggle {
                id: shareToggleButton

                visible: overlay.isFocused && !root.capturing
                active: root.shareActive
                icon: ""
                imageSource: root.connectivityStatus === 2 ? Qt.resolvedUrl("assets/icons/share-error.svg") : Qt.resolvedUrl("assets/icons/share.svg")
                iconColor: {
                    if (root.connectivityStatus === 1)
                        return overlay.themeRef.shareConnected;

                    if (root.connectivityStatus === 2)
                        return overlay.themeRef.shareErrorIcon;

                    return overlay.themeRef.sharePending;
                }
                backgroundColor: root.connectivityStatus === 2 ? overlay.themeRef.shareErrorBackground : overlay.themeRef.toggleBackground
                shadowColor: overlay.themeRef.toggleShadow
                borderColor: overlay.themeRef.barBorder
                borderWidth: 1
                pulse: root.connectivityStatus === 0
                targetX: (overlay.width + root.targetMenuWidth) / 2 + 15 + (root.tempActive ? 44 + 10 : 0)
                targetY: segmentedControl.y + segmentedControl.height / 2
                sourceX: overlay.width / 2 + (root.targetMenuWidth / 2) - 22
                onClicked: root.shareActive = false
            }

            Item {
                visible: !root.capturing
                anchors.fill: parent
                z: 999

                HoverHandler {
                    onPointChanged: {
                        root.activeScreenName = overlay.modelData.name;
                        if (root.mode === "region" && !regionSelector.pressed) {
                            regionSelector.mouseX = point.position.x;
                            regionSelector.mouseY = point.position.y;
                        }
                        if (root.mode === "window" && !windowSelector.pressed) {
                            windowSelector.mouseX = point.position.x;
                            windowSelector.mouseY = point.position.y;
                        }
                    }
                }

            }

        }

    }

}
