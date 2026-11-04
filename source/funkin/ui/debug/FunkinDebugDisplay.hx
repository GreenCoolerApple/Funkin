package funkin.ui.debug;

import flixel.util.FlxStringUtil;
import funkin.ui.debug.stats.FunkinStatsGraph;
import funkin.util.MemoryUtil;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.filters.DropShadowFilter;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.Lib;

/**
 * A debug overlay showing useful info.
 */
class FunkinDebugDisplay extends Sprite
{
  static final UPDATE_DELAY:Int = 100;
  static final OTHERS_OFFSET:Int = 8;

  static final ADVANCED_WIDTH:Int = 240;
  static final ADVANCED_BASE_HEIGHT:Int = 104;
  static final ADVANCED_MEM_BLOCK_HEIGHT:Int = 46;
  static final FPS_GRAPH_HEIGHT:Int = 34;
  static final MEM_GRAPH_HEIGHT:Int = 22;

  static final PANEL_RADIUS:Int = 8;
  static final ACCENT_HEIGHT:Int = 3;
  static final COLOR_PANEL:Int = 0x14171A;
  static final COLOR_PANEL_BORDER:Int = 0x2E3338;
  static final COLOR_TEXT_DIM:Int = 0xB4BCC4;

  /**
   * Accent colors, picked by how close the FPS is to the target framerate.
   */
  static final COLOR_GOOD:Int = 0x43E97B;
  static final COLOR_OKAY:Int = 0xFFC145;
  static final COLOR_BAD:Int = 0xFF4D6D;

  /**
   * Graph colors for the memory counters of the advanced display.
   */
  static final COLOR_GC_MEM:Int = 0x5CC8FF;
  static final COLOR_TASK_MEM:Int = 0xB388FF;

  /**
   * Indicates whether the debug display is in advanced mode.
   */
  public var isAdvanced(default, set):Bool = false;

  /**
   * The opacity of the debug display's background.
   */
  public var backgroundOpacity(default, set):Float = 0.5;

  var deltaTimeout:Float;
  var times:Array<Float>;
  var color:Int;
  var fps:Int;
  var fpsPeak:Int;
  var gcMem:Float;
  var gcMemPeak:Float;
  var taskMem:Float;
  var taskMemPeak:Float;
  var background:Shape;
  var accent:Shape;
  var accentColor:Int = -1;
  var panelWidth:Float = 0;
  var fpsText:TextField;
  var statsText:TextField;
  var fpsGraph:FunkinStatsGraph;
  var gcMemGraph:FunkinStatsGraph;
  var taskMemGraph:FunkinStatsGraph;
  var infoDisplay:TextField;

