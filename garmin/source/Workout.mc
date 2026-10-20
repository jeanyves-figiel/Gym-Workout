import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.Time;

// One session played on the watch (#550): walks its exercises set by set, records a Garmin strength activity
// (heart rate, calories, a lap per set) and sends each set and the finish to the phone.
class Workout {
    var session as Dictionary;
    var items as Array<Dictionary>;
    var index as Number = 0;
    var setIndex as Number = 0;
    var kg as Float = 0.0;
    var reps as Number = 0;
    var setsDone as Dictionary = {};
    var restEnd as Number? = null;
    var editingKg as Boolean = false;
    hidden var _start as Number;
    hidden var _recording as ActivityRecording.Session? = null;
    hidden var _ended as Boolean = false;

    function initialize(s as Dictionary) {
        session = s;
        items = s["items"] as Array<Dictionary>;
        _start = Time.now().value();
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        if (Toybox has :ActivityRecording) {
            _recording = ActivityRecording.createSession({
                :name => "MonkeyWorkout",
                :sport => ActivityRecording.SPORT_TRAINING,
                :subSport => ActivityRecording.SUB_SPORT_STRENGTH_TRAINING
            });
            _recording.start();
        }
        load();
    }

    function item() as Dictionary? {
        return index < items.size() ? items[index] : null;
    }

    function done() as Boolean {
        return index >= items.size();
    }

    function sets() as Number {
        var it = item();
        return it == null ? 0 : it["s"] as Number;
    }

    function loggable() as Boolean {
        var it = item();
        return it != null && it["l"] == true;
    }

    function timedSec() as Number? {
        var it = item();
        return it == null ? null : it["ts"] as Number?;
    }

    // Suggested load and reps for the current exercise.
    hidden function load() as Void {
        var it = item();
        if (it == null) {
            return;
        }
        var k = it["kg"];
        kg = k == null ? 0.0 : (k as Numeric).toFloat();
        var tr = it["tr"];
        reps = tr == null ? 10 : tr as Number;
        editingKg = false;
    }

    function step() as Float {
        var it = item();
        var s = it == null ? null : it["st"];
        return s == null ? 2.5 : (s as Numeric).toFloat();
    }

    function adjust(up as Boolean) as Void {
        if (editingKg) {
            kg = kg + (up ? step() : -step());
            if (kg < 0) {
                kg = 0.0;
            }
        } else {
            reps = reps + (up ? 1 : -1);
            if (reps < 0) {
                reps = 0;
            }
        }
    }

    // The set is done: logged for the phone, a lap on the activity, then rest or the next exercise.
    function logSet() as Void {
        var it = item();
        if (it == null) {
            return;
        }
        var uid = it["u"] as String;
        if (loggable()) {
            api().send({"type" => "set", "sid" => session["id"], "ex" => it["e"], "i" => setIndex, "kg" => kg, "reps" => reps});
        }
        setsDone[uid] = setIndex + 1;
        if (_recording != null) {
            _recording.addLap();
        }
        var rest = it["rest"] == null ? 0 : it["rest"] as Number;
        if (setIndex + 1 < sets()) {
            setIndex++;
            restEnd = rest > 0 ? Time.now().value() + rest : null;
        } else {
            api().send({"type" => "done", "uid" => uid});
            next();
            restEnd = rest > 0 && !done() ? Time.now().value() + rest : null;
        }
    }

    function next() as Void {
        index++;
        setIndex = 0;
        load();
    }

    function restLeft() as Number {
        return restEnd == null ? 0 : (restEnd as Number) - Time.now().value();
    }

    function addRest(seconds as Number) as Void {
        if (restEnd != null) {
            restEnd = (restEnd as Number) + seconds;
        }
    }

    function heartRate() as Number? {
        var info = Activity.getActivityInfo();
        return info == null ? null : info.currentHeartRate;
    }

    // Saves the Garmin activity (Garmin Connect adds it to Apple Health) and tells the phone what was done.
    function finish() as Void {
        if (_ended) {
            return;
        }
        _ended = true;
        var info = Activity.getActivityInfo();
        var event = {"type" => "finished", "sid" => session["id"], "title" => session["t"], "start" => _start,
                     "end" => Time.now().value(), "sets" => setsDone};
        if (info != null) {
            if (info.averageHeartRate != null) { event["hr"] = info.averageHeartRate; }
            if (info.maxHeartRate != null) { event["hrMax"] = info.maxHeartRate; }
            if (info.calories != null) { event["kcal"] = info.calories; }
        }
        if (_recording != null) {
            _recording.stop();
            _recording.save();
            _recording = null;
        }
        Sensor.setEnabledSensors([]);
        if (setsDone.size() > 0) {
            api().send(event);
        }
        getApp().workout = null;
    }

    // Nothing kept: no activity, nothing sent at the end (sets already sent stay on the phone's day).
    function discard() as Void {
        _ended = true;
        if (_recording != null) {
            _recording.stop();
            _recording.discard();
            _recording = null;
        }
        Sensor.setEnabledSensors([]);
        getApp().workout = null;
    }
}

function buzz() as Void {
    if (Attention has :vibrate) {
        Attention.vibrate([new Attention.VibeProfile(80, 500)]);
    }
}
