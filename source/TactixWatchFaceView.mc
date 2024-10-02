import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Test;

class TactixWatchFaceView extends WatchUi.WatchFace {
    typedef DataFieldLayout as {
        // Degrees counter-clockwise from the 3 o'clock position
        :textAngle as Number,
        :direction as Graphics.RadialTextDirection,
    };

    typedef IconPosition as {
        :x as Float,
        :y as Float,
    };

    typedef BurnInOffset as {
        :x as Number,
        :y as Number,
    };

    private static const BURN_IN_SHIFT as Number = 3;

    private static const DATA_FIELD_ICON_TO_TEXT_SPACING as Number = 5;

    private static const DATA_FIELD_FONT_FACE = "RobotoCondensedBold";
    private static const DATA_FIELD_FONT_SIZE = 24;

    private static const TIME_FONT_FACE = "RobotoCondensedBold";
    private const TIME_FONT_SIZE = 82;

    private const PI2 = Math.PI * 2.0;
    private const RADIANS_PER_MINUTE = PI2 / 60.0;

    private static const MAJOR_TICK_HEIGHT = 17.0;
    private static const MAJOR_TICK_HALF_WIDTH = 5.0;
    private static const MINOR_TICK_HEIGHT = 17.0;
    private static const MINOR_TICK_HALF_WIDTH = 2.5;
    private static const MINOR_TICK_OFFSET = 3;
    private static const MARKER_TICK_COLOR = 0xB5A67B; // brown-ish

    // 0°, 90°, 180°, 270°
    private static const MAJOR_TICK_RADIANS as Array<Float> = [
        0.0,
        Math.PI / 2.0,
        Math.PI,
        (3.0 * (Math.PI / 2.0)),
    ];
    private static const MAJOR_TICK_POLY as Array<Graphics.Point2D> = [
        [-MAJOR_TICK_HALF_WIDTH, 0.0],
        [-MAJOR_TICK_HALF_WIDTH, MAJOR_TICK_HEIGHT],
        [MAJOR_TICK_HALF_WIDTH, MAJOR_TICK_HEIGHT],
        [MAJOR_TICK_HALF_WIDTH, 0.0],
    ];

    // 30°, 60°, 120°, 150°, 210°, 240°, 300°, 330°
    private static const MINOR_TICK_RADIANS as Array<Float> = [
        Math.PI / 6.0,
        (Math.PI / 6.0) * 2.0,
        (Math.PI / 6.0) * 4.0,
        (Math.PI / 6.0) * 5.0,
        (Math.PI / 6.0) * 7.0,
        (Math.PI / 6.0) * 8.0,
        (Math.PI / 6.0) * 10.0,
        (Math.PI / 6.0) * 11.0,
    ];
    private static const MINOR_TICK_POLY as Array<Graphics.Point2D> = [
        [-MINOR_TICK_HALF_WIDTH, 0.0],
        [-MINOR_TICK_HALF_WIDTH, MINOR_TICK_HEIGHT],
        [MINOR_TICK_HALF_WIDTH, MINOR_TICK_HEIGHT],
        [MINOR_TICK_HALF_WIDTH, 0.0],
    ];

    private static const MINUTE_HAND_HEIGHT = 30;
    private static const MINUTE_HAND_POLY as Array<Graphics.Point2D> = [
        [-20.0, 0.0],
        [0.0, 30.0],
        [20.0, 0.0],
        [0.0, 15.0],
    ];

    private static const DATA_FIELD_LAYOUTS as Array<DataFieldLayout> = [
        { :textAngle => 15, :direction => Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 45, :direction => Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 75, :direction => Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 105, :direction => Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 135, :direction => Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 165, :direction => Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 195, :direction => Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 225, :direction => Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 255, :direction => Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 285, :direction => Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 315, :direction => Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE } as DataFieldLayout,
        { :textAngle => 345, :direction => Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE } as DataFieldLayout,
    ];

