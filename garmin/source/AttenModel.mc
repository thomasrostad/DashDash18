import Toybox.Application;
import Toybox.Lang;

//! Tall fra telefonen. iOS kan sende heltall som Number eller Long, og sannhetsverdier som Boolean
//! eller tall, så alt leses gjennom disse.
module Msg {
    function num(value as Object?) as Number {
        if (value instanceof Number) { return value; }
        if (value instanceof Long) { return value.toNumber(); }
        if (value instanceof Float) { return value.toNumber(); }
        if (value instanceof Double) { return value.toNumber(); }
        return 0;
    }

    function flag(value as Object?) as Boolean {
        if (value instanceof Boolean) { return value; }
        return num(value) != 0;
    }

    function text(value as Object?) as String {
        return value instanceof String ? value : "";
    }

    function texts(value as Object?) as Array<String> {
        var out = [] as Array<String>;
        if (value instanceof Array) {
            var list = value as Array<Object?>;
            for (var i = 0; i < list.size(); i += 1) { out.add(text(list[i])); }
        }
        return out;
    }
}

//! Én spiller på hullet, slik telefonen regnet den (WatchRound.Row i Atten, kuttet ned).
class HoleRow {
    var member as String;
    var name as String;
    var isMe as Boolean;
    //! Klokka kan føre for spilleren: deg selv, eller båsen når du er markør.
    var editable as Boolean;
    //! Tallet som står: det lagrede, ellers par (forvalget).
    var value as Number;
    var saved as Boolean;
    //! Slag spilleren får på hullet.
    var received as Number;
    //! Slagantallet den første teksten gjelder.
    var low as Number;
    //! Teksten hullkortet på telefonen viser for hvert slagantall fra `low`: «2 p · netto par».
    var texts as Array<String>;
    //! Scorefargen for hvert slagantall: «birdie», «par» …
    var tones as Array<String>;

    function initialize(d as Dictionary<String, Object?>) {
        member = Msg.text(d["m"]);
        name = Msg.text(d["nm"]);
        isMe = Msg.flag(d["me"]);
        editable = Msg.flag(d["e"]);
        value = Msg.num(d["v"]);
        saved = d["s"] != null;
        received = Msg.num(d["rc"]);
        low = Msg.num(d["lo"]);
        texts = Msg.texts(d["tx"]);
        tones = Msg.texts(d["tn"]);
    }

    function high() as Number {
        return low + texts.size() - 1;
    }

    //! Opp/ned: aldri under det minste eller over taket.
    function clamp(strokes as Number) as Number {
        if (texts.size() == 0) { return value; }
        if (strokes < low) { return low; }
        if (strokes > high()) { return high(); }
        return strokes;
    }

    function text(strokes as Number) as String {
        var i = strokes - low;
        return (i >= 0 && i < texts.size()) ? texts[i] : "";
    }

    function tone(strokes as Number) as String {
        var i = strokes - low;
        return (i >= 0 && i < tones.size()) ? tones[i] : "";
    }
}

//! Hullet telefonen sendte: nummer, par, radene og «Bayen nå» for båsen.
class HoleCard {
    var round as String;
    //! Rundens 0-baserte hull.
    var index as Number;
    var number as Number;
    var par as Number;
    var strokeIndex as Number?;
    //! Hull i runden, så «Neste hull» vet hvor langt den kan gå.
    var count as Number;
    var rows as Array<HoleRow>;
    //! [plass, navn, verdi, meg] per rad i «Bayen nå».
    var standings as Array<Array<String>>;

    function initialize(d as Dictionary<String, Object?>) {
        round = Msg.text(d["r"]);
        index = Msg.num(d["h"]);
        number = Msg.num(d["n"]);
        par = Msg.num(d["p"]);
        strokeIndex = d["i"] == null ? null : Msg.num(d["i"]);
        count = Msg.num(d["c"]);
        rows = [] as Array<HoleRow>;
        var list = d["rows"];
        if (list instanceof Array) {
            var items = list as Array<Object?>;
            for (var i = 0; i < items.size(); i += 1) {
                var row = items[i];
                if (row instanceof Dictionary) { rows.add(new HoleRow(row as Dictionary<String, Object?>)); }
            }
        }
        standings = [] as Array<Array<String>>;
        var table = d["st"];
        if (table instanceof Array) {
            var items = table as Array<Object?>;
            for (var i = 0; i < items.size(); i += 1) { standings.add(Msg.texts(items[i])); }
        }
    }

