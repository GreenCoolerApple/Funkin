package funkin.ui.options;

import funkin.ui.Page.PageName;
import funkin.ui.transition.LoadingState;
import funkin.ui.TextMenuList;
import funkin.ui.TextMenuList.TextMenuItem;
import flixel.math.FlxPoint;
import funkin.ui.TextMenuList;
import funkin.ui.TextMenuList.TextMenuItem;
import flixel.FlxSprite;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.group.FlxGroup;
import flixel.util.FlxSignal;
import funkin.audio.FunkinSound;
import funkin.ui.mainmenu.MainMenuState;
import funkin.ui.MusicBeatState;
import funkin.graphics.shaders.HSVShader;
import funkin.input.Controls;
#if FEATURE_NEWGROUNDS
#end
#if mobile
import funkin.util.TouchUtil;
import funkin.mobile.ui.FunkinBackButton;
import funkin.mobile.input.ControlsHandler;
import funkin.mobile.ui.options.ControlsSchemeMenu;
#end
#if FEATURE_MOBILE_IAP
import funkin.mobile.util.InAppPurchasesUtil;
#end
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;

/**
 * The main options menu
 * It mainly is controlled via the "optionsCodex" object,
 * which handles paging and going to the different submenus
 */
class OptionsState extends MusicBeatState
{
  /**
   * Instance of the OptionsState
   */
  public static var instance:OptionsState;

  var optionsCodex:Codex<OptionsMenuPageName>;

  public var drumsBG:FunkinSound;

  public static var rememberedSelectedIndex:Int = 0;

  override function create():Void
  {
    instance = this;

    persistentUpdate = true;

    drumsBG = FunkinSound.load(Paths.music('offsetsLoop/drumsLoop'), 0, true, false, false, false);

    var menuBG = new FlxSprite().loadGraphic(Paths.image('menuBG'));
    var hsv = new HSVShader(-0.6, 0.9, 3.6);
    menuBG.shader = hsv;
    menuBG.setGraphicSize(Std.int(FlxG.width * 1.1));
    menuBG.updateHitbox();
    menuBG.screenCenter();
    menuBG.scrollFactor.set(0, 0);
    add(menuBG);

    optionsCodex = new Codex<OptionsMenuPageName>(Options);
    add(optionsCodex);

    var options:OptionsMenu = optionsCodex.addPage(Options, new OptionsMenu());
    var preferences:PreferencesMenu = optionsCodex.addPage(Preferences, new PreferencesMenu());
    var controls:ControlsMenu = optionsCodex.addPage(Controls, new ControlsMenu());
    #if FEATURE_LAG_ADJUSTMENT
    var offsets:OffsetMenu = optionsCodex.addPage(Offsets, new OffsetMenu());
    #end
    var saveData:SaveDataMenu = optionsCodex.addPage(SaveData, new SaveDataMenu());

    options.addSaveDataOptionsItem(saveData);
    options.addExitItem();

    if (options.hasMultipleOptions())
    {
      options.onExit.add(exitToMainMenu);
      controls.onExit.add(exitControls);
      preferences.onExit.add(optionsCodex.switchPage.bind(Options));
      #if FEATURE_LAG_ADJUSTMENT
      offsets.onExit.add(exitOffsets);
      #end
      saveData.onExit.add(optionsCodex.switchPage.bind(Options));
    }
    else
    {
      // No need to show Options page
      #if mobile
      preferences.onExit.add(exitToMainMenu);
      optionsCodex.setPage(Preferences);
      #else
      controls.onExit.add(exitToMainMenu);
      optionsCodex.setPage(Controls);
      #end
    }

    super.create();
    #if mobile
    addHitbox();
    hitbox.visible = false;
    #end
  }

