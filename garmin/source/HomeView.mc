import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Home (#550, design B): next session as a data screen. Pairing code until the watch is paired.
class HomeView extends WatchUi.View {
    hidden var _timer as Timer.Timer = new Timer.Timer();

    function initialize() {
        View.initialize();
    }

    // Checks every 5 s while the code shows, so the watch moves on as soon as the phone pairs it.
    function onShow() as Void {
        api().refresh();
        _timer.start(method(:onTick), 5000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        if (Api.token() == null || Api.code() != null || Api.snapshot() == null) {
            api().refresh();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        Style.clear(dc);
        var h = dc.getHeight();
        if (Api.token() == null || Api.code() != null) {
            drawPairing(dc, h);
            return;
        }
        var snap = Api.snapshot();
        if (snap == null) {
            Style.text(dc, h * 0.4, Graphics.FONT_SMALL, "Open MonkeyWorkout", Graphics.COLOR_WHITE);
            Style.text(dc, h * 0.52, Graphics.FONT_SMALL, "on your iPhone", Graphics.COLOR_WHITE);
            Style.text(dc, h * 0.66, Graphics.FONT_XTINY, api().offline ? "NO CONNECTION" : "SYNCING...", Style.MUTED);
            return;
        }
        var next = snap["next"] as Dictionary?;
        if (next == null) {
            Style.text(dc, h * 0.24, Graphics.FONT_XTINY, "THIS WEEK", Style.MUTED);
            Style.text(dc, h * 0.36, Graphics.FONT_MEDIUM, "ALL DONE", Style.LIME);
            Style.rule(dc, h * 0.47);
        } else {
            Style.text(dc, h * 0.2, Graphics.FONT_XTINY, (next["d"] as String).toUpper(), Style.MUTED);
            Style.text(dc, h * 0.32, Graphics.FONT_MEDIUM, (next["t"] as String).toUpper(), Style.TITLE);
            Style.rule(dc, h * 0.43);
            Style.text(dc, h * 0.5, Graphics.FONT_XTINY, "EXERCISES - TIME", Style.MUTED);
            Style.text(dc, h * 0.6, Graphics.FONT_MEDIUM,
                (next["items"] as Array).size().toString() + " - " + (next["m"] as Number).toString() + " MIN", Graphics.COLOR_WHITE);
            if (snap["pro"] == false) {
                Style.text(dc, h * 0.74, Graphics.FONT_XTINY, "PRO ON IPHONE", Style.HEART);
            } else {
                Style.pill(dc, h * 0.74, "START", Style.ACCENT, Graphics.COLOR_WHITE);
            }
        }
        var water = snap["water"] as Dictionary?;
        if (water != null) {
            Style.text(dc, h * 0.88, Graphics.FONT_XTINY,
                "WATER " + (water["g"] as Number).toString() + "/" + (water["t"] as Number).toString(), 0x4AB0F0);
        }
    }

    hidden function drawPairing(dc as Graphics.Dc, h as Number) as Void {
        Style.text(dc, h * 0.2, Graphics.FONT_XTINY, "PAIR WITH IPHONE", Style.MUTED);
        var code = Api.code();
        Style.text(dc, h * 0.4, Graphics.FONT_LARGE, code == null ? "..." : code, Style.TITLE);
        Style.rule(dc, h * 0.53);
        Style.text(dc, h * 0.63, Graphics.FONT_XTINY, "iPhone: Settings >", Graphics.COLOR_WHITE);
        Style.text(dc, h * 0.71, Graphics.FONT_XTINY, "Garmin watch", Graphics.COLOR_WHITE);
        Style.text(dc, h * 0.84, Graphics.FONT_XTINY, api().offline ? "NO CONNECTION" : "WAITING", Style.MUTED);
    }
}

class HomeDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var snap = Api.snapshot();
        if (Api.token() == null || Api.code() != null || snap == null) {
            api().refresh();
            return true;
        }
        var next = snap["next"] as Dictionary?;
        if (next == null || snap["pro"] == false || (next["items"] as Array).size() == 0) {
            return true;
        }
        var app = getApp();
        if (app.workout == null) {
            app.workout = new Workout(next);
        }
        WatchUi.pushView(new WorkoutView(), new WorkoutDelegate(), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({:title => "MonkeyWorkout"});
        menu.addItem(new WatchUi.MenuItem("Water +1", null, :water, null));
        menu.addItem(new WatchUi.MenuItem("Refresh", null, :refresh, null));
        menu.addItem(new WatchUi.MenuItem("Unpair", null, :unpair, null));
        WatchUi.pushView(menu, new HomeMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

class HomeMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :water) {
            api().addWater();
        } else if (id == :refresh) {
            api().refresh();
        } else if (id == :unpair) {
            api().unpair();
        }
    }
}
