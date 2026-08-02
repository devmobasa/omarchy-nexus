import "../model/NexusAgendaModel.js" as NexusAgendaModel
import "../model/NexusMediaModel.js" as NexusMediaModel
import "../model/NexusMetricsModel.js" as NexusMetricsModel
import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: hero

    required property var nexus

    width: parent.width
    spacing: Style.spacing.md

    Row {
        width: parent.width
        spacing: Style.spacing.md

        Column {
            width: parent.width - (heroArt.visible ? heroArt.width + Style.spacing.md : 0)
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: Qt.formatTime(nexus.now, "HH:mm")
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge
                font.bold: true
            }

            Text {
                text: Qt.formatDate(nexus.now, "dddd, MMMM d")
                color: Qt.darker(Color.menu.text, 1.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }

            Text {
                visible: nexus.settings.showNextEvent && nexus.nextEvent !== null
                width: parent.width
                text: "󰃭 " + NexusAgendaModel.countdownLabel(nexus.nextEvent, nexus.now.getTime())
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight

                MouseArea {
                    anchors.fill: parent
                    onClicked: nexus.summonSibling("community.calendar-agenda")
                }

            }

            Text {
                visible: text.length > 0
                text: nexus.workspaceLabel
                color: Qt.darker(Color.menu.text, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }

        }

        Rectangle {
            id: heroArt

            visible: nexus.settings.showMedia
            width: Style.space(72)
            height: Style.space(72)
            radius: Style.cornerRadius
            anchors.verticalCenter: parent.verticalCenter
            color: nexus.softText(0.06)
            clip: true
            // Restrained accent glow while something is playing.
            border.width: 1
            border.color: nexus.mediaSelected && nexus.mediaSelected.isPlaying ? nexus.softAccent(0.65) : nexus.softText(0.1)

            Image {
                id: artwork

                anchors.fill: parent
                anchors.margins: 1
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: Style.space(144)
                sourceSize.height: Style.space(144)
                source: nexus.mediaSelected ? NexusMediaModel.allowedArtUrl(nexus.mediaSelected.trackArtUrl || "") : ""
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: !artwork.visible
                text: "󰝚"
                color: Qt.darker(Color.menu.text, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
            }

        }

    }

    Text {
        width: parent.width
        visible: nexus.settings.showFetch && text.length > 0
        text: NexusMetricsModel.fetchLine(nexus.hostName, nexus.kernelVersion, nexus.uptimeSeconds)
        color: Qt.darker(Color.menu.text, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
    }

}