    private static const DATA_FIELDS as Array<FieldType> = [
        FIELD_TYPE_SUNRISE_SUNSET,
        FIELD_TYPE_HIGH_LOW_TEMPERATURE,
        FIELD_TYPE_WEATHER,
        FIELD_TYPE_NOTIFICATIONS,
        FIELD_TYPE_NEXT_CALENDAR_EVENT,
        FIELD_TYPE_CONNECTION_STATUS,
        FIELD_TYPE_BATTERY,
        FIELD_TYPE_HEART_RATE,
        FIELD_TYPE_BODY_BATTERY,
        FIELD_TYPE_DAY,
        FIELD_TYPE_DOW,
        FIELD_TYPE_MONTH,
    ];

    // X/Y offsets used for some burn-in protection
    // Doesn't appear to be strictly neccissary for
    // my device (Tactix 7 AMOLED), but why not.
    // Only used when in always-on/sleep mode.
    private static const BURN_IN_OFFSETS as Array<BurnInOffset> = [
        { :x => 0, :y => BURN_IN_SHIFT } as BurnInOffset,
        { :x => BURN_IN_SHIFT, :y => BURN_IN_SHIFT } as BurnInOffset,
        { :x => BURN_IN_SHIFT, :y => 0 } as BurnInOffset,
        { :x => BURN_IN_SHIFT, :y => -BURN_IN_SHIFT } as BurnInOffset,
        { :x => 0, :y => -BURN_IN_SHIFT } as BurnInOffset,
        { :x => -BURN_IN_SHIFT, :y => -BURN_IN_SHIFT } as BurnInOffset,
        { :x => -BURN_IN_SHIFT, :y => 0 } as BurnInOffset,
        { :x => -BURN_IN_SHIFT, :y => BURN_IN_SHIFT } as BurnInOffset,
    ];

    private var isAsleep as Boolean = false;
    private var lastAsleepMinute as Number or Null = null;
    private var burnInOffsetIndex as Number = 0;

    // displayRadius == width == height
    private var displayRadius as Number = 0;
    private var dataFieldTextRadius as Number = 0;
    private var dataFieldIconRadius as Number = 0;
    private var majorMarkerTickRadius as Number = 0;
    private var minorMarkerTickRadius as Number = 0;
    private var minuteHandRadius as Number = 0;

    private var centerTransform as Graphics.AffineTransform = new Graphics.AffineTransform();

    // TODO make calendar icon bigger
    private var timeFont as Graphics.VectorFont or Null = null;
    private var dataFieldFont as Graphics.VectorFont or Null = null;
    private var icons as WatchUi.FontResource or Null = null;
    private var weatherIcons as WatchUi.FontResource or Null = null;

    private var fieldValues as FieldValues;

    function initialize() {
        WatchFace.initialize();

        // Expected capabilities
        Test.assertMessage(Graphics has :VectorFont, "Missing VectorFont support");
        Test.assertMessage(Graphics has :createBufferedBitmap, "Missing createBufferedBitmap support");
        Test.assertMessage(Graphics has :BufferedBitmap, "Missing BufferedBitmap support");
        // TODO
        // settings requiresBurnInProtection
        // and others

        // Each data field can occupy 1/12 (30 deg) of the radial region
        Test.assert(DATA_FIELD_LAYOUTS.size() == 12);
        Test.assert(DATA_FIELDS.size() <= 12);

        fieldValues = new FieldValues(DATA_FIELDS);
    }

