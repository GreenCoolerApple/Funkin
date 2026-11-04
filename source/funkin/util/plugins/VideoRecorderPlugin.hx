package funkin.util.plugins;

#if FEATURE_VIDEO_RECORDING
import flixel.FlxBasic;
import flixel.FlxG;
import funkin.audio.FunkinSound;
import funkin.external.windows.VideoRecorder;
import funkin.util.WindowUtil;
import funkin.util.logging.CrashHandler;

/**
 * A Flixel plugin which records videos of the game window, similar to the `ScreenshotPlugin`.
 * Press `F7` to start recording and press it again to stop. Hold `SHIFT` and press it to open the videos folder.
 *
 * The frames and the sound of the game are captured and encoded to an MP4 file in native code (see `VideoRecorder`).
 */
@:nullSafety
class VideoRecorderPlugin extends FlxBasic
{
  /**
   * The folder where videos are saved.
   */
  public static final VIDEO_FOLDER:String = 'videos';

  /**
   * The frame rate of the recorded videos.
   * If the game runs faster, only some of its frames are captured.
   */
  public static final VIDEO_FPS:Int = 60;

  /**
   * Whether a video is being recorded right now.
   */
  public var isRecording(default, null):Bool = false;

  /**
   * How long the current video is, in seconds.
   */
  public var recordingTime(default, null):Float = 0.0;

  var captureTimer:Float = 0.0;
  var shownSeconds:Int = -1;
  var titleBeforeRecording:String = '';

  /**
   * Initialize the video recorder plugin.
   */
  public static function initialize():Void
  {
    FlxG.plugins.addPlugin(new VideoRecorderPlugin());
  }

  public function new()
  {
    super();

    // Called when clicking the X button on the window.
    WindowUtil.windowExit.add(onWindowClose);

    // Called when the game crashes.
    CrashHandler.errorSignal.add(onWindowCrash);
    CrashHandler.criticalErrorSignal.add(onWindowCrash);
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);

    if (hasPressedRecord())
    {
      if (FlxG.keys.pressed.SHIFT) openVideosFolder();
      else if (isRecording) stopRecording();
      else
        startRecording();
    }

    if (isRecording) updateRecording(elapsed);
  }

  /**
   * @return `true` if the record key is currently pressed.
   */
  public function hasPressedRecord():Bool
  {
    return PlayerSettings.player1.controls.WINDOW_RECORD;
  }

  /**
   * Starts recording the game window to a new file in the videos folder.
   */
  public function startRecording():Void
  {
    if (isRecording) return;

    FileUtil.createDirIfNotExists(VIDEO_FOLDER);
    final path:String = sys.FileSystem.absolutePath('$VIDEO_FOLDER/video-${DateUtil.generateTimestamp()}.mp4');

    final window:lime.ui.Window = FlxG.stage.window;
    final width:Int = Std.int(window.width * window.scale);
    final height:Int = Std.int(window.height * window.scale);

    if (!VideoRecorder.start(path, width, height, VIDEO_FPS, true))
    {
      trace(' WARNING '.warning() + ' Failed to start recording a video to: $path');
      return;
    }

    trace('Recording a video to: $path (${VideoRecorder.hasAudio() ? 'with sound' : 'without sound'})');

    isRecording = true;
    recordingTime = 0.0;
    captureTimer = 0.0;
    shownSeconds = -1;
    titleBeforeRecording = window.title;

    FunkinSound.playOnce(Paths.sound('screenshot'), 1.0);
  }

  /**
   * Stops recording and finishes the video file.
   */
  public function stopRecording():Void
  {
    if (!isRecording) return;
    isRecording = false;

    final frames:Int = VideoRecorder.getFrameCount();
    final dropped:Int = VideoRecorder.getDroppedFrames();

    // Waits for the frames that are still queued to be encoded, then closes the file.
    VideoRecorder.stop();

    trace('Finished recording a video: $frames frames, $dropped dropped.');

    FlxG.stage.window.title = titleBeforeRecording;

    FunkinSound.playOnce(Paths.sound('screenshot'), 1.0);
  }

  function updateRecording(elapsed:Float):Void
  {
    recordingTime += elapsed;
    captureTimer += elapsed;

    // The game can run faster than the video, so only some of the frames are captured.
    // A frame that comes slightly early still counts, so a game running at the same speed as the video does not skip frames.
    final frameTime:Float = 1.0 / VIDEO_FPS;
    if (captureTimer >= frameTime * 0.9)
    {
      // If the game is slower than the video, do not try to make up for the lost frames.
      captureTimer = Math.min(Math.max(captureTimer - frameTime, 0.0), frameTime);

      final window:lime.ui.Window = FlxG.stage.window;
      VideoRecorder.capture(Std.int(window.width * window.scale), Std.int(window.height * window.scale));
    }

    // Show that a video is being recorded in the title of the window, which is not part of the video.
    // This is repeated, since states can change the title.
    final seconds:Int = Std.int(recordingTime);
    if (seconds != shownSeconds || !StringTools.contains(FlxG.stage.window.title, 'REC'))
    {
      shownSeconds = seconds;
      FlxG.stage.window.title = '${titleBeforeRecording}  -  REC ${formatTime(seconds)}';
    }
  }

  static function formatTime(totalSeconds:Int):String
  {
    final minutes:Int = Std.int(totalSeconds / 60);
    final seconds:Int = totalSeconds % 60;
    return '${StringTools.lpad(Std.string(minutes), '0', 2)}:${StringTools.lpad(Std.string(seconds), '0', 2)}';
  }

  function openVideosFolder():Void
  {
    FileUtil.createDirIfNotExists(VIDEO_FOLDER);
    FileUtil.openFolder(VIDEO_FOLDER);
  }

  function onWindowClose(exitCode:Int):Void
  {
    // Without this the video would not be playable, as the end of the file is written when stopping.
    stopRecording();
  }

  function onWindowCrash(message:String):Void
  {
    stopRecording();
  }

  override public function destroy():Void
  {
    stopRecording();

    if (FlxG.plugins.list.contains(this)) FlxG.plugins.remove(this);

    WindowUtil.windowExit.remove(onWindowClose);
    CrashHandler.errorSignal.remove(onWindowCrash);
    CrashHandler.criticalErrorSignal.remove(onWindowCrash);

    super.destroy();
  }
}
#end
