package funkin.util;

import flixel.tweens.FlxEase;
import flixel.tweens.FlxEase.EaseFunction;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.play.PlayState;

/**
 * Shortcuts for scripts, so common things do not need extra imports.
 * Available in every script as `ScriptUtil`.
 *
 * Anywhere a color is expected, scripts can pass an `Int` (`0xFF31B0D1`),
 * or a `String` (`"#31B0D1"`, `"0xFF31B0D1"` or `"red"`).
 */
class ScriptUtil
{
  ///// COLORS /////

  /**
   * Converts a hex string, color name or `Int` into a color.
   * Returns white if the value cannot be understood.
   */
  public static function color(value:Dynamic):FlxColor
  {
    return ColorUtil.parse(value) ?? FlxColor.WHITE;
  }

  /**
   * Blends two colors.
   * @param t How far to go from `a` to `b`, from `0.0` to `1.0`.
   */
  public static function lerpColor(a:Dynamic, b:Dynamic, t:Float):FlxColor
  {
    return FlxColor.interpolate(color(a), color(b), clamp(t, 0.0, 1.0));
  }

  /**
   * Makes a color darker. `amount` goes from `0.0` (unchanged) to `1.0` (black).
   */
  public static function darken(value:Dynamic, amount:Float = 0.2):FlxColor
  {
    return ColorUtil.darken(color(value), amount);
  }

  /**
   * Makes a color lighter. `amount` goes from `0.0` (unchanged) to `1.0` (white).
   */
  public static function lighten(value:Dynamic, amount:Float = 0.2):FlxColor
  {
    return ColorUtil.lighten(color(value), amount);
  }

  /**
   * Changes the opacity of a color. `alpha` goes from `0.0` (invisible) to `1.0` (opaque).
   */
  public static function withAlpha(value:Dynamic, alpha:Float):FlxColor
  {
    var result:FlxColor = color(value);
    result.alphaFloat = clamp(alpha, 0.0, 1.0);
    return result;
  }

  ///// TWEENS /////

  /**
   * Tweens the properties of an object.
   * For example: `ScriptUtil.tween(sprite, {x: 100, alpha: 0.5}, 1.0, "quadOut")`.
   * @param ease The name of an ease from `FlxEase`, such as `"quadOut"` or `"elasticOut"`. Defaults to linear.
   * @param onComplete Called when the tween finishes.
   */
  public static function tween(target:Dynamic, properties:Dynamic, duration:Float, ?ease:String, ?onComplete:Void->Void):FlxTween
  {
    return FlxTween.tween(target, properties, duration, {
      ease: getEase(ease),
      onComplete: (_) -> if (onComplete != null) onComplete()
    });
  }

  /**
   * Gets an ease function from its name in `FlxEase`. Unknown names give a linear ease.
   */
  public static function getEase(name:Null<String>):EaseFunction
  {
    return switch (name)
    {
      case 'quadIn': FlxEase.quadIn;
      case 'quadOut': FlxEase.quadOut;
      case 'quadInOut': FlxEase.quadInOut;
      case 'cubeIn': FlxEase.cubeIn;
      case 'cubeOut': FlxEase.cubeOut;
      case 'cubeInOut': FlxEase.cubeInOut;
      case 'sineIn': FlxEase.sineIn;
      case 'sineOut': FlxEase.sineOut;
      case 'sineInOut': FlxEase.sineInOut;
      case 'expoIn': FlxEase.expoIn;
      case 'expoOut': FlxEase.expoOut;
      case 'expoInOut': FlxEase.expoInOut;
      case 'backIn': FlxEase.backIn;
      case 'backOut': FlxEase.backOut;
      case 'backInOut': FlxEase.backInOut;
      case 'bounceIn': FlxEase.bounceIn;
      case 'bounceOut': FlxEase.bounceOut;
      case 'bounceInOut': FlxEase.bounceInOut;
      case 'elasticIn': FlxEase.elasticIn;
      case 'elasticOut': FlxEase.elasticOut;
      case 'elasticInOut': FlxEase.elasticInOut;
      default: FlxEase.linear;
    }
  }

  ///// HEALTH BAR /////

  /**
   * Sets the colors of the health bar during a song.
   * @param opponent The color of the opponent's side (the left side).
   * @param player The color of the player's side (the right side).
   * @param duration If more than `0`, the colors fade over this many seconds instead of changing instantly.
   */
  public static function setHealthBarColors(opponent:Dynamic, player:Dynamic, duration:Float = 0.0):Void
  {
    final playState:Null<PlayState> = PlayState.instance;
    if (playState == null) return;

    if (duration > 0.0) playState.tweenHealthBarColors(color(opponent), color(player), duration);
    else
      playState.setHealthBarColors(color(opponent), color(player));
  }

  /**
   * Sets the health bar back to the colors of the characters' health icons.
   */
  public static function resetHealthBarColors():Void
  {
    PlayState.instance?.resetHealthBarColors();
  }

  ///// MATH /////

  /**
   * Limits a value to the range from `min` to `max`.
   */
  public static function clamp(value:Float, min:Float, max:Float):Float
  {
    return Math.max(min, Math.min(max, value));
  }

  /**
   * Goes from `a` to `b`. `t` is how far to go, from `0.0` to `1.0`.
   */
  public static function lerp(a:Float, b:Float, t:Float):Float
  {
    return a + (b - a) * t;
  }

  /**
   * A random decimal number from `min` up to `max`.
   */
  public static function randomFloat(min:Float, max:Float):Float
  {
    return min + Math.random() * (max - min);
  }

  /**
   * A random whole number from `min` to `max`, both included.
   */
  public static function randomInt(min:Int, max:Int):Int
  {
    return min + Math.floor(Math.random() * (max - min + 1));
  }
}
