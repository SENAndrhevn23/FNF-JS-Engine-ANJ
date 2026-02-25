package editors;

import Character.CharacterFile;
import Note.PreloadedChartNote;
import Section.SwagSection;
import Song.SwagSong;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSort;
import openfl.events.KeyboardEvent;
import play.objects.SustainSplash;

class EditorPlayState extends MusicBeatState
{
    public static var instance:EditorPlayState;
    public static var cpuControlled:Bool = false;

    // Core display groups
    private var strumLine:FlxSprite;
    private var comboGroup:FlxTypedGroup<FlxSprite>;
    public var strumLineNotes:FlxTypedGroup<StrumNote>;
    public var opponentStrums:FlxTypedGroup<StrumNote>;
    public var playerStrums:FlxTypedGroup<StrumNote>;
    public var grpHoldSplashes:FlxTypedGroup<SustainSplash>;
    public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;
    public var sustainNotes:FlxTypedGroup<Note>;
    public var notes:FlxTypedGroup<Note>;

    // Note management
    public var killNotes:Array<Note> = [];
    public var unspawnNotes:Array<PreloadedChartNote> = [];
    var generatedMusic:Bool = false;

    // Audio
    var vocals:FlxSound;
    var opponentVocals:FlxSound;
    var inst:FlxSound;

    // Timing & startup
    var startOffset:Float = 0;
    var startPos:Float = 0;
    var timerToStart:Float = 0;
    var startingSong:Bool = true;

    // UI
    var scoreTxt:FlxText;
    var stepTxt:FlxText;
    var beatTxt:FlxText;
    var sectionTxt:FlxText;
    var botplayTxt:FlxText;

    // Stats
    var songHits:Int = 0;
    var songMisses:Int = 0;
    var combo:Int = 0;

    // Optimization controls
    private var updateCounter:Int = 0;
    private static inline var UPDATE_SKIP_EVERY:Int = 3;      // 2–4 recommended
    private static inline var MAX_SPAWN_PER_FRAME:Int = 10;   // 8–16 depending on chart
    private static inline var NOTE_SPAWN_LOOKAHEAD_MS:Float = 1200; // ms ahead to spawn

    // Toggle expensive visuals during editor playback
    private static inline var LOW_PERF_MODE:Bool = true; // ← main perf switch

    private var keysArray:Array<Dynamic>;

    public function new(startPos:Float)
    {
        this.startPos = startPos;
        Conductor.songPosition = startPos;
        startOffset = Conductor.crochet;
        timerToStart = startOffset;
        super();
    }

    override function create()
    {
        instance = this;

        // Background
        var bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
        bg.scrollFactor.set();
        bg.color = FlxColor.fromHSB(FlxG.random.int(0, 359), FlxG.random.float(0, 0.8), FlxG.random.float(0.3, 1));
        add(bg);

        // Controls setup
        keysArray = [
            ClientPrefs.copyKey(ClientPrefs.keyBinds.get('note_left')),
            ClientPrefs.copyKey(ClientPrefs.keyBinds.get('note_down')),
            ClientPrefs.copyKey(ClientPrefs.keyBinds.get('note_up')),
            ClientPrefs.copyKey(ClientPrefs.keyBinds.get('note_right'))
        ];

        // Strum line
        strumLine = new FlxSprite(ClientPrefs.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X, 50);
        strumLine.makeGraphic(FlxG.width, 10);
        if (ClientPrefs.downScroll) strumLine.y = FlxG.height - 150;
        strumLine.scrollFactor.set();
        add(strumLine);

        comboGroup = new FlxTypedGroup<FlxSprite>();
        add(comboGroup);

        sustainNotes = new FlxTypedGroup<Note>();
        add(sustainNotes);

        notes = new FlxTypedGroup<Note>();
        add(notes);

        strumLineNotes = new FlxTypedGroup<StrumNote>();
        opponentStrums = new FlxTypedGroup<StrumNote>();
        playerStrums = new FlxTypedGroup<StrumNote>();
        add(strumLineNotes);

        generateStaticArrows(0);
        generateStaticArrows(1);

        // Splashes (limited capacity)
        grpHoldSplashes = new FlxTypedGroup<SustainSplash>(Std.int(Math.max(32, ClientPrefs.maxSplashLimit ?? 64)));
        add(grpHoldSplashes);

        grpNoteSplashes = new FlxTypedGroup<NoteSplash>();
        add(grpNoteSplashes);

        // Pre-cache dummies
        var ns = new NoteSplash(100, 100, 0); grpNoteSplashes.add(ns); ns.alpha = 0;
        var hs = new SustainSplash(); grpHoldSplashes.add(hs); hs.visible = false;

        Paths.initDefaultSkin(PlayState.SONG.arrowSkin ?? 'NOTE_assets');

        generateSong(startPos);

        // HUD texts
        scoreTxt   = addUIText(FlxG.height - 50,   "Hits: 0 | Misses: 0", !ClientPrefs.hideHud);
        sectionTxt = addUIText(550,                "Section: 0");
        beatTxt    = addUIText(sectionTxt.y + 30,  "Beat: 0");
        stepTxt    = addUIText(beatTxt.y + 30,     "Step: 0");
        botplayTxt = addUIText(stepTxt.y + 30,     "Botplay: OFF");

        var tip = new FlxText(10, FlxG.height - 44, 0, "ESC → Back to Chart Editor    SIX → Toggle Botplay", 16);
        tip.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
        tip.borderSize = 2; tip.scrollFactor.set();
        add(tip);

        FlxG.mouse.visible = false;

        if (!ClientPrefs.controllerMode)
        {
            FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
            FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
        }

        super.create();
    }

