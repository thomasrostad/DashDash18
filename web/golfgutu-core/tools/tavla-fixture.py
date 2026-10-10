"""Lager test/fixtures/tavla.json: et svar fra RPC-en tavla_data (sql/036) og tre sesongrader.

Laget etter TavlaSamples.swift (DashDash18/Features/Tavla), utvidet med lag, trekant, manuelle resultater,
siste ni, avkorting, frosset handicap, tee, kladd og simulator, så mappingen i appen blir prøvd.
Fasiten (tavla.forventet.json) regnes av appens egen Swift-kode med tools/swift-tavla/kjor.sh.

    python3 tools/tavla-fixture.py test/fixtures/tavla.json
"""
import json
import sys


def uid(n):
    return "00000000-0000-0000-0000-%012d" % n


club = uid(9000)
course = uid(9001)
par = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
lengths = [360, 380, 150, 500, 340, 400, 170, 390, 520, 370, 160, 410, 510, 350, 330, 180, 420, 540]
names = ["Bjørn", "Lars", "Kåre", "Knut", "Ola", "Per", "Odd", "Thomas"]

members = []
for i, n in enumerate(names):
    members.append({"id": uid(i + 1), "club_id": club, "user_id": None, "display_name": n,
                    "handicap_index": 8 + i * 2 + (0.4 if i % 3 == 0 else 0),
                    "seed_group": (2 if i == 1 else (1 if i == 4 else None)),
                    "is_organizer": i == 0, "is_treasurer": False, "status": "active", "avatar_path": None})
members.append({"id": uid(9), "club_id": club, "user_id": None, "display_name": "Åse", "handicap_index": 24.1,
                "seed_group": None, "is_organizer": False, "is_treasurer": False, "status": "archived", "avatar_path": None})
members.append({"id": uid(10), "club_id": club, "user_id": None, "display_name": "Zorro", "handicap_index": 12,
                "seed_group": None, "is_organizer": False, "is_treasurer": False, "status": "pending", "avatar_path": None})
members.append({"id": uid(11), "club_id": club, "user_id": None, "display_name": "Anders", "handicap_index": None,
                "seed_group": None, "is_organizer": False, "is_treasurer": False, "status": "active", "avatar_path": None})


def strokes(p, r, n=18, start=0):
    return [par[start + h] + (0 if (p * 3 + h * (r + 1)) % 4 == 0 else (h + p + r) % 3)
            - (1 if (p + h + r) % 11 == 0 else 0) for h in range(n)]


events, rounds, round_holes, players, matches, claims, scores = [], [], [], [], [], [], []


def event(n, date):
    events.append({"id": uid(200 + n), "club_id": club, "season_id": uid(9002), "event_date": date,
                   "start_time": "17:00:00", "venue": None, "note": None})
    return uid(200 + n)


def rnd(n, ev, **kw):
    r = {"id": uid(100 + n), "club_id": club, "event_id": ev, "course_id": course, "round_no": 1, "name": None,
         "status": "locked", "hole_count": 18, "first_hole": 1, "tee_time": None, "format": "stableford",
         "handicap_allowance": 1, "external_handicap": False, "weight": 1, "ld_enabled": True, "ld_hole_index": None,
         "kp_enabled": True, "kp_hole_index": None, "cut_rule": None, "cut_after": None, "par_confirmed_by": None,
         "par_confirmed_at": None, "started_at": None, "locked_at": None, "venue": None, "tee_id": None,
         "tee_name": None, "course_rating": None, "slope_rating": None, "tee_par": None}
    r.update(kw)
    rounds.append(r)
    return r["id"]


def player(rid, m, **kw):
    mm = next(x for x in members if x["id"] == m)
    p = {"round_id": rid, "member_id": m, "club_id": club, "handicap_index": mm["handicap_index"],
         "seed_group": mm["seed_group"], "playing_handicap": None, "bay_no": None, "is_marker": False, "team_no": None}
    p.update(kw)
    players.append(p)


def score(rid, m, holes):
    for h, g in holes:
        scores.append({"round_id": rid, "member_id": m, "hole_index": h, "strokes": g,
                       "recorded_at": None, "updated_by": None, "updated_at": None})


def match(rid, no, a=None, b=None, c=None, ta=None, tb=None, result=None):
    matches.append({"round_id": rid, "match_no": no, "player_a": a, "player_b": b, "player_c": c,
                    "team_a": ta, "team_b": tb, "result": result})


def claim(n, rid, m, kind, meters, hole, ts):
    claims.append({"id": uid(300 + n), "round_id": rid, "member_id": m, "kind": kind, "meters": meters,
                   "hole_index": hole, "created_at": ts})


M = [uid(i + 1) for i in range(8)]

