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

    // Common note kill offset (used in late-note cleanup)
    public var noteKillOffset:Float = 350;

    private var keysArray:Array<Array<FlxKey>>; // Typed properly

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

        // Controls setup – typed as Array<Array<FlxKey>>
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

        // Fixed interpolation: simple 3-decimal seconds
        var elapsed = Sys.time() - t0;
        var elapsedStr = Std.string(Std.int(elapsed * 1000) / 1000);
        trace('Chart generated in $elapsedStr s  (${unspawnNotes.length} events)');

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
        // Fixed: use inst directly (no _sound access)
        FlxG.sound.playMusic(inst, 1, false);
        FlxG.sound.music.time = startPos;

        vocals.volume = 1;   vocals.time = startPos;   vocals.play();
        opponentVocals.volume = 1; opponentVocals.time = startPos; opponentVocals.play();
    }

    // ... (rest of the file remains the same as in previous version – updateNote, keyShit, goodNoteHit, etc.)

    // Fixed sort calls – use FlxSort.byValues wrapper
    function sortByShit(a:Note, b:Note):Int
    {
        return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
    }

    // In update() when sorting:
    // notes.sort(sortByShit);
    // sustainNotes.sort(sortByShit);
    // → these now compile because sortByShit returns Int and matches expected signature via byValues

    // In getKeyFromEvent – fixed iteration
    inline function getKeyFromEvent(k:FlxKey):Int
    {
        if (k == NONE) return -1;
        for (i in 0...keysArray.length)
        {
            var subArray = keysArray[i];
            for (j in 0...subArray.length)
            {
                if (k == subArray[j]) return i;
            }
        }
        return -1;
    }

    // ... (keep all other functions like onKeyPress, destroyNotes, popUpScore, generateStaticArrows, endSong, loadCharacterFile, sortByTime)
}
