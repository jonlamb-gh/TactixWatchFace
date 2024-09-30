import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Time;

const INTEGER_FORMAT = "%d";

typedef FormattedTime as {
    :hour as String,
    :min as String,
    :sec as String,
    :amPm as String
};

class TactixWatchFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        // Do nothing
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        // Do nothing
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new TactixWatchFaceView() ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

}

function getApp() as TactixWatchFaceApp {
    return Application.getApp() as TactixWatchFaceApp;
}

// Return a formatted time dictionary that respects is24Hour settings.
// - hour: 0-23.
// - min:  0-59.
// - sec:  0-59.
function getFormattedTime(hour as Numeric, min as Numeric, sec as Numeric, hideHoursLeadingZero as Boolean) as FormattedTime {
    var amPm = "";

    if (!System.getDeviceSettings().is24Hour) {
        // Ensure noon is shown as PM.
        var isPm = (hour >= 12);
        if (isPm) {
            // But ensure noon is shown as 12, not 00.
            if (hour > 12) {
                hour = hour - 12;
            }
            amPm = "p";
        } else {
            // Ensure midnight is shown as 12, not 00.
            if (hour == 0) {
                hour = 12;
            }
            amPm = "a";
        }
    }

    hour = hour.format(hideHoursLeadingZero ? INTEGER_FORMAT : "%02d");

    return {
        :hour => hour,
        :min => min.format("%02d"),
        :sec => sec.format("%02d"),
        :amPm => amPm
    };
}
