# Chug-Library for OpenComputers
##### plus some other stuff eventually
____
# Chug-Lib

Chug-Lib is a library of utility scripts I have made to improve my programming workflow. At the moment there is not much, but more is coming soon.
As for what does exist, here is a quick rundown:

## Chugraph
Chugraph is my solution to a terribly slow GPU, and a slightly less terribly slow vram buffer.

Its also a tad memory-hungry. I've done all the insane memory saving I could think of, and it still eats up around 300kb of ram when doing absolutely nothing.
But this is because all drawing is first entered into an array holding data for the entire screen. This speeds up the drawing process dramatically, so Chugraph can eat all the memory it wants.
That being said, further optimization is a constant goal.

It does a decent enough job at replicating the native functions of an OC GPU, although some have yet to be added.
- SetPixel() and Fill() work very similarly to their native counterparts, except they do not handle text.
  Pixel-space in Chugraph is propped up to be double-height, as to supply the user with proper square pixels
  Text cannot be displayed on a sub-pixel level, so SetText() acts as a solution to that problem.
- SetText() is your means of setting text on the screen. There is one caveat however:
  The coordinates can be a bit finicky. It's been a while since I had to place a string somewhere specific so you may have to play with it a bit to get some text set where you want it to go.
  
As for non-native functions, there are quite a few:
- ClearScreen() and ClearRegion() are a faster way to clear the screen than Fill()
- GetScreenWidth() and GetScreenHeight() returns the "functional" dimensions of the screen, as Chugraph sees it. (double-height applied)
- DrawLine() draws a line between two points
- DrawTriangle() draws a triangle between three points
- FillTriangle() fills a triangle between three points

To show your beautiful drawing on the screen, you must use UpdateScreen()
Chugraph is single-buffered, so I very much recommend clearing the screen and redrawing each frame. This may sound terrible, but unless you're rendering a very chaotic screen, Chugraph can handle it.

Useful command line args:

-d starts demo mode, only shows debug stats. use with either -w or -c to show some stuff

-w (epilepsy warning) continuously draws 350 randomly placed white lines per frame, works as a stress test for two-color rendering situations

-c (epilepsy warning, seriously) continuously draws 350 randomly placed RGB + CMY + White lines per frame, works as a stress test for essentially random noise for extremely taxing rendering situations

-p Prints 256 colors in a neat rectangle

The debug panel shows a few helpful stats that may aid in your own optimization efforts. To fit into a reasonably-sized area, I have shortened the names of many the variables. The extended versions are as follows:
- FPS: Your average frames-per-second over the last 50 frames
- PIXU: The amount of times a pixel was set into the screen buffer in the previous frame
- INVR: How many times a compiled draw string was inverted in the previous frame, to save on having to swap foreground and background colors
- SET: How many times gpu.set() was called in the previous frame
- FILL: How many times gpu.fill() was called in the previous frame
- SFORE: How many times gpu.setForeground() was called in the previous frame
- SBACK: How many times gpu.setBackground() was called in the previous frame
- CPU: How long the CPU was active in the previous frame, also shows a rolling average of the previous 50 frames
- GPU: A poor attempt at estimating the call budget usage for the GPU. Can safely disregard, but may come in handy sometimes
- FRAME: How long its been since the last frame was displayed on screen. This will usually hover around multiples of 50ms, as that is the length of a tick. The rolling average gives you a better idea of how close you are to breaking into the next framerate milestone.
- MEM: The amount of memory used in the last frame. Pretty unreadable, I suggest looking at the rolling average.

Proper documentation for Chugraph will come sometime in the future.

## Chugkey
I was sick of writing the same code over and over again to check which keys were pressed, so I wrote Chugkey.
Chugkey keeps track of which keys are being held in a Key Value table.
- isKeyDown(self, keyString) returns a bool telling you if the key is pressed.
  I only have it working for standard keys, and for arrow keys. This will be expanded sometime in the future

Chugkey is suboptimal, as keypresses sometimes lag behind. Still quite handy for test benching.
