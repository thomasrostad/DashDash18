import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Atten på Garmin: fører hullet og viser «Bayen nå» for runden som går i Atten på telefonen.
//! Telefonen regner alt og sender ett hull om gangen. Klokka viser og sender slagene tilbake, og
//! Atten legger dem i utboksen som hullkortet på telefonen gjør.
class AttenApp extends Application.AppBase {
    private var _model as AttenModel;
    private var _link as PhoneLink;

    function initialize() {
        AppBase.initialize();
        _model = new AttenModel();
        _link = new PhoneLink(_model);
    }

    function onStart(state as Dictionary?) as Void {
        _model.restore();
        var demo = Demo.hole();
        if (demo != null) { _model.receive(demo); }
        _link.start();
    }

    function onStop(state as Dictionary?) as Void {
        _link.stop();
        _model.persist();
    }

    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        return [ new HoleView(_model), new HoleDelegate(_model, _link) ] as [ WatchUi.Views, WatchUi.InputDelegates ];
    }
}
