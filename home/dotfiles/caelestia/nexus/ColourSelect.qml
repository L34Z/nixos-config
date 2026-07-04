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

    readonly property var tokenKeys: schemeData ? Object.keys(schemeData.colours) : []

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

        SectionHeader {
            first: true
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
