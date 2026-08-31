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

**It does a decent enough job at replicating the native functions of an OC GPU, although some have yet to be added.**
- SetPixel() and Fill() work very similarly to their native counterparts, except they do not handle text.
  Pixel-space in Chugraph is propped up to be double-height, as to supply the user with proper square pixels
  Text cannot be displayed on a sub-pixel level, so SetText() acts as a solution to that problem.
- SetText() is your means of setting text on the screen. There is one caveat however:
  The coordinates can be a bit finicky. It's been a while since I had to place a string somewhere specific so you may have to play with it a bit to get some text set where you want it to go.
  
**As for non-native functions, there are quite a few:**
- ClearScreen() and ClearRegion() are a faster way to clear the screen than Fill()
- GetScreenWidth() and GetScreenHeight() returns the "functional" dimensions of the screen, as Chugraph sees it. (double-height applied)
- DrawLine() draws a line between two points
- DrawTriangle() draws a triangle between three points
- FillTriangle() fills a triangle between three points

**To show your beautiful drawing on the screen, you must use UpdateScreen()**
- Chugraph is single-buffered, so I very much recommend clearing the screen and redrawing each frame. This may sound terrible, but unless you're rendering a very chaotic screen, Chugraph can handle it.

**Useful command line args:**

| arg | outcome |
|--------|--|
| -d  | Enables demo mode, only shows debug stats. use with an addition arg below to show some stuff |
| -w  | (Epilepsy Warning) Continuously draws 350 randomly placed white lines per frame, works as a stress test for two-color rendering situations |
| -c  | (Epilepsy Warning, **seriously**) continuously draws 350 randomly placed RGB + CMY + White lines per frame, works as a stress test for essentially random noise for extremely taxing rendering situations |
| -p  | Prints 256 colors in a neat rectangle |

**The debug panel shows a few helpful stats that may aid in your own optimization efforts:**
| Item | What it means |
|------|--|
| FPS | The average frames-per-second over the last 50 frames |
| PIXU | The amount of times a pixel was set into the screen buffer in the previous frame |
| INVR  | Renders the depth buffer |
| SET  | How many times a compiled draw string was inverted in the previous frame, to save on having to swap foreground and background colors |
| FILL  | How many times gpu.set() was called in the previous frame |
| SFORE  | How many times gpu.setForeground() was called in the previous frame |
| SBACK  | How many times gpu.setBackground() was called in the previous frame |
| CPU  | How long the CPU was active in the previous frame, also shows a rolling average of the previous 50 frames |
| GPU  | A poor attempt at estimating the call budget usage for the GPU. Can safely disregard, but may come in handy sometimes |
| FRAME  | How long its been since the last frame was displayed on screen. This will usually hover around multiples of 50ms, as that is the length of a tick. |
| MEM  | The amount of memory used in the last frame. Pretty unreadable, I suggest looking at the rolling average. |

Proper documentation for Chugraph will come sometime in the future.

## Chugkey
I was sick of writing the same code over and over again to check which keys were pressed, so I wrote Chugkey.
Chugkey keeps track of which keys are being held in a Key Value table.
- isKeyDown(self, keyString) returns a bool telling you if the key is pressed.
  I only have it working for standard keys, and for arrow keys. This will be expanded sometime in the future

Chugkey is suboptimal, as keypresses sometimes lag behind. Still quite handy for test benching.

## Chug3D
A fairly quick .obj renderer, as long as the tricount is a tad low

If you thought Chugraph was unreadable, I recommend not taking a peek into the code for Chug3D

The codebase for this originated from a tutorial by Javidx9 on YouTube (https://youtu.be/ih20l3pJoeU), then was optimized (a lot) for a low memory Lua environment.

**Chug3D requires both Chugkey and Chuggraph to run**

At the moment, loading .obj files with some command line arguments is _**all**_ this does. It may be expanded into something more in the future, but that mostly depends on how much more I can optimize.

**USAGE**
- Move an .obj file into the same folder as Chug3D
- Run "chug3d --model=[objfilename]"
- If you've done everything correctly, you should now have a 3d model rendering in a minecraft computer. Very awesome.
- If you get the cube, something has gone wrong. My .obj parser does not account for all possible options, so you may have to re-export it in blender with some of the extra features turned off.
- Also, this only supports triangulated meshes, but this will likely change in the future

**MOVEMENT**

You can translate around the scene using WASD and rotate using arrow keys. That's right folks, Doom is back on the menu.

**COMMAND LINE ARGS**
| arg | outcome |
|--------|--|
| --back=[hexcolor]  | Changes the background of the scene. Example: "--back=0xFF0000" (Red background) |
| -n  | Renders the surface normal of each triangle as a color, based on the normal's xyz values |
| -d  | Renders the depth buffer |
| -s  | Shades the model based on the surface normal's alignment with the light direction normal (Light direction is facing roughly the same as the camera's starting direction) |
| -b  | Blends the model into the background color using that pixel's depth buffer value. Can be combined with -s for a cool (yet laggy) render |
| -r  | Rotates the model on all 3 axis. If you want to pick which axis the model spins on, you can specify with -x, -y, and -z. |
| -w  | Renders the wireframe over the rasterized triangles |
| -f  | Grayscale flat shading based on per-triangle light value |

**PERFORMANCE**

I am quite proud of how far this project has come performance-wise, its almost 6x faster than when I finished the tutorial the original code was based on. That performance came at the cost of readability though, and I apologize if you were looking towards this code for some form of guidance. I'm not that great of a coder anyways, actually I'm pretty bad.

All things considered, most of the nerfs to readability come from memory optimizations. I love OpenComputers, but why are we sticking such a garbage-producing language into a computer with only 2MB of memory? I mean come on.


