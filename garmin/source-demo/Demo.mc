import Toybox.Lang;

//! Bare i demoutgaven (demo.jungle): et hull som Atten på telefonen ville sendt, så simulatoren
//! viser designet uten telefon. Tallene er Anders (markør, ett slag per hull) på hull 3, par 3.
module Demo {
    function hole() as Dictionary<String, Object?>? {
        return {
            "t" => "hole", "r" => "demo", "h" => 2, "n" => 3, "p" => 3, "i" => 15, "c" => 18,
            "rows" => [
                { "m" => "a", "nm" => "Anders", "me" => true, "e" => true, "v" => 3, "s" => null, "rc" => 1, "lo" => 1,
                  "tx" => ["5 p · netto albatross", "4 p · netto eagle", "3 p · netto birdie", "2 p · netto par",
                           "1 p · netto bogey", "0 p · netto dobbel", "0 p · netto dobbel", "0 p · netto dobbel",
                           "0 p · netto dobbel", "0 p · netto dobbel", "0 p · netto dobbel", "0 p · netto dobbel"],
                  "tn" => ["eagle", "eagle", "birdie", "par", "bogey", "dobbel", "blowup", "blowup", "blowup",
                           "blowup", "blowup", "blowup"] },
                { "m" => "b", "nm" => "Bjørn", "me" => false, "e" => true, "v" => 3, "s" => null, "rc" => 1, "lo" => 1,
                  "tx" => ["", "4 p · netto eagle", "3 p · netto birdie", "2 p · netto par"], "tn" => ["", "eagle", "birdie", "par"] },
                { "m" => "c", "nm" => "Cato", "me" => false, "e" => true, "v" => 3, "s" => null, "rc" => 0, "lo" => 1,
                  "tx" => ["", "3 p · netto birdie", "2 p · netto par"], "tn" => ["", "birdie", "par"] },
                { "m" => "d", "nm" => "Dag", "me" => false, "e" => true, "v" => 3, "s" => null, "rc" => 2, "lo" => 1,
                  "tx" => ["", "", "4 p · netto eagle"], "tn" => ["", "", "eagle"] }
            ],
            "st" => [["1.", "Dag", "7 p", "0"], ["2.", "Bjørn", "6 p", "0"], ["3.", "Anders", "5 p", "1"], ["4.", "Cato", "4 p", "0"]]
        };
    }
}