    //! Radene klokka fører, i rekkefølgen på kortet.
    function editable() as Array<HoleRow> {
        var out = [] as Array<HoleRow>;
        for (var i = 0; i < rows.size(); i += 1) {
            if (rows[i].editable) { out.add(rows[i]); }
        }
        return out;
    }
}

//! Det klokka vet: hullet som vises, tallene som er endret, og hull som er sendt men ikke kommet
//! fram til telefonen. Klokka regner ingenting selv: tekstene kommer ferdige fra telefonen.
class AttenModel {
    var hole as HoleCard? = null;
    //! Tall endret på klokka for hullet som vises, før det er sendt.
    var drafts as Dictionary<String, Number> = {} as Dictionary<String, Number>;
    //! Raden opp/ned endrer, blant radene klokka fører.
    var selected as Number = 0;
    //! Hull som ikke er kommet fram til telefonen. Lagres, så de overlever at appen lukkes.
    var queue as Array<Dictionary> = [] as Array<Dictionary>;
    //! Telefonen svarte at ingen runde går.
    var noRound as Boolean = false;
    //! Hullet er sendt, og klokka venter på neste fra telefonen.
    var waiting as Boolean = false;

    private const QUEUE_KEY = "queue";

    function initialize() {
    }

    //! En melding fra Atten på telefonen: «hole» eller «none».
    function receive(d as Dictionary<String, Object?>) as Void {
        var type = Msg.text(d["t"]);
        if (type.equals("none")) {
            hole = null;
            noRound = true;
            waiting = false;
            drafts = {} as Dictionary<String, Number>;
            return;
        }
        if (!type.equals("hole")) { return; }
        var next = new HoleCard(d);
        var current = hole;
        var same = current != null && current.round.equals(next.round) && current.index == next.index;
        hole = next;
        noRound = false;
        waiting = false;
        if (!same) {
            drafts = {} as Dictionary<String, Number>;
            selected = 0;
        } else if (selected >= next.editable().size()) {
            selected = 0;
        }
    }

    function selectedRow() as HoleRow? {
        var current = hole;
        if (current == null) { return null; }
        var rows = current.editable();
        return selected < rows.size() ? rows[selected] : null;
    }

    //! Tallet som står: det klokka har endret, ellers telefonens.
    function value(row as HoleRow) as Number {
        var draft = drafts[row.member];
        return draft != null ? draft : row.value;
    }

    //! Står på forvalget (par) uten at noen har tastet: vises dempet, som på telefonen.
    function isDefault(row as HoleRow) as Boolean {
        return row.editable && !row.saved && drafts[row.member] == null;
    }

    //! Opp og ned.
    function step(delta as Number) as Void {
        var row = selectedRow();
        if (row == null) { return; }
        drafts[row.member] = row.clamp(value(row) + delta);
    }

    //! Start: bekreft tallet og gå til neste spiller. Gir true på den siste: da sendes hullet.
    function advance() as Boolean {
        var current = hole;
        if (current == null) { return false; }
        var rows = current.editable();
        if (rows.size() == 0) { return false; }
        var row = rows[selected];
        drafts[row.member] = value(row);
        if (selected < rows.size() - 1) {
            selected += 1;
            return false;
        }
        return true;
    }

    //! Tilbake: forrige spiller. False på den første, så tilbake lukker appen som vanlig.
    function back() as Boolean {
        if (selected > 0) {
            selected -= 1;
            return true;
        }
        return false;
    }

    //! Hullet slik telefonen tar imot det: alle radene klokka fører, med tallene som står.
    function saveMessage() as Dictionary? {
        var current = hole;
        if (current == null) { return null; }
        var scores = [] as Array<Array>;
        var rows = current.editable();
        for (var i = 0; i < rows.size(); i += 1) {
            scores.add([rows[i].member, value(rows[i])]);
        }
        return { "t" => "save", "r" => current.round, "h" => current.index, "sc" => scores };
    }

    function enqueue(message as Dictionary) as Void {
        queue.add(message);
        waiting = true;
        persist();
    }

    function dequeue() as Void {
        if (queue.size() > 0) { queue = queue.slice(1, null); }
        persist();
    }

    function restore() as Void {
        var saved = Application.Storage.getValue(QUEUE_KEY);
        if (saved instanceof Array) { queue = saved as Array<Dictionary>; }
    }

    function persist() as Void {
        Application.Storage.setValue(QUEUE_KEY, queue as Array<Application.Storage.ValueType>);
    }
}
