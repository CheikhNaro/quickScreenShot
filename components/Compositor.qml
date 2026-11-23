/*
 * Compositor abstraction for quickScreenShot.
 *
 * Supports Hyprland, MangoWM, Umbriel and a generic fallback based on
 * Quickshell.screens (region/temp still work, window mode is disabled).
 */

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string name: detect()
    readonly property bool supportsWindows: name === "hyprland" || name === "mango" || name === "umbriel"

    // [{ name, x, y, width, height, focused }]
    property var monitors: []
    // [{ x, y, w, h, output, title, appid }] in global layout coordinates
    property var windows: []
    // { x, y, monitor } in global layout coordinates
    property var cursor: ({
        x: -1,
        y: -1,
        monitor: ""
    })

    readonly property string focusedScreen: {
        for (let i = 0; i < monitors.length; i++) {
            if (monitors[i].focused)
                return monitors[i].name;

        }
        if (cursor && cursor.monitor)
            return cursor.monitor;

        return "";
    }

    function env(key) {
        return Quickshell.env(key) || "";
    }

    function detect() {
        if (env("HYPRLAND_INSTANCE_SIGNATURE"))
            return "hyprland";

        if (env("MANGO_INSTANCE_SIGNATURE"))
            return "mango";

        if (env("UMBRIEL_SOCKET") || env("UMBRIEL_INSTANCE_SIGNATURE"))
            return "umbriel";

        const desktop = (env("XDG_CURRENT_DESKTOP") + " " + env("XDG_SESSION_DESKTOP")).toLowerCase();
        if (desktop.indexOf("hyprland") !== -1)
            return "hyprland";

        if (desktop.indexOf("mango") !== -1)
            return "mango";

        if (desktop.indexOf("umbriel") !== -1)
            return "umbriel";

        return "generic";
    }

    function monitorCommand() {
        if (name === "hyprland")
            return ["hyprctl", "monitors", "-j"];

        if (name === "mango")
            return ["mmsg", "get", "all-monitors"];

        if (name === "umbriel")
            return ["umbriel", "outputs", "--json"];

        return [];
    }

    function windowCommand() {
        if (name === "hyprland")
            return ["hyprctl", "clients", "-j"];

        if (name === "mango")
            return ["mmsg", "get", "all-clients"];

        if (name === "umbriel")
            return ["umbriel", "windows", "--json"];

        return [];
    }

    function cursorCommand() {
        if (name === "hyprland")
            return ["hyprctl", "cursorpos", "-j"];

        if (name === "mango")
            return ["mmsg", "get", "cursorpos"];

        // Umbriel does not expose a global pointer position.
        return [];
    }

    function genericMonitors() {
        return Quickshell.screens.map(s => ({
                    name: s.name,
                    x: s.x,
                    y: s.y,
                    width: s.width,
                    height: s.height,
                    focused: false
                }));
    }

    function parseMonitors(text) {
        try {
            const data = JSON.parse(text);
            if (name === "hyprland") {
                return (data || []).map(m => ({
                            name: m.name,
                            x: m.x,
                            y: m.y,
                            width: m.width,
                            height: m.height,
                            focused: !!m.focused
                        }));
            }
            if (name === "mango") {
                return (data.monitors || []).filter(m => m.active !== false).map(m => ({
                            name: m.name,
                            x: m.x,
                            y: m.y,
                            width: m.width,
                            height: m.height,
                            focused: false
                        }));
            }
            if (name === "umbriel") {
                return (data.ok || []).filter(o => o.enabled).map(o => ({
                            name: o.name,
                            x: o.position.x,
                            y: o.position.y,
                            width: o.logical_size.width,
                            height: o.logical_size.height,
                            focused: !!o.focused
                        }));
            }
        } catch (e) {
            console.warn("quickScreenShot: failed to parse monitors:", e);
        }
        return [];
    }

    function parseWindows(text) {
        try {
            const data = JSON.parse(text);
            if (name === "hyprland") {
                return (data || []).filter(w => w.mapped && !w.hidden).map(w => ({
                            x: w.at[0],
                            y: w.at[1],
                            w: w.size[0],
                            h: w.size[1],
                            output: w.monitor,
                            title: w.title,
                            appid: w.class
                        }));
            }
            if (name === "mango") {
                return (data.clients || []).filter(c => c.is_visible).map(c => ({
                            x: c.x,
                            y: c.y,
                            w: c.width,
                            h: c.height,
                            output: c.monitor,
                            title: c.title,
                            appid: c.appid
                        }));
            }
            if (name === "umbriel") {
                return (data.ok || []).filter(w => w.visible).map(w => ({
                            x: w.x,
                            y: w.y,
                            w: w.w,
                            h: w.h,
                            output: w.output,
                            title: w.title,
                            appid: w.app_id
                        }));
            }
        } catch (e) {
            console.warn("quickScreenShot: failed to parse windows:", e);
        }
        return [];
    }

    function parseCursor(text) {
        try {
            const data = JSON.parse(text);
            return {
                x: data.x,
                y: data.y,
                monitor: data.monitor || ""
            };
        } catch (e) {
            console.warn("quickScreenShot: failed to parse cursor position:", e);
            return {
                x: -1,
                y: -1,
                monitor: ""
            };
        }
    }

    function refresh() {
        if (name === "generic") {
            monitors = genericMonitors();
            return;
        }
        if (monitorCommand().length > 0)
            monitorsProcess.running = true;

        if (windowCommand().length > 0)
            windowsProcess.running = true;

        if (cursorCommand().length > 0)
            cursorProcess.running = true;

    }

    Component.onCompleted: refresh()

    property Process monitorsProcess: Process {
        command: root.monitorCommand()

        stdout: StdioCollector {
            onStreamFinished: root.monitors = root.parseMonitors(this.text)
        }

    }

    property Process windowsProcess: Process {
        command: root.windowCommand()

        stdout: StdioCollector {
            onStreamFinished: root.windows = root.parseWindows(this.text)
        }

    }

    property Process cursorProcess: Process {
        command: root.cursorCommand()

        stdout: StdioCollector {
            onStreamFinished: {
                root.cursor = root.parseCursor(this.text);
                // MangoWM does not mark a focused monitor; the pointer does.
                if (root.name === "mango" && root.cursor.monitor) {
                    root.monitors = root.monitors.map(m => Object.assign({}, m, {
                                focused: m.name === root.cursor.monitor
                            }));
                }
            }
        }

    }

}