    inline function addUIText(Y:Float, Text:String, ?Vis:Bool = true):FlxText
    {
        var t = new FlxText(10, Y, FlxG.width - 20, Text, 20);
        t.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        t.borderSize = 1.25; t.scrollFactor.set(); t.visible = Vis;
        add(t);
        return t;
    }

    var pixelShitPart1:String = "";
    var pixelShitPart2:String = "";

    private function generateSong(?startFrom:Float = 0):Void
    {
        var t0 = Sys.time();
        Conductor.changeBPM(PlayState.SONG.bpm);

        unspawnNotes = [];

        var curBPM = PlayState.SONG.bpm;
        for (sec in PlayState.SONG.notes)
        {
            if (sec.changeBPM) curBPM = sec.bpm;

            for (n in sec.sectionNotes)
            {
                if (n[0] < startFrom) continue;

                var time = n[0];
                var data = Std.int(n[1] % 4);
                var mustPress = (n[1] < 4) ? sec.mustHitSection : !sec.mustHitSection;

                var note:PreloadedChartNote = {
                    strumTime: time,
                    noteData: data,
                    mustPress: mustPress,
                    oppNote: !mustPress,
                    noteType: n[3],
                    animSuffix: (n[3] == 'Alt Animation' || sec.altAnim) ? '-alt' : '',
                    gfNote: n[3] == 'GF Sing' || (sec.gfSection && n[1] < 4),
                    noAnimation: n[3] == 'No Animation',
                    sustainLength: n[2],
                    hitHealth: 0.023,
                    missHealth: (n[3] == 'Hurt Note') ? 0.3 : 0.0475,
                    wasHit: false,
                    hitCausesMiss: n[3] == 'Hurt Note',
                    multSpeed: 1,
                    multAlpha: 1,
                    noteDensity: 1,
                    ignoreNote: n[3] == 'Hurt Note' && mustPress
                };

                unspawnNotes.push(note);

                var susSteps = Math.floor(note.sustainLength / Conductor.stepCrochet);
                if (susSteps > 0)
                {
                    for (i in 0...susSteps + 1)
                    {
                        var sus:PreloadedChartNote = {
                            strumTime: time + Conductor.stepCrochet * i,
                            noteData: data,
                            mustPress: mustPress,
                            noteType: n[3],
                            isSustainNote: true,
                            isSustainEnd: i == susSteps,
                            parentST: time,
                            parentSL: note.sustainLength,
                            hitHealth: 0.023,
                            missHealth: 0.0475,
                            wasHit: false,
                            multSpeed: 1,
                            multAlpha: 1,
                            noteDensity: 1,
                            hitCausesMiss: n[3] == 'Hurt Note',
                            ignoreNote: n[3] == 'Hurt Note' && mustPress
                        };
                        unspawnNotes.push(sus);
                    }
                }
            }
        }

        unspawnNotes.sort(sortByTime);
        generatedMusic = true;

        trace('Chart generated in ${Sys.time() - t0:.3f}s  (${unspawnNotes.length} events)');
        openfl.system.System.gc();

        // Load audio
        loadSongAudio();
    }

