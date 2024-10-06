import Toybox.Math;
import Toybox.WatchUi;
import Toybox.Position;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.Complications;

enum FieldType {
    FIELD_TYPE_NOTIFICATIONS = 0,
    FIELD_TYPE_NEXT_CALENDAR_EVENT,
    FIELD_TYPE_BATTERY,
    FIELD_TYPE_HEART_RATE,
    FIELD_TYPE_WEATHER,
    FIELD_TYPE_HIGH_LOW_TEMPERATURE,
    FIELD_TYPE_SUNRISE_SUNSET,
    FIELD_TYPE_DAY,
    FIELD_TYPE_DOW,
    FIELD_TYPE_MONTH,
    FIELD_TYPE_BODY_BATTERY,
    FIELD_TYPE_CONNECTION_STATUS,
}

typedef FieldValue as {
    :value as String,
    :icon as String,
    :iconIsLabel as Boolean, // The icon field is just normal text
    :valueIsIcon as Boolean, // The value is an icon
    :usesWeatherIcons as Boolean, // :icon uses the weather icons
};

class FieldValues {
    private var complicationsData as Dictionary<Complications.Type, ComplicationData>;

    private var dayOfWeek as Number or Null = null;
    private var dayOfWeekString as String = "";

    private var month as Number or Null = null;
    private var monthString as String = "";

    private var sunriseTodayNotReached as Boolean = false;

    public var lastKnownPosition as Position.Location or Null = null;

    typedef ComplicationData as {
        :compId as Complications.Id,
        :latestValue as Complications.Value or Null,
    };

    typedef CalendarEventTime as {
        :hour24 as Number,
        :min as Number,
    };

    function initialize(types as Array<FieldType>) {
        // Some types require using the complications pub/sub APIs
        var usesComplications = false;
        complicationsData = {} as Dictionary<Complications.Type, ComplicationData>;
        for(var i = 0; i < types.size(); i += 1) {
            switch (types[i]) {
                case FIELD_TYPE_NEXT_CALENDAR_EVENT: {
                    usesComplications = true;
                    addComplicationData(Complications.COMPLICATION_TYPE_CALENDAR_EVENTS);
                    break;
                }

                case FIELD_TYPE_BODY_BATTERY: {
                    usesComplications = true;
                    addComplicationData(Complications.COMPLICATION_TYPE_BODY_BATTERY);
                    break;
                }
            }
        }
        if(usesComplications) {
            Complications.registerComplicationChangeCallback(self.method(:onComplicationChanged));
        }
    }

    private function addComplicationData(type as Complications.Type) as Void {
        var compId = new Complications.Id(type);
        var didSubscribe = Complications.subscribeToUpdates(compId);
        Test.assertMessage(didSubscribe, Lang.format("Failed to subscribe to complication  $1$", [type]));
        complicationsData.put(type, { :compId => compId, :latestValue => null });
    }

    public function onComplicationChanged(id as Complications.Id) as Void {
        var type = id.getType();
        Test.assert(type != null);

        var dataField = complicationsData[type];
        if(dataField != null) {
            var comp = Complications.getComplication(id);
            dataField[:latestValue] = comp.value;
        }
    }

