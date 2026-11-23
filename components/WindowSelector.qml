/*
 * This file contains code based on "HyprQuickshot"
 * Original Author: JamDon2 (Copyright 2025)
 * Licensed under the MIT License.
 *
 * Modifications and other code: Copyright (c) 2026 Ronin-CK
 *
 * Copyright (c) 2025 JamDon2
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
 
import QtQuick  
Item {  
    id: root

    // { name, x, y, width, height } in global layout coordinates
    property var monitor: null
    // [{ x, y, w, h, output, title, appid }] in global layout coordinates
    property var windows: []

    signal regionSelected(real x, real y, real width, real height)
    property alias pressed: mouseArea.pressed

    property real mouseX: 0
    property real mouseY: 0
    onMouseXChanged: updateHovered()
    onMouseYChanged: updateHovered()

    property real dimOpacity: 0.6
    property real borderRadius: 10.0
    property real outlineThickness: 2.0
    property url fragmentShader: Qt.resolvedUrl("../shaders/dimming.frag.qsb")

    property real selectionX: 0
    property real selectionY: 0
    property real selectionWidth: 0
    property real selectionHeight: 0

    property bool animateSelection: true

    function hitWindow(mx, my) {
        if (!monitor)
            return null;
        const list = windows;
        for (let i = list.length - 1; i >= 0; i--) {
            const w = list[i];
            if (!w) continue;
            const wx = w.x - monitor.x;
            const wy = w.y - monitor.y;
            if (mx >= wx && mx <= wx + w.w && my >= wy && my <= wy + w.h) {
                return { x: wx, y: wy, w: w.w, h: w.h };
            }
        }
        return null;
    }

    function updateHovered() {
        const hit = hitWindow(mouseX, mouseY);
        if (!hit) return;
        selectionX = hit.x;
        selectionY = hit.y;
        selectionWidth = hit.w;
        selectionHeight = hit.h;
    }

    Behavior on selectionX { enabled: root.animateSelection; SpringAnimation { spring: 5; damping: 0.7; mass: 1.0; epsilon: 0.1 } }
    Behavior on selectionY { enabled: root.animateSelection; SpringAnimation { spring: 5; damping: 0.7; mass: 1.0; epsilon: 0.1 } }
    Behavior on selectionHeight { enabled: root.animateSelection; SpringAnimation { spring: 5; damping: 0.7; mass: 1.0; epsilon: 0.1 } }
    Behavior on selectionWidth { enabled: root.animateSelection; SpringAnimation { spring: 5; damping: 0.7; mass: 1.0; epsilon: 0.1 } }


    ShaderEffect {
        anchors.fill: parent
        z: 0

        property vector4d selectionRect: Qt.vector4d(
            root.selectionX,
            root.selectionY,
            root.selectionWidth,
            root.selectionHeight
        )
        property real dimOpacity: root.dimOpacity
        property vector2d screenSize: Qt.vector2d(root.width, root.height)
        property real borderRadius: root.borderRadius
        property real outlineThickness: root.outlineThickness

        fragmentShader: root.fragmentShader
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        z: 3
        hoverEnabled: true

        onPositionChanged: (mouse) => {
            root.mouseX = mouse.x;
            root.mouseY = mouse.y;
        }

        onReleased: (mouse) => {
            const hit = root.hitWindow(mouse.x, mouse.y);
            if (!hit) return;
            root.regionSelected(
                Math.round(hit.x),
                Math.round(hit.y),
                Math.round(hit.w),
                Math.round(hit.h)
            );
        }
    }
}