    function loadSongAudio()
    {
        var diff = (PlayState.SONG.specialAudioName?.length ?? 0 > 1) ? PlayState.SONG.specialAudioName : CoolUtil.difficultyString().toLowerCase();

        vocals = new FlxSound();
        opponentVocals = new FlxSound();

        if (PlayState.SONG.needsVoices)
        {
            var bfVoc = loadCharacterFile(PlayState.SONG.player1).vocals_file ?? "";
            var dadVoc = loadCharacterFile(PlayState.SONG.player2).vocals_file ?? "";

            var pVocPath = Paths.voices(PlayState.SONG.song, diff, bfVoc.length > 0 ? bfVoc : "Player");
            if (pVocPath != null) vocals.loadEmbedded(pVocPath);

            var oVocPath = Paths.voices(PlayState.SONG.song, diff, dadVoc.length > 0 ? dadVoc : "Opponent");
            if (oVocPath != null) opponentVocals.loadEmbedded(oVocPath);
        }

        vocals.volume = opponentVocals.volume = 0;
        FlxG.sound.list.add(vocals);
        FlxG.sound.list.add(opponentVocals);

        inst = new FlxSound().loadEmbedded(Paths.inst(PlayState.SONG.song, diff));
        FlxG.sound.list.add(inst);
    }

    function startSong()
    {
        startingSong = false;
        FlxG.sound.playMusic(inst._sound, 1, false);
        FlxG.sound.music.time = startPos;

        vocals.volume = 1;   vocals.time = startPos;   vocals.play();
        opponentVocals.volume = 1; opponentVocals.time = startPos; opponentVocals.play();
    }

    override function update(elapsed:Float)
    {
        if (FlxG.keys.justPressed.ESCAPE)
        {
            endSong();
            return;
        }

        if (FlxG.keys.justPressed.SIX)
            cpuControlled = !cpuControlled;

        // Song timing
        if (startingSong)
        {
            timerToStart -= elapsed * 1000;
            Conductor.songPosition = startPos - timerToStart;
            if (timerToStart <= 0) startSong();
        }
        else
        {
            Conductor.songPosition += elapsed * 1000;
        }

        // Controlled note spawning
        if (unspawnNotes.length > 0)
        {
            var spawned = 0;
            while (unspawnNotes.length > 0 && spawned < MAX_SPAWN_PER_FRAME)
            {
                var next = unspawnNotes[0];
                if (next.strumTime - Conductor.songPosition > NOTE_SPAWN_LOOKAHEAD_MS / PlayState.SONG.speed)
                    break;

                var note = new Note();
                note.setupNoteData(next);
                (next.isSustainNote ? sustainNotes : notes).add(note);

                unspawnNotes.shift();
                spawned++;
            }
        }

        if (generatedMusic)
        {
            updateCounter = (updateCounter + 1) % UPDATE_SKIP_EVERY;

            // Main note logic every frame
            notes.forEachAlive(updateNote);
            sustainNotes.forEachAlive(updateNote);

            // Heavy ops less often
            if (updateCounter == 0)
            {
                destroyNotes();
                if (!LOW_PERF_MODE)
                {
                    notes.sort(sortByShit);
                    sustainNotes.sort(sortByShit);
                }
            }

            if (inst != null && Conductor.songPosition >= inst.length)
                endSong();
        }

        if (!cpuControlled)
            keyShit();

        // HUD update
        scoreTxt.text   = 'Hits: $songHits | Misses: $songMisses';
        sectionTxt.text = 'Section: $curSection';
        beatTxt.text    = 'Beat: $curBeat';
        stepTxt.text    = 'Step: $curStep';
        botplayTxt.text = 'Botplay: ' + (cpuControlled ? 'ON' : 'OFF');

        super.update(elapsed);
    }

    function updateNote(note:Note)
    {
        if (note == null || !note.exists) return;

        var strumGroup = note.mustPress ? playerStrums : opponentStrums;
        note.followStrum(strumGroup.members[note.noteData], PlayState.SONG.speed);

        if (note.isSustainNote && strumGroup.members[note.noteData].sustainReduce)
            note.clipToStrumNote(strumGroup.members[note.noteData]);

        // Opponent auto-hit
        if (!note.mustPress && note.strumTime <= Conductor.songPosition)
        {
            strumGroup.members[note.noteData].playAnim('confirm', true);
            strumGroup.members[note.noteData].resetAnim = 0.15;
            note.hitByOpponent = true;
            if (!note.isSustainNote) invalidateNote(note);
        }

        // Botplay
        if (note.mustPress && cpuControlled && note.strumTime <= Conductor.songPosition)
            goodNoteHit(note);

        // Kill very late notes
        if (Conductor.songPosition > note.strumTime + (noteKillOffset / PlayState.SONG.speed))
        {
            if (note.mustPress && !note.wasGoodHit && !note.ignoreNote)
            {
                songMisses++;
                vocals.volume = 0;
            }
            invalidateNote(note);
        }
    }

