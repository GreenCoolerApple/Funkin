package funkin.external.windows;

#if (windows && cpp)
/**
 * Records the game window, and the sound of the game, to an H.264 and AAC MP4 file, in native code, using Windows Media Foundation.
 *
 * Frames are read from the OpenGL framebuffer and encoded on a separate thread, so recording does not stall the game.
 * The sound is captured from the game process only, which needs Windows 10 (build 20348) or later. On older versions the video has no sound.
 */
@:build(funkin.util.macro.LinkerMacro.xml('project/Build.xml')) @:include('videorecorder.hpp')
extern class VideoRecorder
{
  /**
   * Starts recording to a file.
   * @param path The file to write, which should end with `.mp4`.
   * @param width The width of the frames that will be captured, in pixels.
   * @param height The height of the frames that will be captured, in pixels.
   * @param fps The frame rate of the video.
   * @param audio Whether to record the sound of the game too.
   * @return `true` if recording started.
   */
  @:native('VIDEORECORDER_Start')
  static function start(path:cpp.ConstCharStar, width:Int, height:Int, fps:Int, audio:Bool):Bool;

  /**
   * Captures the game window as the next frame of the video.
   * Must be called from the main thread, which owns the OpenGL context.
   * @param width The width of the window, in pixels.
   * @param height The height of the window, in pixels.
   * @return `true` if the frame was queued, `false` if it was dropped.
   */
  @:native('VIDEORECORDER_Capture')
  static function capture(width:Int, height:Int):Bool;

  /**
   * Finishes the video and closes the file. Waits for the queued frames to be encoded.
   */
  @:native('VIDEORECORDER_Stop')
  static function stop():Void;

  /**
   * @return `true` while a video is being recorded.
   */
  @:native('VIDEORECORDER_IsRecording')
  static function isRecording():Bool;

  /**
   * @return `true` if the video being recorded has sound.
   */
  @:native('VIDEORECORDER_HasAudio')
  static function hasAudio():Bool;

  /**
   * @return How many frames have been queued since recording started.
   */
  @:native('VIDEORECORDER_GetFrameCount')
  static function getFrameCount():Int;

  /**
   * @return How many frames were dropped because the encoder could not keep up.
   */
  @:native('VIDEORECORDER_GetDroppedFrames')
  static function getDroppedFrames():Int;
}
#end
