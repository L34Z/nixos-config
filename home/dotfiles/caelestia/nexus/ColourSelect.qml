pragma ComponentBehavior: Bound

// Replaces upstream's "under construction" Colours page (see home/z.nix,
// which copies this over modules/nexus/pages/wallandstyle/ColourSelect.qml).
//
// Edits ~/.local/state/caelestia/scheme.json in place; the Colours service
// watches that file, so every change restyles the whole shell live. Six
// "role" rows cover the visible bar elements (each fans out to the derived
// m3 tokens), and an advanced list exposes every token individually.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Colours")
    isSubPage: true

    property var schemeData: null
    property int rev: 0
    property string snapshot
    property bool showAll
    property bool harmonious: true
    property var presets: ({})
    property int presetsRev: 0

    readonly property var tokenKeys: schemeData ? Object.keys(schemeData.colours) : []

    readonly property var presetNames: {
        const _ = presetsRev;
        return Object.keys(presets).sort();
    }

    readonly property var roles: [
        {
            key: "base",
            token: "surface",
            icon: "layers",
            label: qsTr("Base"),
            subtext: qsTr("Bar and panel background — also sets light/dark")
        },
        {
            key: "text",
            token: "onSurface",
            icon: "text_fields",
            label: qsTr("Text"),
            subtext: qsTr("General text on the background")
        },
        {
            key: "outer",
            token: "surfaceContainer",
            icon: "rectangle",
            label: qsTr("Outer pills"),
            subtext: qsTr("Module containers on the bar and grouped rows")
        },
        {
            key: "inner",
            token: "primary",
            icon: "radio_button_checked",
            label: qsTr("Inner pills"),
            subtext: qsTr("Active workspace and the main accent")
        },
        {
            key: "icons",
            token: "secondary",
            icon: "apps",
            label: qsTr("Status icons"),
            subtext: qsTr("Network, audio and tray icons")
        },
        {
            key: "clock",
            token: "tertiary",
            icon: "schedule",
            label: qsTr("Clock & logo"),
            subtext: qsTr("Clock text and the OS logo")
        }
    ]

    function clamp01(x: real): real {
        return Math.max(0, Math.min(1, x));
    }

    function hx(c: color): string {
        return c.toString().slice(1, 7);
    }

    function withL(c: color, l: real): color {
        return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation, clamp01(l), 1);
    }

    function shiftL(c: color, d: real): color {
        return withL(c, c.hslLightness + d);
    }

    function desat(c: color, f: real): color {
        return Qt.hsla(Math.max(0, c.hslHue), clamp01(c.hslSaturation * f), c.hslLightness, 1);
    }

    function tokenHex(key: string): string {
        const _ = rev;
        return schemeData?.colours[key] ?? "000000";
    }

    function tokenColour(key: string): color {
        return `#${tokenHex(key)}`;
    }

    // Typed return coerces the hex string into a colour value
    function toColour(hex: string): color {
        return `#${hex}`;
    }

    function markDirty(): void {
        rev++;
        saveTimer.restart();
    }

    function setTokenHex(key: string, hex: string): void {
        if (!schemeData || !/^[0-9a-fA-F]{6}$/.test(hex))
            return;
        schemeData.colours[key] = hex.toLowerCase();
        markDirty();
    }

    // Container/fixed/"on" shades for the primary/secondary/tertiary families
    function applyFamily(prefix: string, c: color): void {
        const light = schemeData.mode === "light";
        const cap = prefix[0].toUpperCase() + prefix.slice(1);
        const cs = schemeData.colours;
        cs[prefix] = hx(c);
        cs[`on${cap}`] = hx(Colours.on(c));
        cs[`${prefix}Container`] = hx(withL(c, light ? 0.85 : 0.3));
        cs[`on${cap}Container`] = hx(withL(c, light ? 0.2 : 0.9));
        cs[`${prefix}Fixed`] = hx(withL(c, 0.85));
        cs[`${prefix}FixedDim`] = hx(withL(c, 0.7));
        cs[`on${cap}Fixed`] = hx(withL(c, 0.12));
        cs[`on${cap}FixedVariant`] = hx(withL(c, 0.3));
    }

    function rand(lo: real, hi: real): real {
        return lo + Math.random() * (hi - lo);
    }

    function openWheel(title: string, c: color, apply: var): void {
        wheelPopup.title = title;
        wheelPopup.initial = c;
        wheelPopup.apply = apply;
        wheelPopup.active = true;
    }

    function pick(xs: var): var {
        return xs[Math.floor(Math.random() * xs.length)];
    }

    // Rolls all six roles; the derived tokens fan out via applyRole, so a
    // generated scheme stays as consistent as a hand-edited one. Revert
    // still restores the page-open snapshot.
    function generate(): void {
        if (!schemeData)
            return;

        if (harmonious) {
            // One hue for everything; icons sit a step away on the wheel and
            // the clock takes a triadic/complementary jump. Base lightness
            // stays on the current side so light/dark mode is preserved.
            const dark = schemeData.mode !== "light";
            const h = Math.random();
            const spread = pick([-1, 1]) * rand(0.09, 0.17);
            const sSurface = rand(0.12, 0.35);
            applyRole("base", Qt.hsla(h, sSurface, dark ? rand(0.07, 0.13) : rand(0.9, 0.96), 1));
            applyRole("text", Qt.hsla(h, rand(0.05, 0.25), dark ? rand(0.86, 0.94) : rand(0.08, 0.16), 1));
            applyRole("outer", Qt.hsla(h, sSurface, dark ? rand(0.16, 0.24) : rand(0.8, 0.88), 1));
            applyRole("inner", Qt.hsla(h, rand(0.5, 0.85), dark ? rand(0.65, 0.82) : rand(0.32, 0.5), 1));
            applyRole("icons", Qt.hsla((h + spread + 1) % 1, rand(0.4, 0.75), dark ? rand(0.62, 0.8) : rand(0.32, 0.5), 1));
            applyRole("clock", Qt.hsla((h + pick([0.33, -0.33, 0.5]) + 1) % 1, rand(0.35, 0.7), dark ? rand(0.62, 0.8) : rand(0.32, 0.5), 1));
        } else {
            // Anything goes — except text, which is pushed to the far side of
            // the base lightness so the result is chaotic but never unreadable.
            const baseL = Math.random();
            const isL = baseL >= 0.5;
            applyRole("base", Qt.hsla(Math.random(), Math.random(), baseL, 1));
            applyRole("text", Qt.hsla(Math.random(), Math.random(), isL ? rand(0, 0.2) : rand(0.8, 1), 1));
            for (const key of ["outer", "inner", "icons", "clock"])
                applyRole(key, Qt.hsla(Math.random(), Math.random(), rand(0.15, 0.85), 1));
        }
    }

    function persistPresets(): void {
        presetsFile.setText(JSON.stringify(presets, null, 4));
    }

    function savePreset(name: string): void {
        name = name.trim();
        if (!schemeData || !name)
            return;
        presets[name] = JSON.parse(JSON.stringify(schemeData));
        presetsRev++;
        persistPresets();
    }

    function loadPreset(name: string): void {
        const p = presets[name];
        if (!p)
            return;
        schemeData = JSON.parse(JSON.stringify(p));
        markDirty();
    }

    function deletePreset(name: string): void {
        delete presets[name];
        presetsRev++;
        persistPresets();
    }

    function presetSwatch(name: string, token: string): color {
        const _ = presetsRev;
        return `#${presets[name]?.colours[token] ?? "000000"}`;
    }

    function applyRole(key: string, c: color): void {
        if (!schemeData)
            return;

        const cs = schemeData.colours;
        const isL = c.hslLightness >= 0.5;

        switch (key) {
        case "base": {
            const sign = isL ? -1 : 1;
            cs.background = cs.surface = cs.neutral = hx(c);
            cs.surfaceDim = hx(shiftL(c, sign * 0.07));
            cs.surfaceBright = hx(isL ? c : shiftL(c, 0.1));
            cs.surfaceVariant = hx(shiftL(c, sign * 0.08));
            cs.inverseSurface = hx(withL(c, isL ? 0.15 : 0.9));
            cs.inverseOnSurface = hx(withL(c, isL ? 0.93 : 0.15));
            cs.term0 = hx(c);
            // Layering (tPalette) darkens/lightens based on mode, so keep it
            // in sync with the base lightness or containers go muddy.
            schemeData.mode = isL ? "light" : "dark";
            break;
        }
        case "text":
            cs.onBackground = cs.onSurface = hx(c);
            cs.onSurfaceVariant = hx(desat(shiftL(c, isL ? -0.08 : 0.08), 0.8));
            break;
        case "outer": {
            const sign = isL ? 1 : -1;
            const light = schemeData.mode === "light";
            cs.surfaceContainer = hx(c);
            cs.surfaceContainerLowest = hx(shiftL(c, sign * 0.16));
            cs.surfaceContainerLow = hx(shiftL(c, sign * 0.08));
            cs.surfaceContainerHigh = hx(shiftL(c, -sign * 0.07));
            cs.surfaceContainerHighest = hx(shiftL(c, -sign * 0.14));
            cs.outline = hx(desat(withL(c, light ? 0.45 : 0.65), 0.6));
            cs.outlineVariant = hx(desat(withL(c, light ? 0.72 : 0.35), 0.6));
            break;
        }
        case "inner":
            applyFamily("primary", c);
            cs.surfaceTint = hx(c);
            cs.inversePrimary = hx(shiftL(c, isL ? -0.25 : 0.25));
            break;
        case "icons":
            applyFamily("secondary", c);
            break;
        case "clock":
            applyFamily("tertiary", c);
            break;
        }

        markDirty();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // PageBase only takes a single content child, so non-visual
        // helpers live inside the layout like the other nexus pages do
        Timer {
            id: saveTimer

            interval: 150
            onTriggered: {
                if (root.schemeData)
                    schemeFile.setText(JSON.stringify(root.schemeData, null, 4));
            }
        }

        FileView {
            id: schemeFile

            path: `${Paths.state}/scheme.json`
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                // Unsaved local edits win over whatever just landed on disk
                if (saveTimer.running)
                    return;
                try {
                    const txt = text();
                    const parsed = JSON.parse(txt);
                    if (!root.snapshot)
                        root.snapshot = txt;
                    root.schemeData = parsed;
                    root.rev++;
                } catch (e) {
                    console.warn("[colours page] failed to parse scheme.json:", e);
                }
            }
        }

        FileView {
            id: presetsFile

            path: `${Paths.state}/colour-presets.json`
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                try {
                    root.presets = JSON.parse(text());
                    root.presetsRev++;
                } catch (e) {
                    console.warn("[colours page] failed to parse colour-presets.json:", e);
                }
            }
        }

        // The page scrolls inside PageBase's Flickable, so the wheel dialog
        // reparents itself to the window and overlays everything. Loader is
        // invisible to the layout; the loaded item lives at window level.
        Loader {
            id: wheelPopup

            property string title
            property color initial
            property var apply

            visible: false
            active: false
            onLoaded: item.parent = QsWindow.window.contentItem

            sourceComponent: MouseArea {
                id: overlay

                property real eh
                property real es
                property real el

                function push(): void {
                    wheelPopup.apply(Qt.hsla(eh, es, el, 1));
                }

                anchors.fill: parent
                focus: true
                hoverEnabled: true
                onClicked: wheelPopup.active = false
                Keys.onEscapePressed: wheelPopup.active = false

                Component.onCompleted: {
                    eh = Math.max(0, wheelPopup.initial.hslHue);
                    es = wheelPopup.initial.hslSaturation;
                    el = wheelPopup.initial.hslLightness;
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(Colours.palette.m3scrim, 0.5)
                }

                StyledRect {
                    anchors.centerIn: parent
                    implicitWidth: dialogLayout.implicitWidth + Tokens.padding.largeIncreased * 2
                    implicitHeight: dialogLayout.implicitHeight + Tokens.padding.largeIncreased * 2
                    color: Colours.palette.m3surfaceContainerHigh
                    radius: Tokens.rounding.large

                    MouseArea {
                        anchors.fill: parent
                    }

                    ColumnLayout {
                        id: dialogLayout

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.medium

                        StyledText {
                            Layout.fillWidth: true
                            text: wheelPopup.title
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        Item {
                            id: wheel

                            readonly property real r: implicitWidth / 2

                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 200
                            implicitHeight: 200

                            // Hue ring (conical) + desaturation-to-grey overlay
                            // (radial); Qt conical gradients run visually
                            // counter-clockwise from 3 o'clock, hence the
                            // atan2(-dy, dx) in the mouse mapping below.
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    strokeWidth: -1
                                    fillGradient: ConicalGradient {
                                        centerX: wheel.r
                                        centerY: wheel.r
                                        angle: 0

                                        GradientStop {
                                            position: 0
                                            color: Qt.hsla(0, 1, 0.5, 1)
                                        }
                                        GradientStop {
                                            position: 1 / 6
                                            color: Qt.hsla(1 / 6, 1, 0.5, 1)
                                        }
                                        GradientStop {
                                            position: 2 / 6
                                            color: Qt.hsla(2 / 6, 1, 0.5, 1)
                                        }
                                        GradientStop {
                                            position: 0.5
                                            color: Qt.hsla(0.5, 1, 0.5, 1)
                                        }
                                        GradientStop {
                                            position: 4 / 6
                                            color: Qt.hsla(4 / 6, 1, 0.5, 1)
                                        }
                                        GradientStop {
                                            position: 5 / 6
                                            color: Qt.hsla(5 / 6, 1, 0.5, 1)
                                        }
                                        GradientStop {
                                            position: 1
                                            color: Qt.hsla(0, 1, 0.5, 1)
                                        }
                                    }

                                    PathAngleArc {
                                        centerX: wheel.r
                                        centerY: wheel.r
                                        radiusX: wheel.r
                                        radiusY: wheel.r
                                        startAngle: 0
                                        sweepAngle: 360
                                    }
                                }

                                ShapePath {
                                    strokeWidth: -1
                                    fillGradient: RadialGradient {
                                        centerX: wheel.r
                                        centerY: wheel.r
                                        focalX: wheel.r
                                        focalY: wheel.r
                                        centerRadius: wheel.r

                                        GradientStop {
                                            position: 0
                                            color: Qt.hsla(0, 0, 0.5, 1)
                                        }
                                        GradientStop {
                                            position: 1
                                            color: Qt.hsla(0, 0, 0.5, 0)
                                        }
                                    }

                                    PathAngleArc {
                                        centerX: wheel.r
                                        centerY: wheel.r
                                        radiusX: wheel.r
                                        radiusY: wheel.r
                                        startAngle: 0
                                        sweepAngle: 360
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent

                                function grab(mx: real, my: real): void {
                                    const dx = mx - wheel.r;
                                    const dy = my - wheel.r;
                                    overlay.eh = (Math.atan2(-dy, dx) / (2 * Math.PI) + 1) % 1;
                                    overlay.es = Math.min(1, Math.hypot(dx, dy) / wheel.r);
                                    overlay.push();
                                }

                                onPressed: e => grab(e.x, e.y)
                                onPositionChanged: e => {
                                    if (pressed)
                                        grab(e.x, e.y);
                                }
                            }

                            Rectangle {
                                readonly property real ang: overlay.eh * 2 * Math.PI

                                x: wheel.r + Math.cos(ang) * overlay.es * wheel.r - width / 2
                                y: wheel.r - Math.sin(ang) * overlay.es * wheel.r - height / 2
                                width: 16
                                height: 16
                                radius: 8
                                color: Qt.hsla(overlay.eh, overlay.es, overlay.el, 1)
                                border.width: 2
                                border.color: overlay.el >= 0.5 ? "#000000" : "#ffffff"
                            }
                        }

                        HslSlider {
                            label: qsTr("Lightness")
                            display: `${Math.round(overlay.el * 100)}%`
                            value: overlay.el
                            onMoved: v => {
                                overlay.el = v;
                                overlay.push();
                            }
                        }

                        RowLayout {
                            spacing: Tokens.spacing.medium

                            StyledRect {
                                implicitWidth: implicitHeight
                                implicitHeight: Tokens.font.icon.medium.pointSize + Tokens.padding.small * 2
                                color: Qt.hsla(overlay.eh, overlay.es, overlay.el, 1)
                                radius: Tokens.rounding.full
                                border.width: 1
                                border.color: Colours.palette.m3outlineVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `#${root.hx(Qt.hsla(overlay.eh, overlay.es, overlay.el, 1))}`
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                            }

                            StyledRect {
                                implicitWidth: pickLayout.implicitWidth + Tokens.padding.medium * 2
                                implicitHeight: pickLayout.implicitHeight + Tokens.padding.small * 2
                                color: Colours.palette.m3secondaryContainer
                                radius: Tokens.rounding.full

                                StateLayer {
                                    onClicked: pickerProc.running = true
                                }

                                RowLayout {
                                    id: pickLayout

                                    anchors.centerIn: parent
                                    spacing: Tokens.spacing.small

                                    MaterialIcon {
                                        text: "colorize"
                                        color: Colours.palette.m3onSecondaryContainer
                                        fontStyle: Tokens.font.icon.small
                                    }

                                    StyledText {
                                        text: qsTr("Pick")
                                        color: Colours.palette.m3onSecondaryContainer
                                        font: Tokens.font.label.small
                                    }
                                }
                            }

                            StyledRect {
                                implicitWidth: doneLabel.implicitWidth + Tokens.padding.medium * 2
                                implicitHeight: doneLabel.implicitHeight + Tokens.padding.small * 2
                                color: Colours.palette.m3primary
                                radius: Tokens.rounding.full

                                StateLayer {
                                    onClicked: wheelPopup.active = false
                                }

                                StyledText {
                                    id: doneLabel

                                    anchors.centerIn: parent
                                    text: qsTr("Done")
                                    color: Colours.palette.m3onPrimary
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }
                }

                Process {
                    id: pickerProc

                    command: ["hyprpicker"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const m = text.trim().match(/#?([0-9a-fA-F]{6})/);
                            if (!m)
                                return;
                            const c = root.toColour(m[1]);
                            overlay.eh = Math.max(0, c.hslHue);
                            overlay.es = c.hslSaturation;
                            overlay.el = c.hslLightness;
                            overlay.push();
                        }
                    }
                }
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Generate")
        }

        ConnectedRect {
            first: true

            Layout.fillWidth: true
            implicitHeight: generateLayout.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                onClicked: root.generate()
            }

            RowLayout {
                id: generateLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "casino"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Random palette")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.harmonious ? qsTr("One hue, matching shades — keeps light/dark mode") : qsTr("Anything goes — may flip light/dark mode")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Harmonious")
            subtext: qsTr("Derive every role from a single random hue")
            checked: root.harmonious
            onToggled: root.harmonious = checked
        }

        SectionHeader {
            text: qsTr("Preview")
        }

        // Miniature bar wired to the live palette
        StyledRect {
            Layout.fillWidth: true

            implicitHeight: previewRow.implicitHeight + Tokens.padding.medium * 2
            color: Colours.palette.m3surface
            radius: Tokens.rounding.large
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            RowLayout {
                id: previewRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: wsRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: wsRow.implicitHeight + Tokens.padding.small * 2
                    color: Colours.palette.m3surfaceContainer
                    radius: Tokens.rounding.full

                    RowLayout {
                        id: wsRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        StyledRect {
                            implicitWidth: implicitHeight
                            implicitHeight: activeWs.implicitHeight + Tokens.padding.extraSmall * 2
                            color: Colours.palette.m3primary
                            radius: Tokens.rounding.full

                            StyledText {
                                id: activeWs

                                anchors.centerIn: parent
                                text: "1"
                                color: Colours.palette.m3onPrimary
                                font: Tokens.font.label.small
                            }
                        }

                        StyledText {
                            text: "2"
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StyledText {
                            text: "3"
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Sample text")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledRect {
                    implicitWidth: statusRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: statusRow.implicitHeight + Tokens.padding.small * 2
                    color: Colours.palette.m3surfaceContainer
                    radius: Tokens.rounding.full

                    RowLayout {
                        id: statusRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "wifi"
                            color: Colours.palette.m3secondary
                            fontStyle: Tokens.font.icon.small
                        }

                        MaterialIcon {
                            text: "volume_up"
                            color: Colours.palette.m3secondary
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: "12:00"
                            color: Colours.palette.m3tertiary
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Shell colours")
        }

        Repeater {
            model: root.roles

            RoleRow {}
        }

        SectionHeader {
            text: qsTr("Advanced")
        }

        ToggleRow {
            first: true
            last: !root.showAll
            text: qsTr("Edit individual colours")
            subtext: qsTr("Every scheme token, including the terminal palette")
            checked: root.showAll
            onToggled: root.showAll = checked
        }

        Repeater {
            model: root.showAll ? root.tokenKeys : []

            TokenRow {}
        }

        SectionHeader {
            text: qsTr("Presets")
        }

        ConnectedRect {
            first: true
            last: root.presetNames.length === 0

            Layout.fillWidth: true
            implicitHeight: saveLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: saveLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledTextField {
                    id: presetNameField

                    Layout.fillWidth: true
                    leadingIcon: "bookmark_add"
                    placeholderText: qsTr("Preset name")
                    supportingText: qsTr("Saves the current scheme — same name overwrites")
                    onAccepted: root.savePreset(text)
                }

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: saveIcon.implicitHeight + Tokens.padding.small * 2
                    color: presetNameField.text.trim() ? Colours.palette.m3primary : Colours.palette.m3surfaceContainer
                    radius: Tokens.rounding.full

                    StateLayer {
                        onClicked: root.savePreset(presetNameField.text)
                    }

                    MaterialIcon {
                        id: saveIcon

                        anchors.centerIn: parent
                        text: "save"
                        color: presetNameField.text.trim() ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }
                }
            }
        }

        Repeater {
            model: root.presetNames

            PresetRow {}
        }

        SectionHeader {
            text: qsTr("Manage")
        }

        ConnectedRect {
            first: true
            last: true

            Layout.fillWidth: true
            implicitHeight: revertLayout.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                onClicked: {
                    if (!root.snapshot)
                        return;
                    try {
                        root.schemeData = JSON.parse(root.snapshot);
                        root.rev++;
                        saveTimer.stop();
                        schemeFile.setText(root.snapshot);
                    } catch (e) {
                        console.warn("[colours page] failed to revert:", e);
                    }
                }
            }

            RowLayout {
                id: revertLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "undo"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Revert changes")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Restore the scheme from when this page was opened")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    component RoleRow: ConnectedRect {
        id: row

        required property var modelData
        required property int index

        property bool expanded
        property real eh
        property real es
        property real el

        function beginEdit(): void {
            const c = root.tokenColour(modelData.token);
            eh = Math.max(0, c.hslHue);
            es = c.hslSaturation;
            el = c.hslLightness;
        }

        function applyEdit(): void {
            root.applyRole(modelData.key, Qt.hsla(eh, es, el, 1));
        }

        first: index === 0
        last: index === root.roles.length - 1

        Layout.fillWidth: true
        implicitHeight: roleCol.implicitHeight + Tokens.padding.medium * 2
        clip: true

        Behavior on implicitHeight {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        ColumnLayout {
            id: roleCol

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            Item {
                Layout.fillWidth: true
                implicitHeight: roleHeader.implicitHeight

                StateLayer {
                    radius: Tokens.rounding.small
                    onClicked: {
                        row.expanded = !row.expanded;
                        if (row.expanded)
                            row.beginEdit();
                    }
                }

                RowLayout {
                    id: roleHeader

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: row.modelData.icon
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.subtext
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: Tokens.font.icon.medium.pointSize + Tokens.padding.small * 2
                        color: root.tokenColour(row.modelData.token)
                        radius: Tokens.rounding.full
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant

                        StateLayer {
                            onClicked: {
                                row.beginEdit();
                                root.openWheel(row.modelData.label, root.tokenColour(row.modelData.token), c => {
                                    row.eh = Math.max(0, c.hslHue);
                                    row.es = c.hslSaturation;
                                    row.el = c.hslLightness;
                                    row.applyEdit();
                                });
                            }
                        }
                    }

                    MaterialIcon {
                        text: "expand_more"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                        rotation: row.expanded ? 180 : 0

                        Behavior on rotation {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                active: row.expanded
                visible: active

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.medium

                    HslSlider {
                        label: qsTr("Hue")
                        display: `${Math.round(row.eh * 360)}°`
                        value: row.eh
                        onMoved: v => {
                            row.eh = v;
                            row.applyEdit();
                        }
                    }

                    HslSlider {
                        label: qsTr("Saturation")
                        display: `${Math.round(row.es * 100)}%`
                        value: row.es
                        onMoved: v => {
                            row.es = v;
                            row.applyEdit();
                        }
                    }

                    HslSlider {
                        label: qsTr("Lightness")
                        display: `${Math.round(row.el * 100)}%`
                        value: row.el
                        onMoved: v => {
                            row.el = v;
                            row.applyEdit();
                        }
                    }

                    StyledTextField {
                        Layout.fillWidth: true
                        leadingIcon: "tag"
                        placeholderText: qsTr("RRGGBB")
                        text: root.tokenHex(row.modelData.token)
                        validate: /^[0-9a-fA-F]{6}$/
                        errorText: qsTr("Must be 6 hex digits")
                        onEditingFinished: {
                            if (!valid || !text)
                                return;
                            const c = root.toColour(text);
                            row.eh = Math.max(0, c.hslHue);
                            row.es = c.hslSaturation;
                            row.el = c.hslLightness;
                            row.applyEdit();
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Container and “on” shades are derived automatically")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    component HslSlider: ColumnLayout {
        id: slider

        property alias label: sliderLabel.text
        property alias display: sliderValue.text
        property real value

        signal moved(v: real)

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                id: sliderLabel

                Layout.fillWidth: true
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                id: sliderValue

                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: Tokens.padding.medium * 2
            radius: Tokens.rounding.small
            value: slider.value
            onInteraction: v => slider.moved(v)
        }
    }

    component PresetRow: ConnectedRect {
        id: prow

        required property string modelData
        required property int index

        // Two-step delete: first click arms (icon + colour change), second
        // within 3s deletes; anywhere else on the row loads the preset.
        property bool confirmingDelete

        first: false
        last: index === root.presetNames.length - 1

        Layout.fillWidth: true
        implicitHeight: presetLayout.implicitHeight + Tokens.padding.small * 2

        StateLayer {
            onClicked: root.loadPreset(prow.modelData)
        }

        Timer {
            id: disarmTimer

            interval: 3000
            onTriggered: prow.confirmingDelete = false
        }

        RowLayout {
            id: presetLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            Row {
                spacing: -Tokens.padding.small

                Repeater {
                    model: ["surface", "primary", "secondary", "tertiary"]

                    StyledRect {
                        required property string modelData

                        implicitWidth: implicitHeight
                        implicitHeight: Tokens.font.label.small.pointSize + Tokens.padding.small * 2
                        color: root.presetSwatch(prow.modelData, modelData)
                        radius: Tokens.rounding.full
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: prow.modelData
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: deleteIcon.implicitHeight + Tokens.padding.small * 2
                color: prow.confirmingDelete ? Colours.palette.m3errorContainer : "transparent"
                radius: Tokens.rounding.full

                StateLayer {
                    onClicked: {
                        if (prow.confirmingDelete) {
                            root.deletePreset(prow.modelData);
                        } else {
                            prow.confirmingDelete = true;
                            disarmTimer.restart();
                        }
                    }
                }

                MaterialIcon {
                    id: deleteIcon

                    anchors.centerIn: parent
                    text: prow.confirmingDelete ? "delete_forever" : "delete"
                    color: prow.confirmingDelete ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }

    component TokenRow: ConnectedRect {
        id: trow

        required property string modelData
        required property int index

        first: false
        last: index === root.tokenKeys.length - 1

        Layout.fillWidth: true
        implicitHeight: tokenLayout.implicitHeight + Tokens.padding.small * 2

        RowLayout {
            id: tokenLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: Tokens.font.label.small.pointSize + Tokens.padding.small * 2
                color: root.tokenColour(trow.modelData)
                radius: Tokens.rounding.full
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                StateLayer {
                    onClicked: root.openWheel(trow.modelData, root.tokenColour(trow.modelData), c => root.setTokenHex(trow.modelData, root.hx(c)))
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: trow.modelData
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledTextField {
                Layout.preferredWidth: 140
                text: root.tokenHex(trow.modelData)
                validate: /^[0-9a-fA-F]{6}$/
                errorText: qsTr("6 hex digits")
                onEditingFinished: {
                    if (valid && text)
                        root.setTokenHex(trow.modelData, text);
                }
            }
        }
    }
}
