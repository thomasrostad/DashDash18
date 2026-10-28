import Toybox.Communications;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

//! Meldingene til og fra Atten på telefonen (Connect IQ Mobile SDK i Atten).
//!
//! Til telefonen: «hello» når appen starter, «get» for et annet hull, «save» med slagene.
//! Fra telefonen: «hole» (hullet ferdig regnet) eller «none» (ingen runde).
//! Hull som skal lagres, ligger i køen til telefonen har fått dem, også om appen lukkes.
class PhoneLink {
    private var _model as AttenModel;
    private var _sending as Boolean = false;
    private var _timer as Timer.Timer;

    //! Hvor ofte køen prøves på nytt når telefonen ikke svarer.
    private const RETRY_MS = 15000;

    function initialize(model as AttenModel) {
        _model = model;
        _timer = new Timer.Timer();
    }

    function start() as Void {
        Communications.registerForPhoneAppMessages(method(:onPhone));
        hello();
        flush();
        _timer.start(method(:retry), RETRY_MS, true);
    }

    function stop() as Void {
        _timer.stop();
    }

    function onPhone(message as Communications.PhoneAppMessage) as Void {
        var data = message.data;
        if (data instanceof Dictionary) {
            _model.receive(data as Dictionary<String, Object?>);
            WatchUi.requestUpdate();
        }
    }

    //! Hullet legges i køen først, så det ikke går tapt om telefonen er utenfor rekkevidde.
    function save() as Void {
        var message = _model.saveMessage();
        if (message == null) { return; }
        _model.enqueue(message);
        flush();
    }

    //! Et annet hull («Forrige hull», «Neste hull» i menyen).
    function request(index as Number) as Void {
        var hole = _model.hole;
        if (hole == null || index < 0 || index >= hole.count) { return; }
        Communications.transmit({ "t" => "get", "r" => hole.round, "h" => index }, null, new QuietListener());
    }

    function hello() as Void {
        Communications.transmit({ "t" => "hello" }, null, new QuietListener());
    }

    function flush() as Void {
        if (_sending || _model.queue.size() == 0) { return; }
        _sending = true;
        var message = _model.queue[0] as Dictionary<Communications.TransmitKeyType, Communications.TransmitType>;
        Communications.transmit(message, null, new QueueListener(self));
    }

    function sent() as Void {
        _sending = false;
        _model.dequeue();
        WatchUi.requestUpdate();
        flush();
    }

    function failed() as Void {
        _sending = false;
        WatchUi.requestUpdate();
    }

    function retry() as Void {
        flush();
        if (_model.hole == null) { hello(); }
    }
}

//! Køen: neste hull sendes først når telefonen har fått det forrige.
class QueueListener extends Communications.ConnectionListener {
    private var _link as PhoneLink;

    function initialize(link as PhoneLink) {
        ConnectionListener.initialize();
        _link = link;
    }

    function onComplete() as Void {
        _link.sent();
    }

    function onError() as Void {
        _link.failed();
    }
}

//! Forespørsler som ikke trenger svar her: svaret kommer som en egen melding fra telefonen.
class QuietListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
    }

    function onError() as Void {
    }
}
