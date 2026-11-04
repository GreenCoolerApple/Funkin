# Recording videos

Funkin' Revival can record videos of the game window, with the sound of the game, similar to how screenshots work. This is only available on Windows.

| Key | What it does |
| --- | --- |
| `F7` | Starts recording. Press it again to stop. |
| `Shift` + `F7` | Opens the `videos` folder. |

Videos are saved as H.264 and AAC MP4 files in the `videos` folder next to the game, as `video-<date>.mp4`.
While recording, the title of the window shows `REC` and how long the video is. Nothing is drawn on the game itself, so it does not show up in the video.

The key can be changed in the Controls menu, under the window controls.

## Limits

- Videos are recorded at 60 frames per second. If the game runs slower than that, the video has the frames the game could show.
- The sound is only what the game plays, not other programs. This needs Windows 10 (build 20348) or later, such as Windows 11. On older versions the video has no sound.
- The video has the size the window had when recording started, rounded down to an even number. If the window is resized while recording, the picture is stretched to fit.
- If the computer cannot encode fast enough, some frames are skipped instead of slowing the game down.
- Press `F7` again to stop recording before closing the game. A video is only playable once it is finished (closing the game or a crash also finish it).

## How it works

The `VideoRecorderPlugin` (Haxe) handles the key and the timing. Everything else is native code in `source/funkin/external/windows/project/src/videorecorder.cpp`:

- Each frame is read from the OpenGL framebuffer on the render thread.
- The frames are queued and encoded on a separate thread by Windows Media Foundation, using the graphics card when it can.
- The sound is captured by a second thread with the per-process loopback of Windows, which only hears this game, and encoded to AAC. The video and the sound use the same clock, and when the game is silent the gap is filled, so they stay in sync.
- Stopping waits for the queued frames, then writes the end of the file. If the game closes or crashes while recording, the recording is stopped first so the video stays playable.

It is enabled by the `FEATURE_VIDEO_RECORDING` flag, which is on for Windows builds.
