#if !macro
import Paths;

#if sys
import sys.*;
import sys.io.*;
#end

// LUA is generally not supported on HTML5 in FNF engines 
// because it relies on C++ (hxluajit/cpp package).
#if (LUA_ALLOWED && !html5)
    import hxluajit.*;
    import hxluajit.Types;
    import psychlua.*;
#elseif !html5
    // This branch handles cases where LUA_ALLOWED might be false 
    // but the files are still imported for desktop.
    import psychlua.FunkinLua; 
    import psychlua.HScript;
#else
    // HTML5 BRANCH: Skip FunkinLua/Lua entirely to avoid the C++ Pointer error.
    import psychlua.HScript;
#end

#if flxanimate
import flxanimate.*;
import flxanimate.PsychFlxAnimate as FlxAnimate;
#end

#if MODS_ALLOWED
import backend.Mods;
#end

//so that it doesn't bring up a "Type not found: Countdown"
import BaseStage.Countdown;

//Flixel
import flixel.sound.FlxSound;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxTypedGroup;
import flixel.util.FlxDestroyUtil;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxSubState;
import flixel.addons.display.FlxGridOverlay;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.FlxObject;
import flixel.util.FlxSave;
import flixel.util.FlxStringUtil;

//others
import openfl.display.BitmapData;
import openfl.net.FileFilter;
import openfl.geom.Rectangle;
import openfl.utils.Assets as OpenFlAssets;
import lime.utils.Assets;
import haxe.Json;

// utils
import utils.*;

using StringTools;
#end