  function exitOffsets():Void
  {
    if (drumsBG.volume > 0)
    {
      drumsBG.fadeOut(0.5, 0);
    }
    FlxG.sound.music.fadeOut(0.5, 0, function(tw)
    {
      FunkinSound.playMusic('freakyMenu', {
        startingVolume: 0,
        overrideExisting: true,
        restartTrack: true,
        persist: true
      });
      FlxG.sound.music.fadeIn(0.5, 1);
    });
    optionsCodex.switchPage(Options);
  }

  function exitControls():Void
  {
    // Apply any changes to the controls.
    PlayerSettings.reset();
    PlayerSettings.init();

    optionsCodex.switchPage(Options);
  }

  function exitToMainMenu():Void
  {
    optionsCodex.currentPage.enabled = false;
    // TODO: Animate this transition?
    FlxG.keys.enabled = false;
    FlxG.switchState(() -> new MainMenuState());
  }
}

/**
 * Our default Page when we enter the OptionsState, a bit of the root
 */
class OptionsMenu extends Page<OptionsMenuPageName>
{
  var items:TextMenuList;
  #if FEATURE_TOUCH_CONTROLS
  var backButton:FunkinBackButton;
  var goingBack:Bool = false;
  #end

  /**
   * Camera focus point
   */
  var camFocusPoint:FlxObject;

  final CAMERA_MARGIN:Int = 150;

  public function new()
  {
    super();
    add(items = new TextMenuList());
    items.onAcceptPress.add(playConfirmAnimation);

    createItem('PREFERENCES', function() codex.switchPage(Preferences));
    #if mobile
    if (ControlsHandler.hasExternalInputDevice)
    #end
    createItem('CONTROLS', function() codex.switchPage(Controls));
    // createItem("CONTROL SCHEMES", function() {
    //   FlxG.state.openSubState(new ControlsSchemeMenu());
    // });
    #if FEATURE_LAG_ADJUSTMENT
    createItem('LAG ADJUSTMENT', function()
    {
      var switchToOffsets = function()
      {
        FunkinSound.playMusic('offsetsLoop', {
          startingVolume: 0,
          overrideExisting: true,
          restartTrack: true,
          loop: true
        });
        OptionsState.instance.drumsBG.play(true);
        FlxG.sound.music.fadeIn(1, 1);
        codex.switchPage(Offsets);
      };

      if (FlxG.sound.music != null)
      {
        FlxG.sound.music.fadeOut(0.5, 0, function(tw)
        {
          switchToOffsets();
        });
      }
      else
      {
        switchToOffsets();
      }
    });
    #end
    #if FEATURE_MOBILE_IAP
    createItem('RESTORE PURCHASES', function()
    {
      InAppPurchasesUtil.restorePurchases();
    });
    #end
    #if android
    createItem('OPEN DATA FOLDER', function()
    {
      funkin.external.android.DataFolderUtil.openDataFolder();
    });
    #end
    // Create an object for the camera to track.
    camFocusPoint = new FlxObject(0, 0, 140, 70);
    add(camFocusPoint);

    // Follow the camera focus as we scroll.
    FlxG.camera.follow(camFocusPoint, null, 0.085);
    FlxG.camera.deadzone.set(0, CAMERA_MARGIN / 2, FlxG.camera.width, FlxG.camera.height - CAMERA_MARGIN + 40);
    FlxG.camera.minScrollY = -CAMERA_MARGIN / 2;

    // Move the camera when the menu is scrolled.
    items.onChange.add(onMenuChange);

    onMenuChange(items.members[0]);

    items.selectItem(OptionsState.rememberedSelectedIndex);
    #if FEATURE_TOUCH_CONTROLS
    FlxG.touches.swipeThreshold.y = 100;
    #end
  }

  public function addSaveDataOptionsItem(saveDataMenu:SaveDataMenu):Void
  {
    // no need to show an entire new menu for just one option
    if (saveDataMenu.hasMultipleOptions())
    {
      createItem('SAVE DATA OPTIONS', function()
      {
        codex.switchPage(SaveData);
      });
    }
    else
    {
      createItem('CLEAR SAVE DATA', saveDataMenu.openSaveDataPrompt);
    }
  }

