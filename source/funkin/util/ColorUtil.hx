package funkin.util;

import flixel.util.FlxColor;
import openfl.display.BitmapData;

/**
 * Utilities for working with colors.
 */
class ColorUtil
{
  /**
   * Pixels that are more transparent than this are ignored when looking for a dominant color.
   */
  static final MIN_ALPHA:Int = 128;

  /**
   * Pixels darker than this (outlines, shadows) are ignored when looking for a dominant color.
   */
  static final MIN_BRIGHTNESS:Float = 0.2;

  /**
   * Pixels less saturated than this (whites, grays) are ignored when looking for a dominant color.
   */
  static final MIN_SATURATION:Float = 0.25;

  /**
   * The dominant color is brightened to at least this value, so it stays visible on dark backgrounds.
   */
  static final MIN_RESULT_BRIGHTNESS:Float = 0.55;

  /**
   * The number of buckets used to group similar colors (4 bits per channel).
   */
  static final BUCKET_COUNT:Int = 4096;

  /**
   * Finds the most prominent color in a bitmap.
   * Transparent, dark and gray pixels are ignored, so outlines and highlights do not win over the actual color of the image.
   * @param bitmap The bitmap to look at.
   * @param fallback The color to return if the bitmap has no usable pixels.
   * @return The dominant color, fully opaque.
   */
  public static function getDominantColor(bitmap:Null<BitmapData>, fallback:FlxColor):FlxColor
  {
    if (bitmap == null || bitmap.width == 0 || bitmap.height == 0) return fallback;

    var weights:Array<Float> = [for (_ in 0...BUCKET_COUNT) 0.0];
    var sumRed:Array<Float> = [for (_ in 0...BUCKET_COUNT) 0.0];
    var sumGreen:Array<Float> = [for (_ in 0...BUCKET_COUNT) 0.0];
    var sumBlue:Array<Float> = [for (_ in 0...BUCKET_COUNT) 0.0];

    for (y in 0...bitmap.height)
    {
      for (x in 0...bitmap.width)
      {
        var pixel:FlxColor = bitmap.getPixel32(x, y);
        if (pixel.alpha < MIN_ALPHA) continue;
        if (pixel.brightness < MIN_BRIGHTNESS || pixel.saturation < MIN_SATURATION) continue;

        var bucket:Int = ((pixel.red >> 4) << 8) | ((pixel.green >> 4) << 4) | (pixel.blue >> 4);
        var weight:Float = pixel.saturation * pixel.brightness;

        weights[bucket] += weight;
        sumRed[bucket] += pixel.red * weight;
        sumGreen[bucket] += pixel.green * weight;
        sumBlue[bucket] += pixel.blue * weight;
      }
    }

    var best:Int = -1;
    for (bucket in 0...BUCKET_COUNT)
    {
      if (weights[bucket] > 0 && (best == -1 || weights[bucket] > weights[best])) best = bucket;
    }

    if (best == -1) return fallback;

    var result:FlxColor = FlxColor.fromRGB(Std.int(sumRed[best] / weights[best]), Std.int(sumGreen[best] / weights[best]),
      Std.int(sumBlue[best] / weights[best]));
    if (result.brightness < MIN_RESULT_BRIGHTNESS) result.brightness = MIN_RESULT_BRIGHTNESS;
    return result;
  }

  /**
   * Converts a value from JSON or a script into a color.
   * @param value An `Int` color, or a `String` such as `"#31B0D1"`, `"0xFF31B0D1"` or `"red"`.
   * @return The color, or `null` if the value could not be understood.
   */
  public static function parse(value:Dynamic):Null<FlxColor>
  {
    if (value == null) return null;
    if (Std.isOfType(value, Int)) return FlxColor.fromInt(value);
    if (Std.isOfType(value, String)) return FlxColor.fromString(value);
    return null;
  }

  /**
   * Returns how different two colors are, from `0.0` (identical) to `1.0` (black versus white).
   */
  public static function distance(a:FlxColor, b:FlxColor):Float
  {
    var dr:Float = a.red - b.red;
    var dg:Float = a.green - b.green;
    var db:Float = a.blue - b.blue;
    return Math.sqrt(dr * dr + dg * dg + db * db) / 441.6729559;
  }

  /**
   * Makes a color darker.
   * @param amount How much darker, from `0.0` (unchanged) to `1.0` (black).
   */
  public static function darken(color:FlxColor, amount:Float = 0.2):FlxColor
  {
    var result:FlxColor = color;
    result.brightness = result.brightness * (1.0 - amount);
    return result;
  }

  /**
   * Makes a color lighter.
   * @param amount How much lighter, from `0.0` (unchanged) to `1.0` (white).
   */
  public static function lighten(color:FlxColor, amount:Float = 0.2):FlxColor
  {
    var result:FlxColor = color;
    result.lightness = result.lightness + (1.0 - result.lightness) * amount;
    return result;
  }

  /**
   * Makes sure two colors are different enough to tell apart, by darkening the second one if needed.
   * Used so the two sides of the health bar never blend together.
   * @param minDistance The smallest accepted `distance` between both colors.
   */
  public static function ensureContrast(a:FlxColor, b:FlxColor, minDistance:Float = 0.2):FlxColor
  {
    var result:FlxColor = b;
    var attempts:Int = 0;
    while (distance(a, result) < minDistance && attempts < 4)
    {
      result = (a.brightness > 0.5) ? darken(result, 0.3) : lighten(result, 0.3);
      attempts++;
    }
    return result;
  }
}