    public function getValue(now as Gregorian.Info, settings as System.DeviceSettings, type as FieldType) as FieldValue {
        var rezStrings = Rez.Strings;
        var fieldValue = {
            :value => "--",
            :icon => "",
            :iconIsLabel => false,
            :valueIsIcon => false,
            :usesWeatherIcons => false,
        };

        switch (type) {
            case FIELD_TYPE_NOTIFICATIONS: {
                fieldValue[:icon] = "h";
                if(settings.connectionAvailable == true) {
                    fieldValue[:value] = settings.notificationCount.format(INTEGER_FORMAT);
                }
                break;
            }

            case FIELD_TYPE_NEXT_CALENDAR_EVENT: {
                fieldValue[:icon] = "j";
                var time = complicationsData[Complications.COMPLICATION_TYPE_CALENDAR_EVENTS];
                if((time != null) && (time[:latestValue] != null)) {
                    // TODO - cache some state, don't do this when we don't have to
                    // can be once a minute
                    var calTime = convertCalendarEventComplicationTime(settings.is24Hour, time[:latestValue] as String);
                    if(calTime != null) {
                        var calSeconds = (calTime[:hour24] as Number * Gregorian.SECONDS_PER_HOUR)
                            + (calTime[:min] as Number * Gregorian.SECONDS_PER_MINUTE);
                        var nowSeconds = (now.hour * Gregorian.SECONDS_PER_HOUR)
                            + (now.min * Gregorian.SECONDS_PER_MINUTE);

                        // Don't show the event if it's for tomorrow
                        // TODO - need to check if this is how it works on device
                        if(nowSeconds <= calSeconds) {
                            // TODO use global format time
                            fieldValue[:value] = time[:latestValue] as String;
                        }
                    }
                }
                break;
            }

            case FIELD_TYPE_BATTERY: {
                fieldValue[:icon] = "g";
                var sample = Math.floor(System.getSystemStats().battery);
                fieldValue[:value] = sample.format(INTEGER_FORMAT) + "%";
                break;
            }

            case FIELD_TYPE_HEART_RATE: {
                fieldValue[:icon] = "i";
                var info = Activity.getActivityInfo();
                var sample = info != null ? info.currentHeartRate : null;
                if(sample == null) {
                    var historicalHr = ActivityMonitor.getHeartRateHistory(1, true /* newest */).next();
                    if((historicalHr != null) && (historicalHr.heartRate != ActivityMonitor.INVALID_HR_SAMPLE)) {
                        sample = historicalHr.heartRate as Number;
                    }
                }
                if(sample != null) {
                    fieldValue[:value] = sample.format(INTEGER_FORMAT);
                }
                break;
            }

            case FIELD_TYPE_WEATHER: {
                fieldValue[:icon] = "gps?";
                fieldValue[:iconIsLabel] = true;

                var weather = Weather.getCurrentConditions();

                if((weather != null) && (weather.temperature != null)) {
                    var temp = weather.temperature as Numeric; // Celcius
                    if (settings.temperatureUnits == System.UNIT_STATUTE) {
                        temp = celciusToFarenheit(temp);
                    }
                    fieldValue[:value] = temp.format(INTEGER_FORMAT) + "°";
                }

                // If it's night time, then just show the night time icon
                // until sunrise (or we don't have sunrise time)
                if(sunriseTodayNotReached == true) {
                    fieldValue[:icon] = "d";
                    fieldValue[:iconIsLabel] = false;
                    fieldValue[:usesWeatherIcons] = true;
                } else if((weather != null) && (weather.condition != null)) {
                    fieldValue[:icon] = getWeatherIcon(weather.condition as Number);
                    fieldValue[:iconIsLabel] = false;
                    fieldValue[:usesWeatherIcons] = true;
                }

                break;
            }

            case FIELD_TYPE_HIGH_LOW_TEMPERATURE: {
                fieldValue[:icon] = "k";
                var weather = Weather.getCurrentConditions();
                if(weather != null) {
                    if((weather.lowTemperature != null) && (weather.highTemperature != null)) {
                        var low = weather.lowTemperature as Numeric;
                        var high = weather.highTemperature as Numeric;
                        if (settings.temperatureUnits == System.UNIT_STATUTE) {
                            low = celciusToFarenheit(low);
                            high = celciusToFarenheit(high);
                        }
                        low = Math.floor(low).format(INTEGER_FORMAT);
                        high = Math.floor(high).format(INTEGER_FORMAT);
                        fieldValue[:value] = low + "/" + high;
                    }
                }
                break;
            }

            case FIELD_TYPE_SUNRISE_SUNSET: {
                fieldValue[:icon] = "gps?";
                fieldValue[:iconIsLabel] = true;
                sunriseTodayNotReached = false;

                // Update last known position
                var pos = Position.getInfo();
                if((pos.position != null) && (pos.accuracy != Position.QUALITY_NOT_AVAILABLE)) {
                    lastKnownPosition = pos.position;
                }

                if(lastKnownPosition != null) {
                    // Borrowed from crystal-face:
                    // Add a minute, so that if sun rises at
                    // 07:38:17, then 07:38 is already consided daytime (seconds not shown to user).
                    var time = Time.now().add(new Time.Duration(1));

                    // Get today's sunrise/sunset times
                    var sunrise = Weather.getSunrise(lastKnownPosition as Position.Location, time);
                    var sunset = Weather.getSunset(lastKnownPosition as Position.Location, time);

                    var nextSunEvent = {
                        :time => null,
                        :isSunrise => true,
                    };
                    if((sunrise != null) && (sunset != null)) {
                        if(time.greaterThan(sunset) == true) {
                            // After today's sunset, tomorrows sunrise is next
                            var sameTimeTomorrow = time.add(new Time.Duration(24 * 60 * 60));
                            nextSunEvent[:time] = Weather.getSunrise(lastKnownPosition as Position.Location, sameTimeTomorrow);
                            nextSunEvent[:isSunrise] = true;
                        } else if(time.greaterThan(sunrise) == true) {
                            // After today's sunrise, today's sunset is next
                            nextSunEvent[:time] = sunset;
                            nextSunEvent[:isSunrise] = false;
                        } else {
                            // Today's sunrise is next
                            nextSunEvent[:time] = sunrise;
                            nextSunEvent[:isSunrise] = true;

                            // Used by weather
                            sunriseTodayNotReached = true;
                        }
                    }

                    if(nextSunEvent[:time] != null) {
                        var info = Gregorian.info(nextSunEvent[:time] as Time.Moment, Time.FORMAT_SHORT);
                        time = getFormattedTime(info.hour, info.min, info.sec, true /* hideHoursLeadingZero */);
                        fieldValue[:value] = time[:hour] + ":" + time[:min] + time[:amPm];
                        fieldValue[:iconIsLabel] = false;

                        if(nextSunEvent[:isSunrise] == true) {
                            fieldValue[:icon] = "e";
                        } else {
                            fieldValue[:icon] = "f";
                        }
                    }
                }

                break;
            }

            case FIELD_TYPE_DAY: {
                fieldValue[:icon] = "D";
                fieldValue[:iconIsLabel] = true;
                fieldValue[:value] = now.day.format(INTEGER_FORMAT);
                break;
            }

            case FIELD_TYPE_DOW: {
                fieldValue[:icon] = "W";
                fieldValue[:iconIsLabel] = true;
                // Pattern borrowed from crystal-face:
                // Load strings just-in-time, to save memory. They rarely change, so worthwhile trade-off.
                if((dayOfWeek == null) || (now.day_of_week != dayOfWeek)) {
                    dayOfWeek = now.day_of_week as Number;
                    var resourceArray = [
                        rezStrings.Sun,
                        rezStrings.Mon,
                        rezStrings.Tue,
                        rezStrings.Wed,
                        rezStrings.Thu,
                        rezStrings.Fri,
                        rezStrings.Sat
                        ];
                    var resource = resourceArray[dayOfWeek - 1] as Lang.ResourceId;
                    dayOfWeekString = WatchUi.loadResource(resource) as String;
                    dayOfWeekString = dayOfWeekString.toUpper();
                }
                fieldValue[:value] = dayOfWeekString;
                break;
            }

            case FIELD_TYPE_MONTH: {
                fieldValue[:icon] = "M";
                fieldValue[:iconIsLabel] = true;
                // Pattern borrowed from crystal-face:
                // Load strings just-in-time, to save memory. They rarely change, so worthwhile trade-off.
                if((month == null) || (now.month != month)) {
                    month = now.month as Number;
                    var resourceArray = [
                        rezStrings.Jan,
                        rezStrings.Feb,
                        rezStrings.Mar,
                        rezStrings.Apr,
                        rezStrings.May,
                        rezStrings.Jun,
                        rezStrings.Jul,
                        rezStrings.Aug,
                        rezStrings.Sep,
                        rezStrings.Oct,
                        rezStrings.Nov,
                        rezStrings.Dec
                    ];
                    var resource = resourceArray[month - 1] as Lang.ResourceId;
                    monthString = WatchUi.loadResource(resource) as String;
                    monthString = monthString.toUpper();
                }
                fieldValue[:value] = monthString;
                break;
            }

            case FIELD_TYPE_BODY_BATTERY: {
                fieldValue[:icon] = "d";
                var bodyBattery = complicationsData[Complications.COMPLICATION_TYPE_BODY_BATTERY];
                if((bodyBattery != null) && (bodyBattery[:latestValue] != null)) {
                    bodyBattery = bodyBattery[:latestValue] as Number;
                    fieldValue[:value] = bodyBattery.format(INTEGER_FORMAT);
                }
                break;
            }

            case FIELD_TYPE_CONNECTION_STATUS: {
                fieldValue[:icon] = "b";
                fieldValue[:valueIsIcon] = true;
                fieldValue[:value] = getConnectionIcon(settings);
                break;
            }

            default: {
                // Should not get here
                Test.assertMessage(false, "Invalid FieldType");
                break;
            }
        }

        return fieldValue;
    }