  public function addExitItem():Void
  {
    #if NO_FEATURE_TOUCH_CONTROLS
    createItem('EXIT', exit);
    #else
    backButton = new FunkinBackButton(FlxG.width - 230, FlxG.height - 200, exit, 1.0);
    backButton.onConfirmStart.add(function()
    {
      items.busy = true;
      goingBack = true;
      backButton.active = true;
    });
    add(backButton);
    #end
  }

  function onMenuChange(selected:TextMenuItem):Void
  {
    camFocusPoint.y = selected.y;
  }

  /**
   * Whether the confirm animation is playing, or has played and still has to be undone.
   */
  var confirming:Bool = false;

  /**
   * The camera zoom before the confirm animation started, so it can be restored.
   */
  var confirmBaseZoom:Float = 1.0;

  /**
   * Plays the animation of choosing an option: the other options fade out,
   * the screen flashes and the camera zooms in a little.
   */
  function playConfirmAnimation(selected:TextMenuItem):Void
  {
    // Items that open instantly have no time for an animation.
    if (selected.fireInstantly) return;

    confirming = true;
    confirmBaseZoom = FlxG.camera.zoom;

    for (item in items.members)
    {
      if (item != selected) FlxTween.tween(item, {alpha: 0.0}, 0.3, {ease: FlxEase.quadOut});
    }

    // A quick flash, if flashing lights are allowed, and a camera bump that settles back before the next page opens.
    if (funkin.Preferences.flashingLights) FlxG.camera.flash(FlxColor.WHITE, 0.3);
    FlxTween.tween(FlxG.camera, {zoom: confirmBaseZoom * 1.06}, 0.12, {
      ease: FlxEase.quadOut,
      onComplete: _ -> FlxTween.tween(FlxG.camera, {zoom: confirmBaseZoom}, 0.7, {ease: FlxEase.sineOut})
    });
  }

  /**
   * Undoes the confirm animation, for when this page is shown again after choosing an option that opens another page.
   */
  function resetConfirmAnimation():Void
  {
    confirming = false;

    FlxTween.cancelTweensOf(FlxG.camera, ['zoom']);
    FlxG.camera.zoom = confirmBaseZoom;

    for (i in 0...items.members.length)
    {
      final item:TextMenuItem = items.members[i];
      FlxTween.cancelTweensOf(item, ['alpha']);
      // The selected item is fully visible and the others are dimmed, same as in `MenuListItem`.
      item.alpha = (i == items.selectedIndex) ? 1.0 : 0.6;
    }
  }

  function createItem(name:String, callback:Void->Void, fireInstantly = false):TextMenuItem
  {
    var item = items.createItem(0, 100 + items.length * 100, name, BOLD, callback);
    item.fireInstantly = fireInstantly;
    item.screenCenter(X);
    return item;
  }

  override function update(elapsed:Float):Void
  {
    if ((FlxG.sound.music?.volume ?? 1.0) < 0.8)
    {
      FlxG.sound.music.volume += 0.5 * elapsed;
    }

    #if FEATURE_TOUCH_CONTROLS
    backButton.active = (!goingBack) ? !items.busy : true;
    #end

    // The page stops updating while another page is shown, so this is reached again once this one is back.
    if (confirming && !items.busy) resetConfirmAnimation();

    super.update(elapsed);
  }

  override function set_enabled(value:Bool):Bool
  {
    items.enabled = value;
    return super.set_enabled(value);
  }

  /**
   * True if this page has multiple options, excluding the exit option.
   * If false, there's no reason to ever show this page.
   */
  public function hasMultipleOptions():Bool
  {
    return items.length > 2;
  }
}

enum abstract OptionsMenuPageName(String) to PageName
{
  public var Options = 'options';
  public var Controls = 'controls';
  public var Colors = 'colors';
  public var Mods = 'mods';
  public var Preferences = 'preferences';
  public var Offsets = 'offsets';
  public var SaveData = 'saveData';
}
