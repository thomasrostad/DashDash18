import Toybox.Lang;
import Toybox.Test;

//! Modellen på klokka: opp/ned, Start gjennom båsen og hullet som sendes. Kjøres med
//! `tools/build.sh test`. Hullet er som telefonen sender det (GarminMessage i Atten).
(:test)
module AttenTests {
    function sampleHole() as Dictionary<String, Object?> {
        return {
            "t" => "hole", "r" => "runde-1", "h" => 2, "n" => 3, "p" => 3, "i" => 15, "c" => 18,
            "rows" => [
                { "m" => "anders", "nm" => "Anders", "me" => true, "e" => true, "v" => 3, "s" => null,
                  "rc" => 1, "lo" => 1, "tx" => ["5 p · netto albatross", "4 p · netto eagle", "3 p · netto birdie",
                                                  "2 p · netto par", "1 p · netto bogey", "tak 6 slag"],
                  "tn" => ["eagle", "eagle", "birdie", "par", "bogey", "dobbel"] },
                { "m" => "bjorn", "nm" => "Bjørn", "me" => false, "e" => true, "v" => 4, "s" => 4,
                  "rc" => 0, "lo" => 1, "tx" => ["a", "b", "c", "d"], "tn" => ["", "", "", ""] },
                { "m" => "cato", "nm" => "Cato", "me" => false, "e" => false, "v" => 3, "s" => 3,
                  "rc" => 0, "lo" => 3, "tx" => ["2 p · netto par"], "tn" => ["par"] }
            ],
            "st" => [["1.", "Bjørn", "12 slag", "0"], ["2.", "Anders", "15 slag", "1"]]
        };
    }

    function model() as AttenModel {
        var m = new AttenModel();
        m.receive(sampleHole());
        return m;
    }

    (:test)
    function radeneOgTeksten(logger as Logger) as Boolean {
        var m = model();
        var hole = m.hole as HoleCard;
        Test.assertEqual(hole.number, 3);
        Test.assertEqual(hole.editable().size(), 2);
        var anders = hole.rows[0];
        Test.assertEqual(anders.text(4), "2 p · netto par");
        Test.assertEqual(anders.tone(3), "birdie");
        Test.assert(m.isDefault(anders));
        Test.assert(!m.isDefault(hole.rows[1]));
        Test.assertEqual(hole.standings[1][1], "Anders");
        return true;
    }

    //! Opp/ned stopper ved taket og ved 1.
    (:test)
    function oppOgNedStopperVedTaket(logger as Logger) as Boolean {
        var m = model();
        var anders = (m.hole as HoleCard).rows[0];
        for (var i = 0; i < 10; i += 1) { m.step(1); }
        Test.assertEqual(m.value(anders), 6);
        for (var i = 0; i < 10; i += 1) { m.step(-1); }
        Test.assertEqual(m.value(anders), 1);
        return true;
    }

    //! Start går gjennom radene klokka fører, og sender på den siste med tallene som står.
    (:test)
    function startGjennomBaasen(logger as Logger) as Boolean {
        var m = model();
        m.step(1);
        Test.assert(!m.advance());
        Test.assertEqual(m.selected, 1);
        Test.assert(m.advance());
        var message = m.saveMessage() as Dictionary<String, Object>;
        Test.assertEqual(message["t"] as String, "save");
        Test.assertEqual(message["h"] as Number, 2);
        var scores = message["sc"] as Array<Array<Object>>;
        Test.assertEqual(scores.size(), 2);
        Test.assertEqual(scores[0][1], 4);
        Test.assertEqual(scores[1][1], 4);
        return true;
    }

    //! Samme hull på nytt (nyere tall fra telefonen) beholder det som er tastet. Et annet hull gjør ikke.
    (:test)
    function sammeHullBeholderUtkastet(logger as Logger) as Boolean {
        var m = model();
        m.step(1);
        m.receive(sampleHole());
        Test.assertEqual(m.drafts.size(), 1);
        var other = sampleHole();
        other["h"] = 3;
        m.receive(other);
        Test.assertEqual(m.drafts.size(), 0);
        m.receive({ "t" => "none" });
        Test.assert(m.hole == null);
        Test.assert(m.noRound);
        return true;
    }

    //! Tilbake på første spiller lukker appen (false), ellers går den til forrige.
    (:test)
    function tilbake(logger as Logger) as Boolean {
        var m = model();
        Test.assert(!m.back());
        m.advance();
        Test.assert(m.back());
        Test.assertEqual(m.selected, 0);
        return true;
    }
}
