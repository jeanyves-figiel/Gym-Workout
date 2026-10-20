import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Set screen (#550, design B): exercise, set count, kg × reps, heart rate. Up/Down change reps (or kg), Start logs
// the set; rest takes the whole screen with its ring around the bezel.
class WorkoutView extends WatchUi.View {
    hidden var _timer as Timer.Timer = new Timer.Timer();
    hidden var _wasResting as Boolean = false;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        var w = getApp().workout;
        if (w != null) {
            var resting = w.restLeft() > 0;
            if (_wasResting && !resting) {
                buzz();
                w.restEnd = null;
            }
            _wasResting = resting;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        Style.clear(dc);
        var w = getApp().workout;
        if (w == null) {
            return;
        }
        if (w.done()) {
            drawDone(dc, w);
        } else if (w.restLeft() > 0) {
            drawRest(dc, w);
        } else {
            drawSet(dc, w);
        }
    }

    hidden function drawSet(dc as Graphics.Dc, w as Workout) as Void {
        var h = dc.getHeight();
        var it = w.item() as Dictionary;
        Style.text(dc, h * 0.18, Graphics.FONT_XTINY,
            "SET " + (w.setIndex + 1).toString() + "/" + w.sets().toString() + "  EX " + (w.index + 1).toString() + "/" + w.items.size().toString(),
            Style.MUTED);
        Style.text(dc, h * 0.29, Graphics.FONT_SMALL, (it["n"] as String).toUpper(), it["c"] == null ? Style.TITLE : it["c"] as Number);
        Style.rule(dc, h * 0.38);
        var timed = w.timedSec();
        if (w.loggable()) {
            var kgColor = w.editingKg ? Style.LIME : Graphics.COLOR_WHITE;
            var repsColor = w.editingKg ? Graphics.COLOR_WHITE : Style.LIME;
            Style.text(dc, h * 0.47, Graphics.FONT_XTINY, w.editingKg ? "KG  UP/DOWN" : "REPS  UP/DOWN", Style.MUTED);
            var cx = dc.getWidth() / 2;
            // Number fonts have digits only: the "x" between them uses a text font.
            dc.setColor(kgColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 12, h * 0.59, Graphics.FONT_NUMBER_MEDIUM, Style.kg(w.kg), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Style.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.6, Graphics.FONT_SMALL, "x", Style.CENTER);
            dc.setColor(repsColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 12, h * 0.59, Graphics.FONT_NUMBER_MEDIUM, w.reps.toString(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (timed != null) {
            Style.text(dc, h * 0.47, Graphics.FONT_XTINY, "WORK", Style.MUTED);
            Style.text(dc, h * 0.59, Graphics.FONT_NUMBER_MEDIUM, Style.clock(timed as Number), Graphics.COLOR_WHITE);
        } else {
            Style.text(dc, h * 0.47, Graphics.FONT_XTINY, "REPS", Style.MUTED);
            Style.text(dc, h * 0.59, Graphics.FONT_MEDIUM, it["r"] as String, Graphics.COLOR_WHITE);
        }
        var hr = w.heartRate();
        Style.text(dc, h * 0.72, Graphics.FONT_XTINY, hr == null ? "HR --" : "HR " + hr.toString(), Style.HEART);
        Style.pill(dc, h * 0.84, "LOG SET", Style.ACCENT, Graphics.COLOR_WHITE);
    }

    // Rest (design B): green ring draining around the bezel, time left, the next set.
    hidden function drawRest(dc as Graphics.Dc, w as Workout) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var it = w.item() as Dictionary;
        var left = w.restLeft();
        var total = it["rest"] == null ? 60 : it["rest"] as Number;
        if (total < left) {
            total = left;
        }
        var frac = total > 0 ? left.toFloat() / total : 0.0;
        dc.setPenWidth(h / 26);
        dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, h / 2, h / 2 - h / 52);
        if (frac > 0) {
            dc.setColor(Style.REST, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, h / 2, h / 2 - h / 52, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * frac).toNumber());
        }
        dc.setPenWidth(1);
        Style.text(dc, h * 0.24, Graphics.FONT_XTINY, "REST", Style.MUTED);
        Style.text(dc, h * 0.38, Graphics.FONT_NUMBER_HOT, Style.clock(left), Style.REST);
        Style.rule(dc, h * 0.52);
        Style.text(dc, h * 0.6, Graphics.FONT_XTINY,
            "NEXT - SET " + (w.setIndex + 1).toString() + "/" + w.sets().toString(), Style.MUTED);
        var line = w.loggable() ? Style.kg(w.kg) + " kg x " + w.reps.toString() : (it["n"] as String);
        Style.text(dc, h * 0.7, Graphics.FONT_SMALL, line, Graphics.COLOR_WHITE);
        var hr = w.heartRate();
        Style.text(dc, h * 0.82, Graphics.FONT_XTINY, (hr == null ? "HR --" : "HR " + hr.toString()) + "  +15s UP", Style.HEART);
    }

    hidden function drawDone(dc as Graphics.Dc, w as Workout) as Void {
        var h = dc.getHeight();
        Style.text(dc, h * 0.3, Graphics.FONT_XTINY, "WORKOUT", Style.MUTED);
        Style.text(dc, h * 0.42, Graphics.FONT_MEDIUM, "DONE", Style.LIME);
        Style.rule(dc, h * 0.53);
        Style.text(dc, h * 0.62, Graphics.FONT_XTINY, (w.session["t"] as String).toUpper(), Graphics.COLOR_WHITE);
        Style.pill(dc, h * 0.78, "SAVE", Style.ACCENT, Graphics.COLOR_WHITE);
    }
}

class WorkoutDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    hidden function workout() as Workout? {
        return getApp().workout;
    }

    function onSelect() as Boolean {
        var w = workout();
        if (w == null) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        if (w.done()) {
            w.finish();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (w.restLeft() > 0) {
            // Skip rest.
            w.restEnd = null;
        } else {
            w.logSet();
            buzz();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        var w = workout();
        if (w != null) {
            if (w.restLeft() > 0) {
                w.addRest(15);
            } else {
                w.adjust(true);
            }
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onNextPage() as Boolean {
        var w = workout();
        if (w != null && w.restLeft() <= 0) {
            w.adjust(false);
            WatchUi.requestUpdate();
        }
        return true;
    }

    // Back and Menu open the workout menu: nothing ends by accident.
    function onBack() as Boolean {
        return onMenu();
    }

    function onMenu() as Boolean {
        var w = workout();
        if (w == null) {
            return false;
        }
        var menu = new WatchUi.Menu2({:title => "Workout"});
        if (w.loggable()) {
            menu.addItem(new WatchUi.MenuItem(w.editingKg ? "Change reps" : "Change kg", null, :toggle, null));
        }
        menu.addItem(new WatchUi.MenuItem("Next exercise", null, :skip, null));
        menu.addItem(new WatchUi.MenuItem("Finish & save", null, :finish, null));
        menu.addItem(new WatchUi.MenuItem("Discard", "Nothing saved", :discard, null));
        WatchUi.pushView(menu, new WorkoutMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

class WorkoutMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var w = getApp().workout;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (w == null) {
            return;
        }
        if (id == :toggle) {
            w.editingKg = !w.editingKg;
        } else if (id == :skip) {
            w.restEnd = null;
            w.next();
        } else if (id == :finish) {
            w.finish();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (id == :discard) {
            w.discard();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        WatchUi.requestUpdate();
    }
}
