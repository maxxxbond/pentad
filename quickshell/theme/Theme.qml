pragma Singleton
import QtQuick
import QtQml
import "../logic/theme.mjs" as ThemeLogic

QtObject {
    id: root

    property var config: ({
        appearance: "dark",
        accent: "#869677",
        fontFamily: "Geist",
        reducedMotion: false
    })
    readonly property var tokens: ThemeLogic.resolveTheme(config)

    function resolve(config) {
        ThemeLogic.resolveTheme(config)
        root.config = config
    }
}
