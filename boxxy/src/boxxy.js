function Boxxy() {
    this.teams = {};
    this.laps = [];
    this.maxLaps = 10;

    /* To be user will override this */
    this.onUpdate = function() {};
    this.onPutState = function(state) {};
    this.onAddLap = function(lap) {};
}

Boxxy.prototype.putState = function(state) {
    this.teams = state.teams;
    this.laps = state.laps;

    this.onUpdate();
    this.onPutState(state);
}

Boxxy.prototype.addLap = function(lap) {
    this.laps = [lap].concat(this.laps);
    if(this.laps.length > this.maxlaps) this.laps.shift();

    this.teams[lap.team.id] = lap.team;

    this.onUpdate();
    this.onAddLap(lap);
}

Boxxy.prototype.teamsByScore = function() {
    var byScore = [];
    for(var i in this.teams) byScore.push(this.teams[i]);
    byScore.sort(function (a, b) {
        return b.laps - a.laps;
    });
    return byScore;
}

// Only used on the client side: this requires sockets.io to be in scope
Boxxy.prototype.listen = function(uri) {
    var boxxy  = this;
    var socket = io.connect(uri);

    socket.on('/state', function(state) {
        boxxy.putState(state);
    });

    socket.on('/lap', function(lap) {
        boxxy.addLap(lap);
    });
}

exports.initialize = function() {
    return new Boxxy();
}