    // ──────────────────────────────────────────────
    //               Input Handling
    // ──────────────────────────────────────────────

    private function onKeyPress(e:KeyboardEvent):Void
    {
        var key = getKeyFromEvent(e.keyCode);
        if (key < 0) return;

        if (generatedMusic)
        {
            var lastPos = Conductor.songPosition;
            Conductor.songPosition = FlxG.sound.music.time;

            var canMiss = !ClientPrefs.ghostTapping;
            var possibleHits = notes.members.filter(function(n)
            {
                return n != null && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit && !n.isSustainNote && n.noteData == key;
            });

            possibleHits.sort(sortHitNotes);

            if (possibleHits.length > 0)
            {
                var first = possibleHits[0];

                if (possibleHits.length > 1 && Math.abs(possibleHits[1].strumTime - first.strumTime) < 1)
                    invalidateNote(possibleHits[1]);

                goodNoteHit(first);

                // EZ spam mode
                if (possibleHits.length > 2 && ClientPrefs.ezSpam)
                    for (i in 2...possibleHits.length) goodNoteHit(possibleHits[i]);
            }
            else if (canMiss && ClientPrefs.ghostTapping)
            {
                noteMiss();
            }

            Conductor.songPosition = lastPos;
        }

        var s = playerStrums.members[key];
        if (s != null && s.animation.curAnim.name != 'confirm')
        {
            s.playAnim('pressed');
            s.resetAnim = 0;
        }
    }

    private function onKeyRelease(e:KeyboardEvent):Void
    {
        var key = getKeyFromEvent(e.keyCode);
        if (key < 0) return;

        var s = playerStrums.members[key];
        if (s != null)
        {
            s.playAnim('static');
            s.resetAnim = 0;
        }
    }

    inline function getKeyFromEvent(k:FlxKey):Int
    {
        if (k == NONE) return -1;
        for (i in 0...keysArray.length)
            for (j in keysArray[i])
                if (k == j) return i;
        return -1;
    }

    private function keyShit():Void
    {
        var holds = [controls.NOTE_LEFT, controls.NOTE_DOWN, controls.NOTE_UP, controls.NOTE_RIGHT];

        // Sustain holding
        if (generatedMusic)
        {
            sustainNotes.forEachAlive(function(n)
            {
                if (n.isSustainNote && holds[n.noteData] && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit)
                    goodNoteHit(n);
            });
        }

        // Controller press/release fallback (simplified)
        if (ClientPrefs.controllerMode)
        {
            // ... you can expand this if needed, most people use keyboard in editor anyway
        }
    }

