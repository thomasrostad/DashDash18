import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Fargene. Klokka er mørk; på MIP-skjermene blir de nærmeste av de 64 fargene.
module Palette {
    const BG = Graphics.COLOR_BLACK;
    //! Raden som er valgt: skog med gul kant, som på Apple Watch.
    const SELECTED = 0x1C483A;
    const YELLOW = 0xF5C842;
    const SECONDARY = 0xA3B5AB;
    const RUST = 0xF08A4B;

    //! Scorefargen (`ScoreName` i Atten).
    function tone(name as String) as Number {
        if (name.equals("eagle")) { return 0xF2E3A6; }
        if (name.equals("birdie")) { return 0x7FD67F; }
        if (name.equals("par")) { return Graphics.COLOR_WHITE; }
        if (name.equals("bogey")) { return 0xF6A27F; }
        if (name.equals("dobbel")) { return 0xF26B5B; }
        return SECONDARY;
    }
}

//! Hullet: «Hull 3 · par 3», én rad per spiller, og teksten under raden som er valgt.
class HoleView extends WatchUi.View {
    private var _model as AttenModel;

    function initialize(model as AttenModel) {
        View.initialize();
        _model = model;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Palette.BG);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var hole = _model.hole;
        if (hole == null) {
            drawEmpty(dc, w, h);
            return;
        }

        var title = "Hull " + hole.number.toString() + " · par " + hole.par.toString();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_SMALL, title, Graphics.TEXT_JUSTIFY_CENTER);

        // Runde skjermer er smalere øverst og nederst, så radene står i midtfeltet.
        var top = h * 0.24;
        var bottom = h * 0.80;
        var left = w * 0.14;
        var right = w * 0.86;
        var line = dc.getFontHeight(Graphics.FONT_TINY);
        var small = dc.getFontHeight(Graphics.FONT_XTINY);
        var selected = _model.selectedRow();
        var y = top;
        for (var i = 0; i < hole.rows.size(); i += 1) {
            var row = hole.rows[i];
            var isSelected = selected != null && selected.member.equals(row.member);
            var rowH = isSelected ? line + small : line;
            if (y + rowH > bottom) { break; }
            if (isSelected) {
                dc.setColor(Palette.SELECTED, Palette.SELECTED);
                dc.fillRoundedRectangle(left - 6, y - 2, right - left + 12, rowH + 4, 8);
                dc.setColor(Palette.YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawRoundedRectangle(left - 6, y - 2, right - left + 12, rowH + 4, 8);
            }
            var value = _model.value(row);
            var dimmed = _model.isDefault(row);
            var name = row.received > 0 ? row.name + " " + dots(row.received) : row.name;
            dc.setColor(dimmed ? Palette.SECONDARY : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y, Graphics.FONT_TINY, name, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(right, y, Graphics.FONT_TINY, value.toString(), Graphics.TEXT_JUSTIFY_RIGHT);
            if (isSelected) {
                var text = dimmed ? "forvalgt par" : row.text(value);
                dc.setColor(dimmed ? Palette.SECONDARY : Palette.tone(row.tone(value)), Graphics.COLOR_TRANSPARENT);
                dc.drawText(left, y + line, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT);
            }
            y += rowH + 6;
        }

        dc.setColor(_model.queue.size() > 0 ? Palette.RUST : Palette.SECONDARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.84, Graphics.FONT_XTINY, status(), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawEmpty(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(Palette.YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.30, Graphics.FONT_MEDIUM, "Atten", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var headline = _model.noRound ? "Ingen runde nå" : "Venter på telefonen";
        dc.drawText(w / 2, h * 0.48, Graphics.FONT_SMALL, headline, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Palette.SECONDARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.62, Graphics.FONT_XTINY, "Åpne runden i Atten\npå telefonen", Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Linja nederst: hva som venter, ellers hva Start gjør.
    private function status() as String {
        var n = _model.queue.size();
        if (n == 1) { return "1 hull venter"; }
        if (n > 1) { return n.toString() + " hull venter"; }
        if (_model.waiting) { return "Sendt"; }
        var hole = _model.hole;
        if (hole != null && _model.selected < hole.editable().size() - 1) { return "Start: neste spiller"; }
        return "Start: lagre hullet";
    }

    //! Slag mottatt som prikker, høyst tre.
    private function dots(n as Number) as String {
        return n >= 3 ? "•••" : (n == 2 ? "••" : "•");
    }
}

//! Knappene: opp/ned endrer slagene, Start går til neste spiller og lagrer på den siste,
//! Tilbake går til forrige spiller, og menyen (hold opp) har «Bayen nå» og hullene.
class HoleDelegate extends WatchUi.BehaviorDelegate {
    private var _model as AttenModel;
    private var _link as PhoneLink;

    function initialize(model as AttenModel, link as PhoneLink) {
        BehaviorDelegate.initialize();
        _model = model;
        _link = link;
    }

    function onPreviousPage() as Boolean {
        _model.step(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        _model.step(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        if (_model.hole == null) { return false; }
        if (_model.advance()) { _link.save(); }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        if (_model.back()) {
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onMenu() as Boolean {
        var hole = _model.hole;
        if (hole == null) { return false; }
        var menu = new WatchUi.Menu2({ :title => "Atten" });
        menu.addItem(new WatchUi.MenuItem("Bayen nå", null, :standings, null));
        if (hole.index > 0) { menu.addItem(new WatchUi.MenuItem("Forrige hull", null, :previous, null)); }
        if (hole.index < hole.count - 1) { menu.addItem(new WatchUi.MenuItem("Neste hull", null, :next, null)); }
        WatchUi.pushView(menu, new HoleMenuDelegate(_model, _link), WatchUi.SLIDE_UP);
        return true;
    }
}

class HoleMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _model as AttenModel;
    private var _link as PhoneLink;

    function initialize(model as AttenModel, link as PhoneLink) {
        Menu2InputDelegate.initialize();
        _model = model;
        _link = link;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var hole = _model.hole;
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (hole == null) { return; }
        if (id == :standings) {
            WatchUi.pushView(new StandingsView(_model), new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :previous) {
            _link.request(hole.index - 1);
        } else if (id == :next) {
            _link.request(hole.index + 1);
        }
    }
}

//! «Bayen nå» for båsen, slik telefonen regner den.
class StandingsView extends WatchUi.View {
    private var _model as AttenModel;

    function initialize(model as AttenModel) {
        View.initialize();
        _model = model;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Palette.BG);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_SMALL, "Bayen nå", Graphics.TEXT_JUSTIFY_CENTER);
        var hole = _model.hole;
        if (hole == null) { return; }
        var left = w * 0.14;
        var right = w * 0.86;
        var line = dc.getFontHeight(Graphics.FONT_TINY) + 4;
        var y = h * 0.24;
        for (var i = 0; i < hole.standings.size() && y + line < h * 0.88; i += 1) {
            var s = hole.standings[i];
            if (s.size() < 4) { continue; }
            dc.setColor(s[3].equals("1") ? Palette.YELLOW : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y, Graphics.FONT_TINY, s[0] + " " + s[1], Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(right, y, Graphics.FONT_TINY, s[2], Graphics.TEXT_JUSTIFY_RIGHT);
            y += line;
        }
    }
}