# r1: 8 spillere, dueller, LD og KP (likt på KP).
e1 = event(1, "2026-05-14")
r1 = rnd(1, e1, ld_hole_index=6, kp_hole_index=2)
for i, m in enumerate(M):
    player(r1, m, bay_no=i // 4 + 1, is_marker=(i % 4 == 0))
    score(r1, m, list(enumerate(strokes(i, 1))))
for k, i in enumerate(range(0, 8, 2)):
    match(r1, k + 1, a=M[i], b=M[(i + 2) % 8])
claim(1, r1, M[2], "drive", 251.5, 6, "2026-05-14T18:10:00Z")
claim(2, r1, M[5], "drive", 247, 6, "2026-05-14T18:05:00Z")
claim(3, r1, M[1], "kp", 3.2, 2, "2026-05-14T18:20:00Z")
claim(4, r1, M[6], "kp", 3.2, 2, "2026-05-14T18:15:00Z")

# r2: samme kveld som r3. 9 spillere (Åse med), tre dueller og en trekant, manuelle resultater.
e2 = event(2, "2026-05-21")
r2 = rnd(2, e2, format="match", kp_enabled=False)
for i, m in enumerate(M + [uid(9)]):
    player(r2, m)
    score(r2, m, list(enumerate(strokes(i, 2))))
match(r2, 1, a=M[0], b=M[3], result="A")
match(r2, 2, a=M[1], b=M[2])
match(r2, 3, a=M[4], b=M[5], result="halved")
match(r2, 4, a=M[6], b=M[7], c=uid(9))
claim(5, r2, uid(9), "drive", 262, None, "2026-05-21T18:00:00Z")
claim(6, r2, M[3], "kp", 1.5, None, "2026-05-21T18:00:00Z")  # KP er av i runden: teller ikke

# r3: siste ni, fourball med lag, vekt 2, navn med mellomrom rundt.
r3 = rnd(3, e2, round_no=2, hole_count=9, first_hole=10, format="fourball", weight=2, name="  Siste ni  ")
for i, m in enumerate(M):
    player(r3, m, team_no=i // 2 + 1)
    score(r3, m, list(enumerate(strokes(i, 3, 9, 9))))
match(r3, 1, ta=1, tb=2)
match(r3, 2, ta=3, tb=4)

# r4: egne hull (par endret), avkortet felles etter 14, frosset spillehandicap for noen.
e4 = event(4, "2026-05-28")
r4 = rnd(4, e4, cut_rule="common", cut_after=14, handicap_allowance=0.95)
round_holes.append({"round_id": r4, "hole_index": 0, "par": 5, "stroke_index": 7, "length_m": 470})
round_holes.append({"round_id": r4, "hole_index": 6, "par": 4, "stroke_index": 1, "length_m": None})
for i, m in enumerate(M[:6]):
    player(r4, m, playing_handicap=(i * 3 if i % 2 == 0 else None))
    score(r4, m, list(enumerate(strokes(i, 4)))[: (18 if i != 3 else 15)])
match(r4, 1, a=M[0], b=M[1])
match(r4, 2, a=M[2], b=M[3])
match(r4, 3, a=M[4], b=M[5])
claim(7, r4, M[4], "drive", 280, 3, "2026-05-28T18:00:00Z")

# r5: pågår, eget navn, tee med CR, slope og par fra start. Anders (uten indeks) er med.
e5 = event(5, "2026-06-04")
r5 = rnd(5, e5, status="active", name="Finalekveld", course_rating=73.4, slope_rating=131, tee_par=71, tee_name="Gul")
for i, m in enumerate(M[:4] + [uid(11)]):
    player(r5, m)
    score(r5, m, list(enumerate(strokes(i, 5)))[:7])
match(r5, 1, a=M[0], b=M[2])
match(r5, 2, a=M[1], b=M[3])

# r6: kladd (teller ikke).
e6 = event(6, "2026-06-11")
r6 = rnd(6, e6, status="draft")
player(r6, M[0])
score(r6, M[0], [(0, 3)])

# r7: simulatoren deler ut slagene, scramble-2 (ett kort per lag), samme dato som r6.
r7 = rnd(7, e6, round_no=2, external_handicap=True, format="scramble-2", ld_enabled=False)
for i, m in enumerate(M[:4]):
    player(r7, m, team_no=i // 2 + 1)
score(r7, M[0], list(enumerate(strokes(0, 7))))
score(r7, M[2], list(enumerate(strokes(2, 7))))
match(r7, 1, ta=1, tb=2)

courses = [{"id": course, "club_id": club, "name": "Marco Simone", "external_name": None, "course_rating": 72.3,
            "slope_rating": 125, "in_use": True, "confirmed_by": None, "confirmed_at": None}]
si = [7, 3, 15, 1, 11, 5, 17, 9, 13, 8, 16, 2, 12, 6, 14, 18, 4, 10]
course_holes = [{"course_id": course, "hole_number": i + 1, "par": par[i], "stroke_index": si[i],
                 "length_m": lengths[i]} for i in range(18)]

data = {"events": events, "members": members, "rounds": rounds, "round_holes": round_holes, "players": players,
        "matches": matches, "claims": claims, "courses": courses, "course_holes": course_holes, "scores": scores}

golfgutu = {"id": uid(9002), "club_id": club, "name": "Vår 2026", "status": "active", "rules": {"version": 1}}
stableford = {"id": uid(9002), "club_id": club, "name": "Høst 2026", "status": "finished", "rules": {
    "version": 2, "dayTerm": "playingDay",
    "table": {"pointsSource": "stableford", "counting": {"unit": "evening", "best": 3},
              "stablefordCounting": {"unit": "evening", "best": 3}, "tiebreaks": ["stableford"]},
    "sidePrizes": {"longestDrive": {"enabled": True, "points": 1}, "closestToPin": {"enabled": False, "points": 1}},
    "handicap": {"seedingGroups": []}}}
custom = {"id": uid(9002), "club_id": club, "name": "Egen 2026", "status": "planned", "rules": {
    "version": 2, "evenings": 6,
    "table": {"counting": {"unit": "evening", "best": 1}, "roundingStep": None,
              "tiebreaks": ["stableford", "holeDifference"], "matchPoints": {"win": 3, "draw": 1, "loss": 0}},
    "sidePrizes": {"splitTies": False}, "formats": {"matchStrokes": "fullHandicap"}}}

out = {"_kilde": "Laget med tools/tavla-fixture.py etter TavlaSamples.swift, utvidet. Svaret fra RPC-en tavla_data "
                 "(sql/036) og tre sesongrader (Golfgutu, stableford-serie med «spilledag», eget oppsett).",
       "me": uid(8), "tavlaData": data, "sesonger": [golfgutu, stableford, custom]}

with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
    f.write("\n")