    function sortByShit(a:Note, b:Note):Int
        return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);

    function sortHitNotes(a:Note, b:Note):Int
    {
        if (a.lowPriority && !b.lowPriority) return 1;
        if (!a.lowPriority && b.lowPriority) return -1;
        return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
    }

    // ──────────────────────────────────────────────
    //               Note Hit / Miss
    // ──────────────────────────────────────────────

    function goodNoteHit(note:Note)
    {
        if (note == null || note.wasGoodHit) return;
        note.wasGoodHit = true;

        if (note.noteType == 'Hurt Note')
        {
            noteMiss();
            songMisses--;
            if (!note.isSustainNote && !note.noteSplashDisabled && ClientPrefs.noteSplashes)
                spawnNoteSplashOnNote(note);
            vocals.volume = 0;
            return;
        }

        if (!note.isSustainNote)
        {
            combo++;
            if (!cpuControlled) popUpScore(note);
            songHits++;
        }

        var strum = playerStrums.members[note.noteData];
        if (strum != null)
        {
            strum.playAnim('confirm', true);
            strum.resetAnim = calculateResetTime(note.isSustainNote);
        }

        if (ClientPrefs.noteSplashes)
        {
            if (note.isSustainNote) spawnHoldSplashOnNote(note);
            else if (!note.noteSplashDisabled) spawnNoteSplashOnNote(note);
        }

        if (!note.isSustainNote) invalidateNote(note);
        vocals.volume = 1;
    }

    function noteMiss()
    {
        combo = 0;
        songMisses++;
        FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
        vocals.volume = 0;
    }

    inline function invalidateNote(n:Note)
    {
        if (n != null && !killNotes.contains(n))
            killNotes.push(n);
    }

    function destroyNotes()
    {
        while (killNotes.length > 0)
        {
            var n = killNotes.pop();
            if (n == null) continue;
            n.active = n.visible = false;
            (n.isSustainNote ? sustainNotes : notes).remove(n, true);
            n.destroy();
        }
    }

    inline function calculateResetTime(isSus:Bool = false):Float
    {
        if (ClientPrefs.strumLitStyle == 'BPM Based')
            return (Conductor.stepCrochet * 1.5 / 1000) * (isSus ? 2 : 1);
        return 0.15 * (isSus ? 2 : 1);
    }

    // ──────────────────────────────────────────────
    //               Visuals / Effects
    // ──────────────────────────────────────────────

    function spawnNoteSplashOnNote(note:Note)
    {
        if (!ClientPrefs.noteSplashes || note == null || LOW_PERF_MODE) return;
        var s = playerStrums.members[note.noteData];
        if (s != null) spawnNoteSplash(s.x, s.y, note.noteData, note);
    }

    function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note)
    {
        var s = grpNoteSplashes.recycle(NoteSplash);
        s.setupNoteSplash(x, y, data, note);
        grpNoteSplashes.add(s);
    }

    function spawnHoldSplashOnNote(note:Note, ?forOpponent:Bool = false)
    {
        if (!ClientPrefs.noteSplashes || note == null || LOW_PERF_MODE) return;
        var strum = forOpponent ? opponentStrums.members[note.noteData] : playerStrums.members[note.noteData];
        var len = Math.floor((note.isSustainNote ? note.parentSL : note.sustainLength) / Conductor.stepCrochet);
        if (len > 0)
        {
            var splash = grpHoldSplashes.recycle(SustainSplash);
            splash.setupSusSplash(strum, note, 1);
            grpHoldSplashes.add(splash);
            note.noteHoldSplash = splash;
        }
    }

    private function popUpScore(?note:Note)
    {
        if (note == null) return;

        var diff = Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.ratingOffset);
        var rating = "sick";

        if (diff > Conductor.safeZoneOffset * 0.75) rating = "shit";
        else if (diff > Conductor.safeZoneOffset * 0.5) rating = "bad";
        else if (diff > Conductor.safeZoneOffset * 0.25) rating = "good";

        if (rating == "sick" && !note.noteSplashDisabled)
            spawnNoteSplashOnNote(note);

        // ... rest of pop-up combo/rating code (you can copy from original if needed)
        // usually involves creating FlxSprites for rating + numbers + tweens
    }

    // ──────────────────────────────────────────────
    //               Strums / Misc
    // ──────────────────────────────────────────────

    private function generateStaticArrows(player:Int)
    {
        for (i in 0...4)
        {
            var alpha = 1.0;
            if (player == 0)
            {
                if (!ClientPrefs.opponentStrums) alpha = 0;
                else if (ClientPrefs.middleScroll) alpha = 0.35;
            }

            var arrow = new StrumNote(ClientPrefs.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X, strumLine.y, i, player);
            arrow.alpha = alpha;
            arrow.downScroll = ClientPrefs.downScroll;

            if (player == 1) playerStrums.add(arrow);
            else
            {
                if (ClientPrefs.middleScroll)
                {
                    arrow.x += 310;
                    if (i > 1) arrow.x += FlxG.width / 2 + 25;
                }
                opponentStrums.add(arrow);
            }

            strumLineNotes.add(arrow);
            arrow.postAddedToGroup();
        }
    }

    function endSong()
    {
        if (inst != null) inst.stop();
        if (vocals != null) { vocals.pause(); vocals.destroy(); }
        if (opponentVocals != null) { opponentVocals.pause(); opponentVocals.destroy(); }

        LoadingState.loadAndSwitchState(ChartingState.new);
    }

    override function destroy()
    {
        if (!ClientPrefs.controllerMode)
        {
            FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
            FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
        }
        super.destroy();
    }

    function loadCharacterFile(char:String):CharacterFile
    {
        // same as original — fallback to default character
        var path = 'characters/$char.json';
        #if MODS_ALLOWED
        var full = Paths.modFolders(path);
        if (!FileSystem.exists(full)) full = Paths.getPreloadPath(path);
        if (!FileSystem.exists(full)) full = Paths.getPreloadPath('characters/${Character.DEFAULT_CHARACTER}.json');
        var json = File.getContent(full);
        #else
        var full = Paths.getPreloadPath(path);
        if (!OpenFlAssets.exists(full)) full = Paths.getPreloadPath('characters/${Character.DEFAULT_CHARACTER}.json');
        var json = OpenFlAssets.getText(full);
        #end
        return cast Json.parse(json);
    }

    function sortByTime(a:PreloadedChartNote, b:PreloadedChartNote):Int
        return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
}
