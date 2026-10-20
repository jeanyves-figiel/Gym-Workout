import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Glance (#550): next session and today's water, from the last snapshot.
(:glance)
class MonkeyGlance extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var snap = Application.Storage.getValue("snap") as Dictionary?;
        var title = "MonkeyWorkout";
        var line = "Pair in the iPhone app";
        if (snap != null) {
            var next = snap["next"] as Dictionary?;
            title = next == null ? "Week done" : (next["t"] as String);
            var water = snap["water"] as Dictionary?;
            line = next == null ? "" : (next["d"] as String) + " - " + (next["m"] as Number).toString() + " min";
            if (water != null) {
                line = line + (line.length() > 0 ? " - " : "") + "water " + (water["g"] as Number).toString() + "/" + (water["t"] as Number).toString();
            }
        }
        var h = dc.getHeight();
        dc.setColor(0x8A8CFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.3, Graphics.FONT_GLANCE, title.toUpper(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.72, Graphics.FONT_GLANCE, line, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