  public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000):Void
  {
    super();

    this.x = x;
    this.y = y;

    this.deltaTimeout = 0.0;
    this.times = [];
    this.color = color;

    this.fps = 0;
    this.fpsPeak = 0;
    this.gcMem = 0.0;
    this.gcMemPeak = 0.0;
    this.taskMem = 0.0;
    this.taskMemPeak = 0.0;

    this.backgroundOpacity = 0;
    this.isAdvanced = false;
  }

  function buildDebugDisplay(advanced:Bool):Void
  {
    removeChildren(0, numChildren);

    var memLines:Int = (MemoryUtil.supportsGCMem() ? 1 : 0) + (MemoryUtil.supportsTaskMem() ? 1 : 0);

    var panelHeight:Float;
    if (advanced)
    {
      panelWidth = ADVANCED_WIDTH;
      panelHeight = ADVANCED_BASE_HEIGHT + (memLines * ADVANCED_MEM_BLOCK_HEIGHT);
    }
    else
    {
      panelWidth = memLines > 0 ? 210 : 140;
      panelHeight = 46 + (memLines * 15);
    }

    background = new Shape();
    background.graphics.lineStyle(1, COLOR_PANEL_BORDER, 1);
    background.graphics.beginFill(COLOR_PANEL, 1);
    background.graphics.drawRoundRect(0, 0, panelWidth, panelHeight, PANEL_RADIUS * 2, PANEL_RADIUS * 2);
    background.graphics.endFill();
    background.alpha = backgroundOpacity;
    addChild(background);

    accent = new Shape();
    accentColor = -1;
    addChild(accent);
    updateAccent();

    if (advanced)
    {
      createAdvancedElements();
      updateAdvancedDisplay();
    }
    else
    {
      createSimpleElements();
      updateSimpleDisplay();
    }
  }

  function createAdvancedElements():Void
  {
    createFpsText();

    // Min / average / peak FPS, dimmed below the big number.
    statsText = createDimText(OTHERS_OFFSET + 2, 42);
    addChild(statsText);

    var graphsWidth:Int = ADVANCED_WIDTH - (OTHERS_OFFSET * 2) - 4;
    var graphY:Int = 60;

    fpsGraph = new FunkinStatsGraph(OTHERS_OFFSET, graphY, graphsWidth, FPS_GRAPH_HEIGHT, accentColor);
    fpsGraph.textDisplay.visible = false;
    fpsGraph.minValue = 0;
    addChild(fpsGraph);
    graphY += FPS_GRAPH_HEIGHT + 24;

    if (MemoryUtil.supportsGCMem())
    {
      gcMemGraph = new FunkinStatsGraph(OTHERS_OFFSET, graphY, graphsWidth, MEM_GRAPH_HEIGHT, COLOR_GC_MEM);
      gcMemGraph.minValue = 0;
      addChild(gcMemGraph);
      graphY += MEM_GRAPH_HEIGHT + 24;
    }

    if (MemoryUtil.supportsTaskMem())
    {
      taskMemGraph = new FunkinStatsGraph(OTHERS_OFFSET, graphY, graphsWidth, MEM_GRAPH_HEIGHT, COLOR_TASK_MEM);
      taskMemGraph.minValue = 0;
      addChild(taskMemGraph);
    }
  }

  /**
   * Creates the big FPS number, followed by a small "FPS" label and the frame time.
   */
  function createFpsText():Void
  {
    fpsText = createDimText(OTHERS_OFFSET + 2, ACCENT_HEIGHT + 2);
    fpsText.autoSize = LEFT;
    fpsText.defaultTextFormat = new TextFormat('_sans', 12, COLOR_TEXT_DIM, true);
    addChild(fpsText);
  }

  /**
   * Creates a small dimmed text field with a drop shadow, so it stays readable on any background.
   */
  function createDimText(x:Float, y:Float):TextField
  {
    var text:TextField = new TextField();
    text.x = x;
    text.y = y;
    text.width = panelWidth - (OTHERS_OFFSET * 2);
    text.selectable = false;
    text.mouseEnabled = false;
    text.defaultTextFormat = new TextFormat('_sans', 11, COLOR_TEXT_DIM);
    text.antiAliasType = NORMAL;
    text.multiline = true;
    text.filters = [new DropShadowFilter(1, 45, 0x000000, 0.9, 2, 2, 1.5)];
    return text;
  }

  function createSimpleElements():Void
  {
    createFpsText();

    // Memory counters, dimmed below the FPS.
    infoDisplay = createDimText(OTHERS_OFFSET + 2, 42);
    addChild(infoDisplay);
  }

  /**
   * Picks the accent color from how close the current FPS is to the target framerate.
   */
  function getStatusColor():Int
  {
    var target:Float = (Lib.current.stage != null) ? Lib.current.stage.frameRate : 60;
    // An uncapped framerate reports 0, so treat anything below 60 as a 60 FPS target.
    if (target < 60) target = 60;

    var ratio:Float = fps / target;
    if (ratio >= 0.9) return COLOR_GOOD;
    if (ratio >= 0.6) return COLOR_OKAY;
    return COLOR_BAD;
  }

  /**
   * Redraws the colored stripe on top of the panel, if the status color changed.
   */
  function updateAccent():Void
  {
    var newColor:Int = getStatusColor();
    if (newColor == accentColor) return;
    accentColor = newColor;

    accent.graphics.clear();
    accent.graphics.beginFill(accentColor, 1);
    accent.graphics.drawRoundRect(PANEL_RADIUS, 0, panelWidth - (PANEL_RADIUS * 2), ACCENT_HEIGHT, 3, 3);
    accent.graphics.endFill();
  }

  override function __enterFrame(deltaTime:Float):Void
  {
    var currentTime:Float = Lib.getTimer();

    times.push(currentTime);

    while (times[0] < currentTime - Constants.MS_PER_SEC)
    {
      times.shift();
    }

    if (deltaTimeout < UPDATE_DELAY)
    {
      deltaTimeout += deltaTime;
      return;
    }

    fps = times.length;

    if (fps > fpsPeak) fpsPeak = fps;

    if (MemoryUtil.supportsGCMem())
    {
      gcMem = MemoryUtil.getGCMemory();

      if (gcMem > gcMemPeak) gcMemPeak = gcMem;
    }

    if (MemoryUtil.supportsTaskMem())
    {
      taskMem = MemoryUtil.getTaskMemory();

      if (taskMem > taskMemPeak) taskMemPeak = taskMem;
    }

    updateAccent();

    if (isAdvanced)
    {
      updateAdvancedDisplay();
    }
    else
    {
      updateSimpleDisplay();
    }

    deltaTimeout = 0.0;
  }

  function updateAdvancedDisplay():Void
  {
    updateFPSGraph();
    updateGcMemGraph();
    updateTaskMemGraph();

    updateFpsText();

    statsText.text = 'AVG ${Math.floor(fpsGraph.average())}    MIN ${Math.floor(fpsGraph.lowest())}    PEAK $fpsPeak';

    if (gcMemGraph != null)
    {
      gcMemGraph.textDisplay.text = 'GC MEM  ${FlxStringUtil.formatBytes(gcMem).toLowerCase()} / ${FlxStringUtil.formatBytes(gcMemPeak).toLowerCase()}';
    }

    if (taskMemGraph != null)
    {
      taskMemGraph.textDisplay.text = 'TASK MEM  ${FlxStringUtil.formatBytes(taskMem).toLowerCase()} / ${FlxStringUtil.formatBytes(taskMemPeak).toLowerCase()}';
    }
  }

  /**
   * Updates the big FPS number, colored by the current status, and the frame time.
   */
  function updateFpsText():Void
  {
    if (fpsText == null) return;

    var digits:String = Std.string(fps);
    var frameTime:Float = fps > 0 ? Math.round(Constants.MS_PER_SEC / fps * 10) / 10 : 0;

    fpsText.text = '$digits FPS   $frameTime ms';
    fpsText.setTextFormat(new TextFormat('_sans', 28, accentColor, true), 0, digits.length);
  }

  function updateSimpleDisplay():Void
  {
    updateFpsText();

    if (infoDisplay != null)
    {
      var info:Array<String> = [];

      if (MemoryUtil.supportsGCMem())
      {
        info.push('GC MEM: ${FlxStringUtil.formatBytes(gcMem).toLowerCase()} / ${FlxStringUtil.formatBytes(gcMemPeak).toLowerCase()}');
      }

      if (MemoryUtil.supportsTaskMem())
      {
        info.push('TASK MEM: ${FlxStringUtil.formatBytes(taskMem).toLowerCase()} / ${FlxStringUtil.formatBytes(taskMemPeak).toLowerCase()}');
      }

      infoDisplay.text = info.join('\n');
    }
  }

  function updateFPSGraph():Void
  {
    fpsGraph.graphColor = accentColor;
    fpsGraph.maxValue = fpsPeak;
    fpsGraph.update(fps);
  }

  function updateGcMemGraph():Void
  {
    if (gcMemGraph != null)
    {
      gcMemGraph.maxValue = gcMemPeak;
      gcMemGraph.update(gcMem);
    }
  }

  function updateTaskMemGraph():Void
  {
    if (taskMemGraph != null)
    {
      taskMemGraph.maxValue = taskMemPeak;
      taskMemGraph.update(taskMem);
    }
  }

  function set_isAdvanced(value:Bool):Bool
  {
    buildDebugDisplay(value);

    return isAdvanced = value;
  }

  function set_backgroundOpacity(value:Float):Float
  {
    if (background != null) background.alpha = value;

    return backgroundOpacity = value;
  }
}

// Note: the string values here are deduced
// so we dont need to do `Off = 'Off'` or nothin
// https://haxe.org/manual/types-abstract-enum.html

enum abstract DebugDisplayMode(String) from String to String
{
  /**
   * Debug display is disabled.
   */
  public var Off;

  /**
   * Simple debug display.
   * FPS and Memory counters only.
   */
  public var Simple;

  /**
   * Advanced debug display.
   * Full FPS and Memory info.
   */
  public var Advanced;
}