    private function celciusToFarenheit(celcius as Numeric) as Numeric {
        return (celcius * (9.0 / 5)) + 32;
    }

    // NOTE: COMPLICATION_TYPE_CALENDAR_EVENTS returns a string of the next calendar event
    // even if the event is tomorrow, so we need to convert the string to a time
    // and compare it with current time to see if it's today's event or not
    private function convertCalendarEventComplicationTime(is24Hour as Boolean, eventTime as String) as CalendarEventTime or Null {
        var calTime = {};
        var hour = null;
        var min = null;
        var hourStr = null;
        var minStr = null;
        var delimIdx = eventTime.find(":");
        
        // Extract hour
        if((delimIdx != null) && (delimIdx != 0)) {
            hourStr = eventTime.substring(0, delimIdx);
        }
        
        // Extract minute, and possibly 'a' or 'p'
        if((delimIdx != null) && (delimIdx < eventTime.length())) {
            minStr = eventTime.substring(delimIdx + 1, null);
        }

        // Convert hour
        if(hourStr != null) {
            hour = hourStr.toNumber();
        }

        // Convert am/pm to 24-hour
        if((is24Hour == false) && (hour != null) && (minStr != null)) {
            var amIdx = minStr.find("a");
            var pmIdx = minStr.find("p");
            var amPmIdx = amIdx != null ? amIdx : pmIdx;
            System.println(Lang.format("amIdx: $1$ pmIdx: $2$", [amIdx, pmIdx]));
            if(amPmIdx != null) {
                var amPmStr = minStr.substring(amPmIdx, null) as String;
                minStr = minStr.substring(0, amPmIdx);
                System.println(Lang.format("amPmStr: $1$ minStr: $2$", [amPmStr, minStr]));
                if(amPmStr.equals("p")) {
                    hour += 12;
                }
            }
        }

        // Convert minute
        if(minStr != null) {
            min = minStr.toNumber();
        }
        
        if((hour != null) && (min != null)) {
            calTime[:hour24] = hour;
            calTime[:min] = min;
            return calTime;
        } else {
            return null;
        }
    }

