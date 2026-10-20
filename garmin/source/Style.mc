import Toybox.Graphics;
import Toybox.Lang;

// Design B (#550, `other-watches/garmin-proposals.png`): Garmin's own data-field look. Black, one colour per role.
module Style {
    const TITLE = 0x8A8CFF;
    const ACCENT = 0x8A4FF0;
    const REST = 0x3CC8A0;
    const HEART = 0xE86FB0;
    const MUTED = 0xAAAAAA;
    const LINE = 0x333333;
    const LIME = 0xCCFF3D;

    const CENTER = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function clear(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }

    function text(dc as Graphics.Dc, y as Numeric, font as Graphics.FontType, s as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, font, s, CENTER);
    }

    // Thin rule between the headline and the numbers.
    function rule(dc as Graphics.Dc, y as Numeric) as Void {
        var w = dc.getWidth();
        dc.setColor(LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.18, y, w * 0.82, y);
    }

    // Rounded pill with a label, the START / LOG button.
    function pill(dc as Graphics.Dc, y as Numeric, label as String, fill as Number, ink as Number) as Void {
        var w = dc.getWidth();
        var font = Graphics.FONT_SMALL;
        var tw = dc.getTextWidthInPixels(label, font) + w * 0.12;
        var th = dc.getFontHeight(font) + 6;
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((w - tw) / 2, y - th / 2, tw, th, th / 2);
        dc.setColor(ink, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, label, CENTER);
    }

    function kg(value as Numeric?) as String {
        if (value == null) {
            return "-";
        }
        var f = value.toFloat();
        return f == f.toNumber().toFloat() ? f.toNumber().toString() : f.format("%.1f");
    }

    function clock(seconds as Number) as String {
        if (seconds < 0) {
            seconds = 0;
        }
        return (seconds / 60).toString() + ":" + (seconds % 60).format("%02d");
    }
}
