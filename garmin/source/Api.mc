import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.WatchUi;

// Server calls (#550): pairing, the snapshot the phone published, and the queue of events for the phone.
// Events wait in Storage until the server has them, so nothing is lost without a phone nearby.
class Api {
    hidden var _sending as Array<Dictionary> = [];
    hidden var _fetching as Boolean = false;
    var offline as Boolean = false;

    function initialize() {}

    static function token() as String? {
        return Application.Storage.getValue("token") as String?;
    }

    static function snapshot() as Dictionary? {
        return Application.Storage.getValue("snap") as Dictionary?;
    }

    static function code() as String? {
        return Application.Storage.getValue("code") as String?;
    }

    hidden function options(method as Communications.HttpRequestMethod) as Dictionary {
        var headers = {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON};
        var t = token();
        if (t != null) {
            headers["X-Garmin-Token"] = t;
        }
        return {
            :method => method,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // Snapshot when paired, a pairing code otherwise; then sends what waits in the queue.
    function refresh() as Void {
        if (_fetching) {
            return;
        }
        _fetching = true;
        if (token() == null) {
            Communications.makeWebRequest(Config.API + "/garmin/pair", {}, options(Communications.HTTP_REQUEST_METHOD_POST), method(:onPair));
        } else {
            Communications.makeWebRequest(Config.API + "/garmin/snapshot", null, options(Communications.HTTP_REQUEST_METHOD_GET), method(:onSnapshot));
        }
    }

    function onPair(status as Number, data as Dictionary or String or Null) as Void {
        _fetching = false;
        offline = status != 200;
        if (status == 200 && data instanceof Dictionary) {
            Application.Storage.setValue("token", data["token"]);
            Application.Storage.setValue("code", data["code"]);
        }
        WatchUi.requestUpdate();
    }

    function onSnapshot(status as Number, data as Dictionary or String or Null) as Void {
        _fetching = false;
        offline = status != 200 && status != 401;
        if (status == 401) {
            // Removed in the app (or the account is gone): pair again.
            Application.Storage.deleteValue("token");
            Application.Storage.deleteValue("snap");
            Application.Storage.deleteValue("code");
            refresh();
            return;
        }
        if (status == 200 && data instanceof Dictionary) {
            if (data["paired"] == true) {
                Application.Storage.deleteValue("code");
                var snap = data["snapshot"];
                if (snap instanceof Dictionary) {
                    Application.Storage.setValue("snap", snap);
                }
                flush();
            } else {
                Application.Storage.setValue("code", data["code"]);
            }
        }
        WatchUi.requestUpdate();
    }

    // MARK: Events for the phone

    static function eventId() as String {
        return Time.now().value().toString() + "-" + (Math.rand() % 1000000).toString();
    }

    function send(event as Dictionary) as Void {
        event["id"] = eventId();
        var queue = Application.Storage.getValue("queue") as Array?;
        if (queue == null) {
            queue = [];
        }
        queue.add(event);
        // Without a phone for a long time: keep the newest.
        if (queue.size() > 150) {
            queue = queue.slice(queue.size() - 150, null);
        }
        Application.Storage.setValue("queue", queue);
        flush();
    }

    function flush() as Void {
        if (_sending.size() > 0 || token() == null) {
            return;
        }
        var queue = Application.Storage.getValue("queue") as Array?;
        if (queue == null || queue.size() == 0) {
            return;
        }
        _sending = queue.slice(0, queue.size() < 20 ? queue.size() : 20) as Array<Dictionary>;
        Communications.makeWebRequest(Config.API + "/garmin/events", {"events" => _sending},
            options(Communications.HTTP_REQUEST_METHOD_POST), method(:onSent));
    }

    function onSent(status as Number, data as Dictionary or String or Null) as Void {
        var sent = _sending;
        _sending = [];
        offline = status != 200;
        if (status != 200) {
            return;
        }
        var queue = Application.Storage.getValue("queue") as Array?;
        if (queue == null) {
            return;
        }
        var left = [];
        for (var i = 0; i < queue.size(); i++) {
            var keep = true;
            for (var j = 0; j < sent.size(); j++) {
                if ((queue[i] as Dictionary)["id"].equals(sent[j]["id"])) {
                    keep = false;
                    break;
                }
            }
            if (keep) {
                left.add(queue[i]);
            }
        }
        Application.Storage.setValue("queue", left);
        if (left.size() > 0) {
            flush();
        }
    }

    // Water +1 (#496): counted on the phone's day, shown at once here.
    function addWater() as Void {
        var snap = snapshot();
        var day = null;
        if (snap != null && snap["water"] instanceof Dictionary) {
            var water = snap["water"] as Dictionary;
            water["g"] = (water["g"] as Number) + 1;
            day = water["d"];
            Application.Storage.setValue("snap", snap);
        }
        var event = {"type" => "water"};
        if (day != null) {
            event["day"] = day;
        }
        send(event);
        WatchUi.requestUpdate();
    }

    function unpair() as Void {
        Application.Storage.clearValues();
        refresh();
    }
}
