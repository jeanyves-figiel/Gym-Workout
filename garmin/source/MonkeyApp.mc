import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// MonkeyWorkout for Garmin (#550). No phone link of its own: everything goes through our server, which the watch
// reaches over the Garmin Connect app. The iPhone app publishes what to show and picks up what the watch logs.
(:glance)
class MonkeyApp extends Application.AppBase {
    var api as Api?;
    var workout as Workout?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        api = new Api();
        api.refresh();
        return [new HomeView(), new HomeDelegate()];
    }

    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new MonkeyGlance()];
    }

    function onStop(state as Dictionary?) as Void {
        // Leaving mid-workout keeps the activity: Garmin saves what was recorded.
        if (workout != null) {
            workout.finish();
        }
    }
}

(:glance)
function getApp() as MonkeyApp {
    return Application.getApp() as MonkeyApp;
}

function api() as Api {
    return getApp().api as Api;
}