    // TODO: the only way to get actual stealth mode status appears to be
    // via checkWifiConnection, which requires Communications and Background
    // permissions and setup.
    // Also, the [:wifi] value always reports NOT_CONNECTED (in the sim).
    //
    // a: stealh mode (stealth filled)
    // c: not-connected (stealth wireframe)
    // l: connected (bluetooth)
    // m: wifi connected (wifi)
    private function getConnectionIcon(settings as System.DeviceSettings) as String {
        var bleInfo = settings.connectionInfo[:bluetooth];
        var wifiInfo = settings.connectionInfo[:wifi];

        var icon = "a";
        //var icon = "c";

        if((bleInfo != null) && (bleInfo.state == System.CONNECTION_STATE_CONNECTED)) {
            icon = "l";
        } else if((wifiInfo != null) && (wifiInfo.state == System.CONNECTION_STATE_CONNECTED)) {
            icon = "m";
        } else if(settings.connectionAvailable == true) {
            icon = "l";
        }

        return icon;
    }

    private function getWeatherIcon(condition as Number) as String {
        var icon = "a"; // sunny

        switch (condition) {
            // cloud
            case Weather.CONDITION_PARTLY_CLOUDY:
            case Weather.CONDITION_MOSTLY_CLOUDY:
            case Weather.CONDITION_CLOUDY:
            case Weather.CONDITION_PARTLY_CLEAR:
            case Weather.CONDITION_THIN_CLOUDS:
                icon = "b";
                break;

            // cloud w/rain
            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_HAIL:
            case Weather.CONDITION_SCATTERED_SHOWERS:
            case Weather.CONDITION_UNKNOWN_PRECIPITATION:
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_HEAVY_SHOWERS:
            case Weather.CONDITION_CHANCE_OF_SHOWERS:
            case Weather.CONDITION_DRIZZLE:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN:
                icon = "c";
                break;

            // snow
            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_WINTRY_MIX:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_HEAVY_SNOW:
            case Weather.CONDITION_LIGHT_RAIN_SNOW:
            case Weather.CONDITION_HEAVY_RAIN_SNOW:
            case Weather.CONDITION_RAIN_SNOW:
            case Weather.CONDITION_ICE:
            case Weather.CONDITION_CHANCE_OF_SNOW:
            case Weather.CONDITION_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_FLURRIES:
            case Weather.CONDITION_FREEZING_RAIN:
            case Weather.CONDITION_SLEET:
            case Weather.CONDITION_ICE_SNOW:
                icon = "e";
                break;

            // fire/smoke
            case Weather.CONDITION_SMOKE:
            case Weather.CONDITION_VOLCANIC_ASH:
                icon = "f";
                break;

            // dust/clouds
            case Weather.CONDITION_FOG:
            case Weather.CONDITION_HAZY:
            case Weather.CONDITION_MIST:
            case Weather.CONDITION_DUST:
            case Weather.CONDITION_SAND:
            case Weather.CONDITION_SQUALL:
            case Weather.CONDITION_SANDSTORM:
            case Weather.CONDITION_HAZE:
                icon = "g";
                break;

            // cloud w/lightning
            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
            case Weather.CONDITION_CHANCE_OF_THUNDERSTORMS:
                icon = "h";
                break;

            // cloud w/wind
            case Weather.CONDITION_WINDY:
            case Weather.CONDITION_TORNADO:
            case Weather.CONDITION_HURRICANE:
            case Weather.CONDITION_TROPICAL_STORM:
                icon = "i";
                break;
        }

        return icon;
    }
}
