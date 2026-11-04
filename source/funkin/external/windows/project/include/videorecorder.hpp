#pragma once

/**
 * Records the game window, and the sound of the game, to an H.264 and AAC MP4 file, using Windows Media Foundation.
 *
 * Frames are grabbed from the OpenGL framebuffer on the calling (render) thread,
 * queued, and encoded on a separate thread, so recording does not stall the game.
 * The sound is captured from the game process only, using the per-process loopback of Windows 10 (build 20348) and later.
 * On older versions the video is recorded without sound.
 */

/**
 * Starts recording to the given file.
 * @param path The output file, as a UTF-8 string. It should end with `.mp4`.
 * @param width The width of the frames that will be captured, in pixels.
 * @param height The height of the frames that will be captured, in pixels.
 * @param fps The frame rate of the video.
 * @param audio Whether to record the sound of the game too.
 * @return `true` if recording started.
 */
bool VIDEORECORDER_Start(const char* path, int width, int height, int fps, bool audio);

/**
 * Captures the current OpenGL framebuffer as the next frame of the video.
 * Must be called from the thread that owns the OpenGL context.
 * @param width The width of the framebuffer, in pixels.
 * @param height The height of the framebuffer, in pixels.
 * @return `true` if the frame was queued, `false` if it was dropped.
 */
bool VIDEORECORDER_Capture(int width, int height);

/**
 * Queues a frame of pixels as the next frame of the video.
 * @param bgra The pixels, as 4 bytes each (blue, green, red, unused), with the bottom row first.
 * @param width The width of the frame, in pixels.
 * @param height The height of the frame, in pixels.
 * @return `true` if the frame was queued, `false` if it was dropped.
 */
bool VIDEORECORDER_WriteFrame(const unsigned char* bgra, int width, int height);

/**
 * Finishes the video and closes the file. Waits for the queued frames to be encoded.
 */
void VIDEORECORDER_Stop();

/**
 * @return `true` while a video is being recorded.
 */
bool VIDEORECORDER_IsRecording();

/**
 * @return `true` if the video being recorded has sound.
 */
bool VIDEORECORDER_HasAudio();

/**
 * @return How many frames have been queued since recording started.
 */
int VIDEORECORDER_GetFrameCount();

/**
 * @return How many frames were dropped because the encoder could not keep up.
 */
int VIDEORECORDER_GetDroppedFrames();