    function onLayout(dc as Dc) as Void {
        var displayWidth = dc.getWidth();
        var displayHeight = dc.getHeight();
        Test.assertEqual(displayWidth, displayHeight);

        displayRadius = displayWidth / 2;
        dataFieldTextRadius = displayRadius - (DATA_FIELD_FONT_SIZE / 2) - BURN_IN_SHIFT;
        dataFieldIconRadius = dataFieldTextRadius - DATA_FIELD_FONT_SIZE - DATA_FIELD_ICON_TO_TEXT_SPACING;

        majorMarkerTickRadius = dataFieldIconRadius - (DATA_FIELD_FONT_SIZE / 2) - MAJOR_TICK_HEIGHT as Number;
        minorMarkerTickRadius = majorMarkerTickRadius - MINOR_TICK_OFFSET;

        minuteHandRadius = majorMarkerTickRadius - MINUTE_HAND_HEIGHT;

        centerTransform.setToTranslation(displayRadius as Float, displayRadius as Float);

        timeFont = Graphics.getVectorFont({
            :face => TIME_FONT_FACE,
            :size => TIME_FONT_SIZE,
        });
        Test.assertMessage(timeFont != null, "Unsupported time font");

        dataFieldFont = Graphics.getVectorFont({
            :face => DATA_FIELD_FONT_FACE,
            :size => DATA_FIELD_FONT_SIZE,
        });
        Test.assertMessage(dataFieldFont != null, "Unsupported data field font");

        icons = WatchUi.loadResource(Rez.Fonts.Icons) as WatchUi.FontResource;
        Test.assertMessage(icons != null, "Invalid icons resource");

        weatherIcons = WatchUi.loadResource(Rez.Fonts.WeatherIcons) as WatchUi.FontResource;
        Test.assertMessage(weatherIcons != null, "Invalid weather icons resource");
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        var timeInfo = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        // Set the background color then call to clear the screen
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setAntiAlias(true);

        // Do burn-in protection offsets when asleep
        // update on-sleep or every minute while asleep
        var adjustX = 0;
        var adjustY = 0;
        if(isAsleep == true) {
            if((lastAsleepMinute == null) || (lastAsleepMinute != timeInfo.min)) {
                incrementBurnInOffset();
                lastAsleepMinute = timeInfo.min;
            }

            adjustX = BURN_IN_OFFSETS[burnInOffsetIndex][:x] as Number;
            adjustY = BURN_IN_OFFSETS[burnInOffsetIndex][:y] as Number;
        }
        centerTransform.setToTranslation((adjustX + displayRadius) as Float, (adjustY + displayRadius) as Float);

        var settings = System.getDeviceSettings();

        // Draw marker ticks and minute hand poly
        drawMarkerTicks(dc);
        drawMinuteHand(dc, timeInfo.min);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for(var i = 0; i < DATA_FIELDS.size(); i++) {
            var fieldValue = fieldValues.getValue(timeInfo, settings, DATA_FIELDS[i]);
            var layout = DATA_FIELD_LAYOUTS[i];

            // Draw the value in the outer ring
            // Can be text or an icon
            if(fieldValue[:valueIsIcon] == true) {
                // Value is an icon
                var font = fieldValue[:usesWeatherIcons] == true ? weatherIcons : icons;
                var pos = getIconPosition(dataFieldTextRadius, layout[:textAngle] as Number);
                dc.drawText(
                    (pos[:x] as Float) + (adjustX as Float),
                    (pos[:y] as Float) + (adjustY as Float),
                    font as WatchUi.FontResource,
                    fieldValue[:value] as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            } else {
                // Value is text
                dc.drawRadialText(
                    displayRadius + adjustX,
                    displayRadius + adjustY,
                    dataFieldFont as Graphics.VectorFont,
                    fieldValue[:value] as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER,
                    layout[:textAngle] as Number,
                    dataFieldTextRadius,
                    layout[:direction] as Graphics.RadialTextDirection
                );
            }

            // Draw the icon in the inner ring
            // Icon can be text or an icon from the icons or weather icons resource
            if(fieldValue[:iconIsLabel] == true) {
                // Icon is just text
                dc.drawRadialText(
                    displayRadius + adjustX,
                    displayRadius + adjustY,
                    dataFieldFont as Graphics.VectorFont,
                    fieldValue[:icon] as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER,
                    layout[:textAngle] as Number,
                    dataFieldIconRadius,
                    layout[:direction] as Graphics.RadialTextDirection
                );
            } else {
                // Icon is one of the resource fonts
                var font = fieldValue[:usesWeatherIcons] == true ? weatherIcons : icons;
                var pos = getIconPosition(dataFieldIconRadius, layout[:textAngle] as Number);
                dc.drawText(
                    (pos[:x] as Float) + (adjustX as Float),
                    (pos[:y] as Float) + (adjustY as Float),
                    font as WatchUi.FontResource,
                    fieldValue[:icon] as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            }
        }

        // Draw the current time
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var time = getFormattedTime(timeInfo.hour, timeInfo.min, timeInfo.sec, false /* hideHoursLeadingZero */);
        var timeText = time[:hour] + ":" + time[:min];
        if(isAsleep == false) {
            timeText = timeText + ":" + time[:sec];
        }
        timeText = timeText + time[:amPm];
        dc.drawText(
            displayRadius + adjustX,
            displayRadius + adjustY,
            timeFont as Graphics.VectorFont,
            timeText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    // Draws the major and minor tick markers
    private function drawMarkerTicks(dc as Dc) as Void {
        /*
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(100, displayRadius, 300, displayRadius);
        dc.drawLine(displayRadius, 100, displayRadius, 300);
        dc.drawCircle(displayRadius, displayRadius, dataFieldTextRadius);
        dc.drawCircle(displayRadius, displayRadius, dataFieldIconRadius);
        dc.drawCircle(displayRadius, displayRadius, majorMarkerTickRadius);
        */

        dc.setColor(MARKER_TICK_COLOR, Graphics.COLOR_TRANSPARENT);

        var localTransform = new Graphics.AffineTransform();
        for(var idx = 0; idx < MAJOR_TICK_RADIANS.size(); idx += 1) {
            localTransform.initialize();
            localTransform.rotate(MAJOR_TICK_RADIANS[idx]);
            localTransform.translate(0.0, majorMarkerTickRadius as Float);
            var relPoly = localTransform.transformPoints(MAJOR_TICK_POLY);
            var poly = centerTransform.transformPoints(relPoly);
            dc.fillPolygon(poly);
        }
        
        for(var idx = 0; idx < MINOR_TICK_RADIANS.size(); idx += 1) {
            localTransform.initialize();
            localTransform.rotate(MINOR_TICK_RADIANS[idx]);
            localTransform.translate(0.0, minorMarkerTickRadius as Float);
            var relPoly = localTransform.transformPoints(MINOR_TICK_POLY);
            var poly = centerTransform.transformPoints(relPoly);
            dc.fillPolygon(poly);
        }
    }

    // min 0..=59
    private function drawMinuteHand(dc as Dc, min as Number) as Void {
        var theta = Math.PI + (RADIANS_PER_MINUTE * min);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        var localTransform = new Graphics.AffineTransform();
        localTransform.rotate(theta);
        localTransform.translate(0.0, minuteHandRadius as Float);
        var relPoly = localTransform.transformPoints(MINUTE_HAND_POLY);
        var poly = centerTransform.transformPoints(relPoly);
        dc.fillPolygon(poly);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
        // Do nothing
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() as Void {
        isAsleep = false;
    }

    // Terminate any active timers and prepare for slow updates.
    function onEnterSleep() as Void {
        isAsleep = true;
        lastAsleepMinute = null;
    }

    private function incrementBurnInOffset() as Void {
        burnInOffsetIndex = (burnInOffsetIndex + 1) % BURN_IN_OFFSETS.size();
    }

    private function getIconPosition(radius as Number, layoutAngleDegrees as Number) as IconPosition {
        // TODO use Graphics.AffineTransform for this instead
        var theta = -1.0 * Math.toRadians(layoutAngleDegrees as Float);
        var cos = Math.cos(theta);
        var sin = Math.sin(theta);
        var x = ((radius as Float) * cos) + displayRadius;
        var y = ((radius as Float) * sin) + displayRadius;
        return {
            :x => x,
            :y => y,
        } as IconPosition;
    }
}
